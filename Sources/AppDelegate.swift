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
    /// 用户手动拖动过程中的最后移动时间，用来在松手后恢复自动行为
    private var lastDraggedAt = Date.distantPast

    private var focusSeconds: Double = 0
    /// 静默中：手停了很久、又没有「在开会」的正向证据。照常计时，只是先不打断。
    private var inSilence = false

    /// 离开必须「持续」够久才算数。锁屏两秒、误触熄屏 → 不该抹掉两小时的累计。
    private static let awayMinSeconds: TimeInterval = 30
    /// 这一轮离开的起始时刻（熄屏/系统睡眠的瞬间由通知记下，不依赖 tick 会不会被压住）
    private var awaySince: Date?
    /// 这一轮离开已经清过零，避免重复打卡
    private var awayCleared = false

    private var panelVisible = false
    private var pauseUntil: Date?
    private var todayCount = 0
    private var countDay = Date()

    private var wanderDirection: CGFloat = 1
    private var wanderRect: NSRect = .zero
    /// 弹窗与游走共用的目标屏幕，避免中途切换导致跳屏
    private var activeScreen: NSScreen?

    private var meetingBusy = false
    private var deferredPending = false
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
        if awaySince == nil { awaySince = Date() }
    }

    /// tick 每秒一次 + 屏幕/系统唤醒通知都会走到这里。
    /// 只有离开**持续够久**才清零——短暂熄屏、误触锁屏不该抹掉累计。
    private func observePresence(away: Bool) {
        let now = Date()
        if away {
            if awaySince == nil { awaySince = now }
            guard !awayCleared, let since = awaySince,
                  now.timeIntervalSince(since) >= Self.awayMinSeconds else { return }
            awayCleared = true
            resetForAway()
        } else {
            // 唤醒通知往往比「睡够 30 秒」到得晚，这里补一次结算
            let elapsed = awaySince.map { now.timeIntervalSince($0) } ?? 0
            if !awayCleared, elapsed >= Self.awayMinSeconds {
                resetForAway()
            }
            awaySince = nil
            awayCleared = false
        }
    }

    /// 房间状态可能变了（唤醒、解锁）——重新问一次屏幕
    @objc private func presenceChanged() {
        observePresence(away: Presence.isAway)
    }

    /// 确凿离开：累计清零，够阈值则计一次休息。
    /// 只有「坐够了软提醒阈值之后才离开」才算一次真正的休息——
    /// 随手离开一分钟也能刷天数的话，解锁就失去意义了。
    private func resetForAway() {
        inSilence = false
        guard focusSeconds > 0 else { return }
        if focusSeconds >= Double(prefs.focusMinutes * 60) {
            recordHabit()
        }
        focusSeconds = 0
        hideReminder()
        updateStatus()
    }

    @objc private func tick() {
        resetDayIfNeeded()

        let idle = IdleClock.seconds
        // 熄屏 / 锁屏 = 确凿离开。比拿时长猜人可靠得多。
        let away = Presence.isAway
        refreshMeetingState(idle: idle, away: away)

        let softLimit = Double(prefs.focusMinutes * 60)
        let strongLimit = Double(max(prefs.strongMinutes, prefs.focusMinutes) * 60)
        let inMeeting = prefs.meetingAware && meetingBusy

        // 到点才清零：离开没够 awayMinSeconds 就回来了，什么都不动
        observePresence(away: away)

        // 屏幕亮着就一直记账。
        // 冻结是上一版的错误：手停三分钟跟旁边人说句话、读文档停下来想，
        // 人明明还在座位上，冻住等于把这段整段漏掉——而屏幕没熄这件事本身
        // 就是系统在说「人还在」（它按 10 分钟无输入才熄屏）。
        if !away {
            focusSeconds += 1
        }

        // 屏幕设成永不休眠时的兜底：拿不到熄屏信号，只能退回去用超长时长判
        if !away, idle >= prefs.awayResetSeconds {
            resetForAway()
        }

        // 静默 = 手停了很久，但**没有**任何「在开会」的正向证据。
        // 不拿它当「人走了」——那正是上一版冻结的错误。它只当作**克制**的理由：
        // 提醒照弹，但不升级、不追鼠标。看视频、线下开会时别被追着跑。
        inSilence = !away && !inMeeting && idle >= prefs.silentSeconds
        // 只有确凿证据（熄屏/锁屏、摄像头麦克风占用）才完全压住弹窗，其余照常提醒。
        let holdBack = away || inMeeting

        if !panelVisible, focusSeconds >= softLimit,
           !isPaused(), !prefs.inQuietHours(), todayCount < prefs.dailyCap {
            if holdBack {
                // 离开 / 开会：记账不停，只是不打断，恢复后补发
                deferredPending = true
            } else {
                let wasDeferred = deferredPending
                deferredPending = false
                showReminder(deferred: wasDeferred)
            }
        }

        // 静默结束（手回来了）补上克制期间欠下的升级计时
        if panelVisible, !inSilence, escalateTimer == nil,
           model.urgency == .soft, model.stage == .sitting {
            startEscalation()
        }

        if panelVisible, model.urgency == .soft, focusSeconds >= strongLimit, !inSilence {
            upgradeToStrong()
        }

        updateStatus()
    }

    /// 会议检测每次都要查 AVFoundation 和 CoreAudio，每秒都做纯属浪费。
    /// 只在三种时刻轮询：快到提醒了、有欠着的提醒等补发、手停下来了。
    /// 第三条是 v0.9.4 加的——「手停了是不是在开会」决定了冻结还是继续计时，
    /// 不查就分不出来。
    private func refreshMeetingState(idle: TimeInterval, away: Bool) {
        guard prefs.meetingAware else {
            meetingBusy = false
            return
        }
        let nearLimit = focusSeconds >= Double(prefs.focusMinutes * 60) - 180
        let handStopped = !away && idle >= prefs.silentSeconds
        guard nearLimit || deferredPending || panelVisible || handStopped else {
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

        let minutes = max(prefs.focusMinutes, Int(focusSeconds / 60))
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
        p.alphaValue = 0
        p.orderFrontRegardless()

        // 只做淡入。位移+透明度双动画在 borderless 面板上会停在中间态，留下固定偏移。
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        // 静默时不起升级计时：卡片安静待着，不追鼠标也不转暖色。
        // 手一回来再补上（见 tick 里的补装逻辑）。
        if !inSilence { startEscalation() }
        startGazeTracking()
        updateStatus()
    }

    private func upgradeToStrong() {
        model.urgency = .strong
        model.minutes = Int(focusSeconds / 60)
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
        deferredPending = false
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
        if focusSeconds >= Double(prefs.focusMinutes * 60) {
            recordHabit()
        }
        focusSeconds = 0
        deferredPending = false
        hideReminder()
    }

    private func didSnooze() {
        let limit = Double(prefs.focusMinutes * 60)
        let back = Double(prefs.snoozeMinutes * 60)
        focusSeconds = max(0, limit - back)
        deferredPending = false
        hideReminder()
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
        guard panelVisible else { return }
        model.stage = .stretching
        model.minutes = Int(focusSeconds / 60)

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

        let width = p.frame.width
        let minX = wanderRect.minX + panelMargin
        let maxX = wanderRect.maxX - width - panelMargin
        guard maxX > minX else { return }

        var x = p.frame.origin.x + wanderDirection * 2
        if x <= minX {
            x = minX
            wanderDirection = 1
        } else if x >= maxX {
            x = maxX
            wanderDirection = -1
        }
        p.setFrameOrigin(NSPoint(x: x, y: wanderRect.minY + panelMargin))
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

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.40
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrameOrigin(NSPoint(x: x, y: rect.minY + panelMargin))
        }

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
              Date().timeIntervalSince(lastDraggedAt) > 0.8 else { return }

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
        p.setFrameOrigin(NSPoint(x: p.frame.origin.x + step, y: rect.minY + panelMargin))
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

    /// 用户拖动面板时，自动行为要让路，否则会一边拖一边被拉走
    @objc private func handlePanelMoved() {
        guard let p = panel, p.isVisible else { return }
        let dragging = (NSEvent.pressedMouseButtons & 1) == 1
        guard dragging else { return }

        lastDraggedAt = Date()
        stopWandering()
        stopChasing()

        // 松手 1 秒后恢复强提醒的追光标（软提醒本来就不追）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            guard Date().timeIntervalSince(self.lastDraggedAt) >= 0.9 else { return }
            if self.panelVisible, self.model.urgency == .strong {
                self.startChasing()
            }
        }
    }

    // MARK: - 菜单

    private func updateStatus() {
        let minutes = Int(focusSeconds / 60)

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

        // 静默不是故障，是手停了但人还在座位上——明说出来，省得又以为计时坏了。
        // 会议中数字还在涨，同样要说清楚为什么。
        let awayNote = inSilence ? " · 静默中（提醒不升级）"
            : (meetingBusy ? " · 会议中照常计时" : "")
        focusMenuItem?.title = "已连续专注 \(minutes) 分钟\(awayNote)（软 \(prefs.focusMinutes) / 强 \(prefs.strongMinutes)）"
        countMenuItem?.title = "今日已提醒 \(todayCount) / \(prefs.dailyCap) 次"

        let habits = Habits.shared
        streakMenuItem?.title = habits.progressLine()
            + (habits.doneToday ? " · 今日已打卡" : " · 今天还没打卡")

        pauseMenuItem?.title = isPaused() ? "恢复计时" : "暂停 1 小时"
        unlockAllMenuItem?.state = prefs.debugUnlockAll ? .on : .off
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
        focusSeconds = 0
        hideReminder()
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
