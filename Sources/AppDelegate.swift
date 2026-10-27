import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var statusItem: NSStatusItem!
    private var panel: ReminderPanel?
    private var hosting: NSHostingView<MascotCard>?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    private let prefs = Prefs.shared
    private let model = ReminderModel()
    private let animator = MascotAnimator()

    private var tickTimer: Timer?
    private var escalateTimer: Timer?
    private var wanderTimer: Timer?
    /// 强提醒阶段贴光标用的定时器
    private var chaseTimer: Timer?
    /// 视线跟随用的定时器。15fps 够用，比动作循环低一档，省电。
    private var gazeTimer: Timer?
    /// 最近的戳击时间，用来判断「连戳三次」
    private var pokeTimes: [Date] = []
    /// 最后一次「用户动手干预」的时刻：拖动卡片、连戳到躲闪。
    /// 自动行为（游走 / 追光标）在这之后的一小段静默期内不抢窗口位置，
    /// 免得用户刚把它挪开、它自己又溜回去。
    private var lastManualMoveAt = Date.distantPast

    /// 判定机：累计、离开结算、静默、待补发全在它里面，这里只负责把系统信号喂进去、
    /// 再按它吐出来的事实去弹窗。逻辑抽成纯函数是为了能跑时间轴用例（Tools/run_tests.sh）。
    private var machine = PresenceMachine()
    /// 上一条 tick 的时刻，用来算真实间隔——定时器会被 App Nap 拉长，不能假设每秒一次
    private var lastTickAt = Date()
    /// 上次落盘时刻
    private var lastPersistAt = Date.distantPast
    /// 最近一次读到的空闲秒数，菜单文案用
    private var lastIdle: TimeInterval = 0

    private var panelVisible = false
    private var pauseUntil: Date?
    private var todayCount = 0
    private var countDay = Date()

    private var wanderDirection: CGFloat = 1
    private var wanderRect: NSRect = .zero
    /// 弹窗与游走共用的目标屏幕，避免中途切换导致跳屏
    private var activeScreen: NSScreen?

    /// 程序自己把面板挪到的位置。
    ///
    /// AppKit 对「定时器挪窗口」和「用户拖窗口」发的是**同一个**
    /// didMoveNotification，通知里也不带任何来源信息（有测试：
    /// Tools/MoveNotifyTest）。游走是 30fps，等于每秒发 30 次这个通知，
    /// 所以处理函数必须自己区分来源，否则每一帧都在猜「是不是用户在拖」。
    ///
    /// 判据就是这个坐标：位置正好等于我们上一帧设的点 → 是我自己挪的。
    private var autoMovedTo = NSPoint(x: CGFloat.greatestFiniteMagnitude,
                                      y: CGFloat.greatestFiniteMagnitude)
    /// 带插值的动画（躲闪）期间，中途每一帧的坐标都不是终点，
    /// 没法用坐标比对，只能按时间窗把这段时间的通知整体当噪音。
    private var autoMoveUntil = Date.distantPast

    private var meetingBusy = false
    private var lastMeetingCheck = Date.distantPast

    private var focusMenuItem: NSMenuItem!
    private var countMenuItem: NSMenuItem!
    private var streakMenuItem: NSMenuItem!
    private var unlockAllMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    /// 状态栏当前文案，用来避免每秒重复赋值触发重绘
    private var lastStatusTitle = ""
    /// 状态栏临时播报（打卡、解锁），到点自动恢复常驻文案
    private var statusFlash: String?
    private var statusFlashUntil = Date.distantPast
    /// 观察连续天数，解锁的瞬间自动换上形象
    private var streakCancellable: AnyCancellable?
    private var lastKnownStreak = Habits.shared.streak

    /// 面板四周留给阴影的透明边距
    private let panelMargin: CGFloat = 4

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLogin.refreshIfNeeded()

        // 旧版本存下的形象可能还没解锁（或者解锁进度被重置），回落到当前可用的最高档
        let habits = Habits.shared
        if !Unlocks.isUnlocked(prefs.mascotStyle, streak: habits.streak,
                               forceAll: prefs.debugUnlockAll) {
            prefs.mascotStyle = Unlocks.bestUnlocked(streak: habits.streak)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "figure.walk",
                                           accessibilityDescription: "歇会儿")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = " 0m"

        rebuildMenu()
        restoreSession()
        startTick()
        watchUnlocks()

        // 熄屏/系统睡眠的**开始**由通知记时间戳，唤醒时再结算。
        // 不能只靠每秒 tick：屏幕睡着时 App Nap 可能把定时器压慢，
        // 醒来第一次 tick 时「睡着」这个状态已经消失了。
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(noteAwayOnset),
            name: NSWorkspace.screensDidSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(noteAwayOnset),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(presenceChanged),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(presenceChanged),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        // 首次启动弹三屏引导。以前直接开设置页，用户看到一堆 Stepper 不知道这是什么。
        // hasLaunchedBefore 由引导自己写（点跳过也算），这里只负责弹窗。
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.openOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
        escalateTimer?.invalidate()
        wanderTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        // 退出前落一次盘：下次启动能接着显示，而不是眼睁睁看着归零
        persist()
    }

    // MARK: - 习惯反馈

    /// 记录一次打卡，成功跨天时在状态栏播报一下。
    /// 没有反馈的话，用户根本不知道今天已经算过了。
    private func recordHabit() {
        let before = Habits.shared.streak
        Habits.shared.markDoneToday()
        let after = Habits.shared.streak
        guard after > before else { return }
        flashStatus("打卡 \(after)天", seconds: 5)
    }

    /// 解锁瞬间自动换上新形象：等了 15 天还要自己去设置页点一下，成就感就没了。
    private func watchUnlocks() {
        // 以订阅建立那一刻的天数为基准，之前的历史解锁不补播报
        lastKnownStreak = Habits.shared.streak
        streakCancellable = Habits.shared.$streak
            .removeDuplicates()
            .sink { [weak self] streak in
                guard let self else { return }
                let previous = self.lastKnownStreak
                self.lastKnownStreak = streak
                guard streak > previous else { return }

                let fresh = Unlocks.styles
                    .filter { $0.days > 0 && $0.days > previous && $0.days <= streak }
                    .max { $0.days < $1.days }
                guard let fresh else { return }
                self.prefs.mascotStyle = fresh.style
                self.flashStatus("解锁\(fresh.name)", seconds: 6)
            }
    }

    /// 状态栏临时显示一句话，之后自动回到计时文案
    private func flashStatus(_ text: String, seconds: Double) {
        statusFlash = " " + text
        statusFlashUntil = Date().addingTimeInterval(seconds)
        lastStatusTitle = ""
        updateStatus()
    }


    // MARK: - 计时

    private func startTick() {
        let t = Timer(timeInterval: 1.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    /// 熄屏 / 系统睡眠的**瞬间**调用。此时 tick 可能被 App Nap 压住，
    /// 光靠每秒轮询会漏掉「睡着」这个过程，所以由通知把起始时刻记下来。
    @objc private func noteAwayOnset() {
        machine.noteAwayOnset(now: Date().timeIntervalSince1970)
    }

    /// 房间状态可能变了（唤醒、解锁）——立刻走一次心跳完成结算，
    /// 不用等下一秒的定时器（它醒来时可能还被压着）。
    @objc private func presenceChanged() {
        tick()
    }

    private var thresholds: PresenceThresholds {
        PresenceThresholds(focusMinutes: prefs.focusMinutes,
                           strongMinutes: prefs.strongMinutes,
                           silentMinutes: prefs.silentMinutes,
                           longSilentMinutes: prefs.longSilentMinutes)
    }

    @objc private func tick() {
        resetDayIfNeeded()

        let now = Date()
        // 真实间隔，不是「1 秒」。App Nap 会把定时器压成几秒一次，
        // 系统睡眠后第一次 tick 的间隔可能是几小时——这两种都不能按 1 秒记账。
        let delta = now.timeIntervalSince(lastTickAt)
        lastTickAt = now

        let idle = IdleClock.seconds
        lastIdle = idle
        // 熄屏 / 锁屏 = 确凿离开。比拿时长猜人可靠得多。
        let away = Presence.isAway
        refreshMeetingState(idle: idle, away: away)

        let event = machine.step(
            now: now.timeIntervalSince1970,
            input: PresenceInput(
                idle: idle,
                away: away,
                inMeeting: prefs.meetingAware && meetingBusy,
                delta: delta,
                panelVisible: panelVisible,
                // 暂停 / 免打扰 / 今日已满只拦「弹不弹」，不拦记账
                canRemind: !isPaused() && !prefs.inQuietHours() && todayCount < prefs.dailyCap
            ),
            thresholds: thresholds
        )

        if event.settledAway {
            if event.shouldRecordHabit { recordHabit() }
            hideReminder()
        }

        if event.shouldShowReminder {
            showReminder(deferred: event.reminderIsDeferred)
        }

        // 静默结束（手回来了）补上克制期间欠下的升级计时
        if panelVisible, event.silenceEnded, escalateTimer == nil,
           model.urgency == .soft, model.stage == .sitting {
            startEscalation()
        }

        if panelVisible, model.urgency == .soft, !machine.inSilence,
           machine.focusSeconds >= thresholds.strong {
            upgradeToStrong()
        }

        // 游走自愈：该动却停着，就重新装上。
        //
        // 停游走的路径有三条（用户拖走、连戳躲闪、升级强提醒），将来还可能
        // 加第四条。要求每条路径都记得自己善后，漏一个就是「卡片定在原地
        // 再也不动」—— 而这正是用户最先能看见的故障。与其靠每条路径自觉，
        // 不如每秒问一次「现在该不该动」，成本是一次判断。
        //
        // 1.5 秒的静默期是留给手动干预的：刚被拖过就先别抢回来。
        if panelVisible, model.urgency == .soft, model.stage == .stretching,
           prefs.wanderEnabled, wanderTimer == nil, chaseTimer == nil,
           Date().timeIntervalSince(lastManualMoveAt) > 1.5 {
            startWandering()
        }

        persistIfNeeded(now)
        updateStatus()
    }

    // MARK: - 落盘

    /// 大约每 10 秒写一次（1 秒粒度的定时器，实际落在 11 秒左右）。
    /// 崩溃最多丢十几秒，比「重启从 0 开始」好太多。
    private func persistIfNeeded(_ now: Date) {
        guard now.timeIntervalSince(lastPersistAt) >= 10 else { return }
        persist(at: now)
    }

    private func persist(at now: Date = Date()) {
        SessionStore.save(SessionStore.Snapshot(
            focusSeconds: machine.focusSeconds,
            daySitSeconds: machine.daySitSeconds,
            todayCount: todayCount
        ))
        // 记基准时用 tick 的时刻，不能用 Date()——否则每次都会晚几毫秒，
        // 攒够一圈实际间隔就变成 12 秒了
        lastPersistAt = now
    }

    /// 启动时续上。**只拿回数字，不补间隙**——关闭期间发生了什么我们一概不知，
    /// 把那段算进去就是编造，而编造出来的分钟数正是让人不再相信这个工具的东西。
    private func restoreSession() {
        guard let snapshot = SessionStore.load() else { return }
        let restored = SessionStore.restore(snapshot)
        todayCount = restored.todayCount
        machine.adopt(focusSeconds: restored.focus, daySitSeconds: restored.daySit)
        if restored.focus > 0 {
            flashStatus("续上 \(Int(restored.focus / 60)) 分钟", seconds: 4)
        }
    }

    /// 会议检测每次都要查 AVFoundation 和 CoreAudio，每秒都做纯属浪费。
    /// 只在四种时刻轮询：快到提醒了、有欠着的提醒等补发、卡片已经弹着、手停下来了。
    private func refreshMeetingState(idle: TimeInterval, away: Bool) {
        guard prefs.meetingAware else {
            meetingBusy = false
            return
        }
        let nearLimit = machine.focusSeconds >= thresholds.soft - 180
        let handStopped = !away && idle >= prefs.silentSeconds
        guard nearLimit || machine.deferredPending || panelVisible || handStopped else {
            meetingBusy = false
            return
        }
        guard Date().timeIntervalSince(lastMeetingCheck) >= 5 else { return }
        lastMeetingCheck = Date()
        meetingBusy = MeetingDetector.isBusy()
    }

    // MARK: - 弹窗

    private func showReminder(deferred: Bool = false, manual: Bool = false) {
        panelVisible = true
        model.visible = true
        // 手动预览不该占掉今天 8 次的名额
        if !manual { todayCount += 1 }

        let minutes = max(prefs.focusMinutes, Int(machine.focusSeconds / 60))
        model.minutes = minutes
        model.stage = .sitting
        model.urgency = .soft
        model.deferred = deferred

        let p = makePanelIfNeeded()
        p.level = .floating

        if hosting == nil {
            let view = MascotCard(
                model: model,
                animator: animator,
                onRest: { [weak self] in self?.didRest() },
                onSnooze: { [weak self] in self?.didSnooze() },
                onPoke: { [weak self] in self?.handlePoke() }
            )
            let h = NSHostingView(rootView: view)
            hosting = h
            // 内容一变就重绘。默认策略（.duringViewResize）只在视图尺寸变化时
            // 重画，内容「从有到无」的那部分会被漏掉 —— 在 isOpaque = false 的
            // 透明面板上，表现就是上一帧留在原地：用户报的「重影」里，
            // 那把没人坐的椅子就是这么来的。
            // 注意别改成 .crossfade，那是主动做交叉淡入，正好是重影的成因。
            h.layerContentsRedrawPolicy = .onSetNeedsDisplay
            p.contentView = h
            h.layoutSubtreeIfNeeded()
            var size = h.fittingSize
            if size.width < 100 || size.height < 100 {
                size = NSSize(width: 286 + MascotCard.shadowPad * 2,
                              height: 340 + MascotCard.shadowPad * 2)
            }
            p.setContentSize(size)
        }

        // 动作库按形象挑：猫头鹰是栖鸟，卖力那一拍用振翅代替打拳
        animator.startLoop(MascotRoutine.variants(for: prefs.mascotStyle))

        guard let screen = preferredScreen() else { return }
        activeScreen = screen
        let visible = screen.visibleFrame
        let size = p.frame.size
        let target = NSPoint(x: visible.maxX - size.width - panelMargin,
                             y: visible.minY + panelMargin)

        p.setFrameOrigin(target)
        // 自己摆的位置也要记账，否则这次定位会被 handlePanelMoved
        // 当成用户拖拽，白白污染 lastManualMoveAt
        autoMovedTo = target
        p.alphaValue = 0
        p.orderFrontRegardless()

        // 只做淡入。位移+透明度双动画在 borderless 面板上会停在中间态，留下固定偏移。
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        // 弹出来就开始计 12 秒，不区分静默。
        //
        // 这里以前写的是 `if !machine.inSilence { startEscalation() }`，本意是
        // 「人在思考时别用游走打扰」。实际效果是反的：坐到阈值时如果手已经停了
        // 5 分钟（读长文档、看视频、想事情——非常常见），弹窗那一刻 inSilence 就是
        // true，计时器压根不创建；而用户看到卡片后的第一反应往往是停下手盯着它，
        // 手一直不回来，兜底的补装也就永远等不到。用户报的现象就是「12 秒毫无反应」。
        //
        // 判断修正：静默只该拦**强提醒升级**（见 tick 里 upgradeToStrong 的条件），
        // 不该拦这个。游走是软提醒阶段的手段，需求原话就是「一直没点就让它动」，
        // 而且横向慢速移动本身很轻，不构成打扰。
        startEscalation()
        startGazeTracking()
        updateStatus()
    }

    private func upgradeToStrong() {
        model.urgency = .strong
        model.minutes = Int(machine.focusSeconds / 60)
        panel?.level = .screenSaver
        NSSound(named: NSSound.Name("Glass"))?.play()
        // 强提醒才黏人：改成贴着光标跑，比游走更有存在感
        startChasing()
    }

    /// 以鼠标所在屏幕为准。NSScreen.main 会随窗口焦点在双屏间漂移，不能作为定位依据。
    private func preferredScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func makePanelIfNeeded() -> ReminderPanel {
        if let existing = panel { return existing }

        let side = 286 + MascotCard.shadowPad * 2
        let p = ReminderPanel(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        // 允许按住卡片拖走。按钮和头像有自己的手势，优先级高于窗口拖动，不会误触。
        p.isMovableByWindowBackground = true
        p.animationBehavior = .none
        // 只盯这一个窗口。用 object: nil 会把设置窗口的拖动也算进来。
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePanelMoved),
            name: NSWindow.didMoveNotification, object: p
        )
        panel = p
        return p
    }

    private func hideReminder() {
        stopEscalation()
        stopWandering()
        stopChasing()
        stopGazeTracking()
        machine.clearDeferred()
        model.pokedLine = nil
        pokeTimes.removeAll()

        guard let p = panel, panelVisible else {
            animator.reset()
            model.visible = false
            return
        }
        panelVisible = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            p.alphaValue = 1
            p.level = .floating
            // 淡出跑完再停常驻动画。提前停会让 2.2% 的呼吸缩放瞬间归位，
            // 卡片在消失前先「缩一下」，肉眼就是闪了一下。
            guard let self, !self.panelVisible else { return }
            self.animator.reset()
            self.model.visible = false
        })

        updateStatus()
    }

    private func didRest() {
        // 和 tick() 里的判定保持同一口径：没坐够阈值就点按钮，不算打卡。
        // 否则「立即提醒我一次」这种测试入口也能刷天数。
        if machine.focusSeconds >= thresholds.soft {
            recordHabit()
        }
        machine.reset()
        hideReminder()
        persist()
    }

    private func didSnooze() {
        let limit = Double(prefs.focusMinutes * 60)
        let back = Double(prefs.snoozeMinutes * 60)
        machine.rewind(to: limit - back)
        hideReminder()
        persist()
    }

    // MARK: - 动作编排：哈欠 -> 伸懒腰 -> 打两拳 -> 歇一下，循环播放
    // 序列本身在 MascotRoutine.rest，这里只管什么时候开跑。

    private func startEscalation() {
        escalateTimer?.invalidate()
        let t = Timer(timeInterval: max(3, prefs.escalateSeconds),
                      target: self, selector: #selector(escalate), userInfo: nil, repeats: false)
        RunLoop.main.add(t, forMode: .common)
        escalateTimer = t
    }

    private func stopEscalation() {
        escalateTimer?.invalidate()
        escalateTimer = nil
    }

    @objc private func escalate() {
        // 一次性 Timer 触发后不会把引用置 nil。不手动清掉的话，tick 里所有
        // `escalateTimer == nil` 的判断会一直认为计时器还在跑。
        escalateTimer = nil
        guard panelVisible else { return }
        model.stage = .stretching
        model.minutes = Int(machine.focusSeconds / 60)

        // 动作循环从弹窗出现起就一直跑，升级只改视觉强度，不打断编排
        startWandering()
        updateStatus()
    }

    // MARK: - 游走（只横向移动，不上下晃）

    private func startWandering() {
        guard prefs.wanderEnabled, wanderTimer == nil, let p = panel else { return }
        wanderDirection = -1

        let screen = activeScreen ?? preferredScreen()
        wanderRect = screen?.visibleFrame ?? p.frame

        // 30fps × 2px = 60px/s，和原来 60fps × 1px 速度一样，
        // 但每秒少唤醒 30 次窗口合成。
        let t = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(wanderStep),
                      userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        wanderTimer = t
    }

    private func stopWandering() {
        wanderTimer?.invalidate()
        wanderTimer = nil
    }

    @objc private func wanderStep() {
        guard let p = panel, p.isVisible, wanderRect.width > 0 else { return }

        // 碰边反弹的规则在 Wander 里（纯函数，有测试），这里只负责取值和落地
        let minX = wanderRect.minX + panelMargin
        let maxX = wanderRect.maxX - p.frame.width - panelMargin
        guard let x = Wander.stepX(from: p.frame.origin.x,
                                   direction: &wanderDirection,
                                   minX: minX, maxX: maxX) else { return }
        let target = NSPoint(x: x, y: wanderRect.minY + panelMargin)
        autoMovedTo = target
        p.setFrameOrigin(target)
    }

    // MARK: - 鼠标互动
    //
    // 性格分级：软提醒阶段克制（被戳抖一下就好，不做多余动作）；
    // 一直不理它升到强提醒，才开始追着光标跑 —— 「越来越烦」本身就是提醒强度的表达。

    private func handlePoke() {
        let now = Date()
        pokeTimes = pokeTimes.filter { now.timeIntervalSince($0) < 3.5 }
        pokeTimes.append(now)

        if pokeTimes.count >= 3 {
            pokeTimes.removeAll()
            dodge()
            return
        }

        // 反应只用已有姿态拼：挠头 -> 眨眼 -> 回坐，等于「干嘛」
        animator.react([(.scratch, 0.40), (.sit, 0.10), (.blink, 0.12), (.sit, 0.20)])
        model.pokedLine = PokeLines.random()

        let line = model.pokedLine
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            // 只清掉自己写的那句，别把后面别人写的覆盖了
            if self?.model.pokedLine == line { self?.model.pokedLine = nil }
        }
    }

    /// 连戳三次：往反方向躲一段，同时摆出防御姿态
    private func dodge() {
        guard let p = panel, p.isVisible else { return }
        stopWandering()
        stopChasing()

        let rect = (p.screen ?? activeScreen)?.visibleFrame ?? p.frame
        let dir: CGFloat = p.frame.midX > rect.midX ? -1 : 1
        var x = p.frame.origin.x + dir * 78
        x = min(max(x, rect.minX + panelMargin), rect.maxX - p.frame.width - panelMargin)

        // 插值动画期间坐标一路在变，比不到终点，只能整段时间免检
        autoMoveUntil = Date().addingTimeInterval(0.5)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.40
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrameOrigin(NSPoint(x: x, y: rect.minY + panelMargin))
        }

        // 躲避也算一次「手动干预」：让 tick 的自愈等一会儿再来接手，
        // 别把「躲开你」这个动作直接跳过。恢复本身交给 tick 统一负责，
        // 这里不再单独排一个定时器 —— 恢复点越少越不容易漏。
        lastManualMoveAt = Date()
        animator.react([(.punch1, 0.16), (.stand, 0.10), (.punch2, 0.16), (.sit, 0.34)])
        model.pokedLine = "躲开你"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.model.pokedLine == "躲开你" { self?.model.pokedLine = nil }
        }
    }

    /// 强提醒阶段：贴着光标走，挡在你正在点的位置旁边。
    /// 比左右来回游走更有存在感，而且不会真的盖住你点东西的地方。
    private func startChasing() {
        guard prefs.wanderEnabled, chaseTimer == nil, panel != nil else { return }
        stopWandering()
        let t = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(chaseStep),
                      userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        chaseTimer = t
    }

    private func stopChasing() {
        chaseTimer?.invalidate()
        chaseTimer = nil
    }

    @objc private func chaseStep() {
        guard let p = panel, p.isVisible,
              Date().timeIntervalSince(lastManualMoveAt) > 0.8 else { return }

        let rect = (p.screen ?? activeScreen)?.visibleFrame ?? p.frame
        let mouse = NSEvent.mouseLocation
        // 光标跑到别的屏幕去了就不追，免得两个屏来回跳
        guard NSMouseInRect(mouse, rect, false) else { return }

        let minX = rect.minX + panelMargin
        let maxX = rect.maxX - p.frame.width - panelMargin
        guard maxX > minX else { return }

        // 停在光标旁边而不是正中，留出一点「不挡手」的距离
        let target = min(max(mouse.x - p.frame.width * 0.5, minX), maxX)
        let dx = target - p.frame.origin.x
        guard abs(dx) > 14 else { return }

        // 比例追随：越远走得越快，接近时自然减速，不会一顿一顿
        let step = max(-7.0, min(7.0, dx * 0.16))
        let next = NSPoint(x: p.frame.origin.x + step, y: rect.minY + panelMargin)
        autoMovedTo = next
        p.setFrameOrigin(next)
    }

    // MARK: - 视线跟随

    private func startGazeTracking() {
        guard gazeTimer == nil, panel != nil else { return }
        let t = Timer(timeInterval: 1.0 / 15.0, target: self, selector: #selector(gazeStep),
                      userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        gazeTimer = t
    }

    private func stopGazeTracking() {
        gazeTimer?.invalidate()
        gazeTimer = nil
        if model.gaze != .center { model.gaze = .center }
    }

    @objc private func gazeStep() {
        guard let p = panel, p.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - p.frame.midX
        let dy = mouse.y - p.frame.midY

        // 水平优先。弹窗贴在屏幕下缘，鼠标几乎总在它上方，
        // 若按夹角判定会一直「往上看」，左右跟随就废了。
        let next: GazeDirection
        if abs(dx) > 60 {
            next = dx < 0 ? .left : .right
        } else if dy > 40 {
            next = .up
        } else if dy < -40 {
            next = .down
        } else {
            next = .center
        }
        if model.gaze != next { model.gaze = next }
    }

    /// 用户拖动面板时，自动行为要让路，否则会一边拖一边被拉走。
    ///
    /// 难点在于 AppKit 不告诉我们是谁移动的：游走每帧 `setFrameOrigin`
    /// 也会走到这里（30fps，有测试 Tools/MoveNotifyTest）。原来这里用
    /// `NSEvent.pressedMouseButtons` 猜「是不是在拖」，方向是错的 ——
    /// 「按着鼠标」不等于「在拖窗口」。用户戳一下卡片、或者点完某处手还没
    /// 抬起来，游走的第一帧就会被当成拖拽，`stopWandering()` 直接把游走
    /// 停掉；而软提醒阶段没有任何恢复路径，卡片就此定在原地再也不动。
    /// 用户报的「12 秒后卡片没游走」就是这个。
    ///
    /// 现在改用坐标比对：位置正是上一帧我们自己设的那个点，就是自动移动。
    @objc private func handlePanelMoved() {
        guard let p = panel, p.isVisible else { return }
        guard Date() >= autoMoveUntil else { return }
        guard !Wander.isAutoMove(actual: p.frame.origin, expected: autoMovedTo) else { return }

        // 到这里才真的是用户在拖
        lastManualMoveAt = Date()
        stopWandering()
        stopChasing()

        // 松手 1 秒后恢复自动行为。强提醒的「追光标」只有这里能恢复，
        // tick 的自愈只管软提醒阶段的游走，所以这段不能省。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.panelVisible else { return }
            guard Date().timeIntervalSince(self.lastManualMoveAt) >= 0.9 else { return }
            if self.model.urgency == .strong {
                self.startChasing()
            } else if self.model.stage == .stretching {
                // 软提醒阶段被拖走也要接着游走，否则碰一下卡片就永久定住。
                // 但只有**已经升级过**（12 秒无响应、进入伸懒腰）才恢复 ——
                // 刚弹出来的头 12 秒本来就不该动，拖它一下也不该提前开跑。
                // 这一步等于提前替 tick 的自愈干了，省掉最多 1 秒的静止感。
                self.startWandering()
            }
        }
    }

    // MARK: - 菜单

    private func updateStatus() {
        let minutes = Int(machine.focusSeconds / 60)

        let normalTitle: String
        if isPaused() {
            normalTitle = " 暂停"
        } else if prefs.inQuietHours() {
            normalTitle = " 免打扰"
        } else if todayCount >= prefs.dailyCap {
            normalTitle = " \(minutes)m 已满"
        } else {
            normalTitle = " \(minutes)m"
        }
        let title = Date() < statusFlashUntil ? (statusFlash ?? normalTitle) : normalTitle
        // 每秒无脑赋值会让状态栏重排重绘，只在文案真的变了才写
        if title != lastStatusTitle {
            statusItem.button?.title = title
            lastStatusTitle = title
        }

        // 数字还在涨的时候，必须说清楚为什么——不然用户只会以为计时坏了。
        let awayNote: String
        if machine.inLongSilence {
            awayNote = " · 手停 \(Int(lastIdle / 60)) 分钟，先不弹"
        } else if machine.inSilence {
            awayNote = " · 静默中（提醒不升级）"
        } else if meetingBusy {
            awayNote = " · 会议中照常计时"
        } else {
            awayNote = ""
        }
        focusMenuItem?.title = "已连续专注 \(minutes) 分钟\(awayNote)（软 \(prefs.focusMinutes) / 强 \(prefs.strongMinutes)）"
        // 今日累计不受归零影响，是「今天一共坐了多久」——比单看这一轮更真实
        countMenuItem?.title = "今日坐 \(durationText(machine.daySitSeconds))"
            + " · 已提醒 \(todayCount) / \(prefs.dailyCap) 次"

        let habits = Habits.shared
        streakMenuItem?.title = habits.progressLine()
            + (habits.doneToday ? " · 今日已打卡" : " · 今天还没打卡")

        pauseMenuItem?.title = isPaused() ? "恢复计时" : "暂停 1 小时"
        unlockAllMenuItem?.state = prefs.debugUnlockAll ? .on : .off
    }

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds / 60)
        guard total >= 60 else { return "\(total) 分钟" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
    }

    private func isPaused() -> Bool {
        guard let until = pauseUntil else { return false }
        if until > Date() { return true }
        pauseUntil = nil
        return false
    }

    private func resetDayIfNeeded() {
        if !Calendar.current.isDate(countDay, inSameDayAs: Date()) {
            countDay = Date()
            todayCount = 0
            // 跨零点只清「今日累计」，这一轮的专注时长不该断——凌晨加班也是加班
            machine.rolloverDay()
            // 跨零点时把「今天是否已打卡」一起对齐，否则昨天的打卡状态会留在今天
            Habits.shared.refreshForNewDay()
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        focusMenuItem = NSMenuItem(title: "已连续专注 0 分钟", action: nil, keyEquivalent: "")
        focusMenuItem.isEnabled = false
        menu.addItem(focusMenuItem)

        countMenuItem = NSMenuItem(title: "今日已提醒 0 次", action: nil, keyEquivalent: "")
        countMenuItem.isEnabled = false
        menu.addItem(countMenuItem)

        streakMenuItem = NSMenuItem(title: Habits.shared.progressLine(), action: nil, keyEquivalent: "")
        streakMenuItem.isEnabled = false
        menu.addItem(streakMenuItem)

        menu.addItem(.separator())

        let testItem = NSMenuItem(title: "立即提醒我一次", action: #selector(testReminder), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        let strongItem = NSMenuItem(title: "预览强提醒", action: #selector(testStrong), keyEquivalent: "s")
        strongItem.target = self
        menu.addItem(strongItem)

        let resetItem = NSMenuItem(title: "重置计时", action: #selector(resetTimer), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        pauseMenuItem = NSMenuItem(title: "暂停 1 小时", action: #selector(togglePause), keyEquivalent: "p")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let onboardingItem = NSMenuItem(title: "重新看一遍引导",
                                        action: #selector(openOnboarding), keyEquivalent: "")
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        unlockAllMenuItem = NSMenuItem(title: "解锁全部形象（调试）",
                                       action: #selector(toggleUnlockAll), keyEquivalent: "")
        unlockAllMenuItem.target = self
        menu.addItem(unlockAllMenuItem)

        let fakeDayItem = NSMenuItem(title: "模拟打卡 +1 天（调试）",
                                     action: #selector(fakeHabitDay), keyEquivalent: "")
        fakeDayItem.target = self
        menu.addItem(fakeDayItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出歇会儿", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateStatus()
    }

    // MARK: - 动作

    @objc private func testReminder() {
        showReminder(manual: true)
    }

    @objc private func testStrong() {
        showReminder(manual: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.upgradeToStrong()
        }
    }

    @objc private func resetTimer() {
        machine.reset()
        hideReminder()
        persist()
        updateStatus()
    }

    @objc private func togglePause() {
        pauseUntil = isPaused() ? nil : Date().addingTimeInterval(3600)
        updateStatus()
    }

    @objc private func toggleUnlockAll() {
        prefs.debugUnlockAll.toggle()
        updateStatus()
    }

    /// 调试：把「最后打卡日」改成昨天，让下一次打卡必然 +1 天，
    /// 不用真的等一整天就能验收打卡播报和解锁换装。
    @objc private func fakeHabitDay() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        UserDefaults.standard.set(f.string(from: yesterday), forKey: "habit.lastDoneDay")
        recordHabit()
        updateStatus()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingView(rootView: SettingsView())
            host.layoutSubtreeIfNeeded()
            let cap = (NSScreen.main?.visibleFrame.height ?? 900) - 80
            let size = NSSize(width: 470, height: min(960, cap))

            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "歇会儿 · 设置"
            // Form 自带滚动，内容超出窗口时能正常往下翻
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// 首次启动的三屏引导，也能从菜单重看一遍
    @objc private func openOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView { [weak self] in
                self?.onboardingWindow?.close()
            }
            let host = NSHostingView(rootView: view)
            host.layoutSubtreeIfNeeded()

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "欢迎使用歇会儿"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(red: 0.988, green: 0.957, blue: 0.910, alpha: 1)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate {

    /// 关窗即丢引用，下次打开重建——避免设置页停在旧状态、引导停在最后一屏
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow { settingsWindow = nil }
        if window === onboardingWindow { onboardingWindow = nil }
    }
}
