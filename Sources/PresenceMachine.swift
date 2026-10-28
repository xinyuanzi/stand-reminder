import Foundation

/// 一秒一次的心跳输入。全部由调用方从系统读好再传进来——
/// 机器自己不读时钟、不碰 AppKit，所以能在测试里把一整天压缩成几百行时间轴。
struct PresenceInput: Equatable {
    /// 距离上次键鼠输入过了多久（秒）
    var idle: Double
    /// 熄屏或锁屏——确凿离开
    var away: Bool
    /// 摄像头/麦克风被占用（调用方已按「会议感知」开关过滤过）
    var inMeeting: Bool
    /// 距离上一次 step 的真实间隔。App Nap 会把它拉长，睡眠唤醒会把它拉得极长。
    var delta: Double
    /// 提醒面板当前是否已经弹出来了
    var panelVisible: Bool
    /// 此刻允许弹窗吗（暂停 / 免打扰 / 今日已满，都由调用方算好）
    var canRemind: Bool
}

/// 阈值集合。单位全是秒。
struct PresenceThresholds: Equatable {
    /// 软提醒
    var soft: Double
    /// 强提醒
    var strong: Double
    /// 静默：手停这么久了，提醒照弹但不升级、不追鼠标
    var silent: Double
    /// 长静默：手停了半小时以上，本人可能根本不在。累计照涨，只是先不弹。
    var longSilent: Double
    /// 离开必须持续够久才算数，防止误触锁屏抹掉两小时
    var awayMin: Double
    /// 点了「我去走走了」之后的观察窗口。窗口内既没熄屏、键鼠/麦克风也一直在，
    /// 就判成「其实没走」，再弹一次。
    var restWindow: Double
    /// 观察窗口内，手停够这么久就算人真的走开了（回到原始需求里的「离开 1 分钟算休息」）
    var restQuiet: Double

    init(focusMinutes: Int, strongMinutes: Int, silentMinutes: Int,
         longSilentMinutes: Int, awayMin: Double = 30,
         restWindow: Double = 300, restQuiet: Double = 60) {
        soft = Double(focusMinutes * 60)
        strong = Double(max(strongMinutes, focusMinutes) * 60)
        silent = Double(silentMinutes * 60)
        // 和设置页同一口径：长静默必须明显大于静默，两个值被调反时以大的为准
        longSilent = max(Double(longSilentMinutes * 60), Double(silentMinutes * 60) + 60)
        self.awayMin = awayMin
        self.restWindow = restWindow
        self.restQuiet = restQuiet
    }
}

/// 一次 step 之后，调用方需要知道的事。全是事实，不含动作——
/// 弹窗、打卡、隐藏面板由 AppDelegate 按这些事实去执行。
struct PresenceEvent: Equatable {
    var focusSeconds: Double = 0
    var inSilence = false
    var inLongSilence = false
    /// 恰好在这一步完成了一次「确凿离开」结算
    var settledAway = false
    /// 结算那一刻已经坐够软提醒阈值 → 该记一次打卡
    var shouldRecordHabit = false
    /// 静默刚刚结束（手回来了），调用方可以把克制期间欠下的升级计时补上
    var silenceEnded = false
    var shouldShowReminder = false
    var reminderIsDeferred = false
    /// 点过「我去走走了」的那一轮，刚刚被确认为真休息（熄屏够久，或手停够久）
    var restConfirmed = false
    /// 点过「我去走走了」，但观察窗口到点时键鼠/麦克风还在 —— 判成没走，再提醒一次
    var restUnconfirmed = false
}

/// 「人还在不在座位上」的判定机。
///
/// 三条原则，写死在这里，不随设置变：
///   1. **只有确凿信号能删数据**。熄屏、锁屏 → 清零；手停多久都只影响提醒强度。
///   2. **不认识的间隔不补**。定时器被挂起 8 小时，那 8 小时既不加也不减。
///   3. **不确定时不打扰**。长静默（半小时没输入）照常记账，只是先不弹窗；
///      手一回来立刻补发——真走了的人回来正好需要被提醒。
struct PresenceMachine: Equatable {

    private(set) var focusSeconds: Double = 0
    /// 今日累计坐着时长，含前面几轮已经归零的部分
    private(set) var daySitSeconds: Double = 0
    private(set) var inSilence = false
    private(set) var inLongSilence = false
    private(set) var deferredPending = false
    /// 这一轮有没有已经弹过。防止调用方漏置 panelVisible 时每秒弹一个。
    private(set) var reminderFired = false

    /// 这一轮连续点了几次「再等 N 分钟」。
    ///
    /// 不设上限的话 snooze 是个后门：`rewind` 把累计往回拨 5 分钟，
    /// 到点再拨 5 分钟，可以一直拨到天亮 —— 强提醒（90 分钟）永远升不上来。
    /// 放在判定机里而不是 UI 里，是因为「这一轮」的边界由判定机定义：
    /// `reset` / `settle` / `rolloverDay` / `adopt` 全部会清它，
    /// 放在外面就有了「哪条路径忘了清」的可能。
    private(set) var snoozeStreak = 0

    /// 这一轮离开的起始时刻（引擎时间）。熄屏/睡眠通知会在事发瞬间写入。
    private(set) var awaySince: Double?
    /// 这一轮离开已经结算过，避免重复清零、重复打卡
    private(set) var awaySettled = false

    /// 点了「我去走走了」的时刻。非 nil = 正在观察这个人到底走没走。
    ///
    /// 为什么不能点了就直接清零：用户点了按钮，手还放在键盘上继续打字，
    /// 这种情况一点也不少见（想先把这句话打完、先把这个函数写完）。
    /// 直接清零等于给了一个「按一下就当休息过」的假按钮，打卡和累计同时被污染。
    private(set) var awaitingRestSince: Double?

    /// 定时器被 App Nap 或系统睡眠拉长时，单次最多认这么多。
    /// 真实 tick 是 1 秒，容忍 3 秒抖动；再长就不是「过去了一段时间」，
    /// 而是「我们没看见发生了什么」，不认识的间隔不补。
    static let deltaCap: Double = 3

    // MARK: - 外部事件

    /// 熄屏 / 系统睡眠的**瞬间**调用。
    /// 屏幕睡着时定时器会被压慢，等不到下一次 tick 就已经醒了，
    /// 「睡着」这个过程会整个消失——所以必须在事发那一刻把时间戳记下来。
    mutating func noteAwayOnset(now: Double) {
        if awaySince == nil { awaySince = now }
    }

    /// 启动时从磁盘续上。只认快照里的数，绝不把关闭期间的时间加回去。
    mutating func adopt(focusSeconds: Double, daySitSeconds: Double) {
        self.focusSeconds = max(0, focusSeconds)
        self.daySitSeconds = max(0, daySitSeconds)
        awaySince = nil
        awaySettled = false
        inSilence = false
        inLongSilence = false
        deferredPending = false
        // 刚启动时屏幕上没有任何卡片，「本轮已弹过」必须归零。
        // 否则续上 30 分钟之后，再坐满 60 分钟也不会弹——续上反而把提醒吞掉了。
        reminderFired = false
        // 连续推掉几次属于「这一轮」的状态，重启就是新的一轮
        snoozeStreak = 0
        // 观察窗口不跨重启：进程都没了，我们没法知道那五分钟里人在不在
        awaitingRestSince = nil
    }

    /// 新的一天：只清当日累计，专注时长属于「这一轮」，跨零点不该断
    mutating func rolloverDay() {
        daySitSeconds = 0
        // 但「推掉了几次」没有跨零点的道理——凌晨接着推，还是同一个人在推
        snoozeStreak = 0
    }

    /// 用户点「休息了」或菜单「重置计时」
    mutating func reset() {
        focusSeconds = 0
        inSilence = false
        inLongSilence = false
        deferredPending = false
        reminderFired = false
        awaySince = nil
        awaySettled = false
        snoozeStreak = 0
        awaitingRestSince = nil
    }

    /// 用户点「休息了」——先开观察窗口，不立刻清零。
    ///
    /// 没坐够阈值就点（比如菜单里「立即提醒我一次」弹出来的卡片），
    /// 没什么可确认为休息的，直接清零。
    ///
    /// 返回「是否开了窗口」。调用方据此决定是「先不打卡，等确认」还是「按老路走」。
    @discardableResult
    mutating func claimRest(now: Double, thresholds t: PresenceThresholds) -> Bool {
        guard focusSeconds >= t.soft else {
            reset()
            return false
        }
        // 已经在该窗口里了就别重置计时，否则连点两下能无限延长观察期
        if awaitingRestSince == nil { awaitingRestSince = now }
        return true
    }

    /// 稍后再说：退回到「阈值前 N 分钟」，到点会再弹一次
    mutating func rewind(to seconds: Double) {
        focusSeconds = max(0, seconds)
        deferredPending = false
        reminderFired = false
    }

    /// 记一次「再等一会儿」。放在 rewind 旁边而不是塞进 rewind，
    /// 是因为次数和回拨是两件事：菜单里也可能有别的入口需要回拨但不计数。
    mutating func noteSnooze() {
        snoozeStreak += 1
    }

    mutating func clearDeferred() {
        deferredPending = false
    }

    // MARK: - 心跳

    mutating func step(now: Double, input: PresenceInput,
                       thresholds t: PresenceThresholds) -> PresenceEvent {
        var event = PresenceEvent()

        settleAway(now: now, away: input.away, thresholds: t, event: &event)
        accumulate(input: input)

        // 结算后清掉的静默不算「刚刚结束」——面板已经被收走了，补升级计时没意义
        let wasSilent = inSilence
        inSilence = !input.away && !input.inMeeting && input.idle >= t.silent
        inLongSilence = !input.away && input.idle >= t.longSilent
        event.silenceEnded = wasSilent && !inSilence

        resolveAwaitingRest(now: now, input: input, thresholds: t, event: &event)

        if !input.panelVisible, !reminderFired, input.canRemind,
           focusSeconds >= t.soft {
            // 确凿离开、正在开会、手停了半小时以上：先不打断，但要记着欠了一条
            if input.away || input.inMeeting || inLongSilence {
                deferredPending = true
            } else {
                event.shouldShowReminder = true
                event.reminderIsDeferred = deferredPending
                deferredPending = false
                reminderFired = true
            }
        }

        event.focusSeconds = focusSeconds
        event.inSilence = inSilence
        event.inLongSilence = inLongSilence
        return event
    }

    // MARK: - 内部

    /// 收「点了我去走走了」的那笔账。
    ///
    /// 三条出路，按优先级：
    ///   1. **熄屏/锁屏够久** —— `settleAway` 已经结算过了（清零 + 算好打卡），这里只收窗口
    ///   2. **手停了够久**（默认 60 秒）—— 人确实走开了，清零并算一次打卡
    ///   3. **窗口到点，键鼠/麦克风还在** —— 判成「其实没走」：**累计一秒不减**，
    ///      立刻再提醒一次
    ///
    /// 第 3 条是这个函数存在的全部理由。不做的话，「我去走走了」就变成一个
    /// 按一下就当休息过的假按钮：手没离开键盘，打卡照记、计时照清。
    private mutating func resolveAwaitingRest(now: Double, input: PresenceInput,
                                              thresholds t: PresenceThresholds,
                                              event: inout PresenceEvent) {
        // 1. 确凿离开。settleAway 已在本步开头清零并算好了打卡，
        //    这里只把「这次确凿离开正好收尾了一个观察窗口」这件事说出去。
        if event.settledAway, awaitingRestSince != nil {
            awaitingRestSince = nil
            event.restConfirmed = true
            return
        }

        guard let since = awaitingRestSince else { return }

        // 2. 手停了够久。注意这是「已被用户告知要走」的前提下的沉默，
        //    和 D-19「手停不算离开」不冲突：那条约束的是「没被告知」的情况。
        if !input.inMeeting, input.idle >= t.restQuiet {
            awaitingRestSince = nil
            event.restConfirmed = true
            event.shouldRecordHabit = settle(t) || event.shouldRecordHabit
            return
        }

        // 3. 窗口到点还在用（或者还在开会）→ 没走
        guard now - since >= t.restWindow else { return }
        awaitingRestSince = nil

        // 和正常路径同一套分支：开会 / 长静默 / 暂停 / 免打扰 / 今日已满都不弹，
        // 但累计一秒不减。区别只是这条路径要把「没走」这个事实带出去，
        // 让卡片换一句解释，否则用户会以为「我明明点了休息，怎么五分钟后又来」。
        if input.canRemind, !input.away, !input.inMeeting, !inLongSilence {
            event.shouldShowReminder = true
            event.reminderIsDeferred = false
            event.restUnconfirmed = true
            reminderFired = true
        } else {
            // 交给正常路径在允许的时候补弹；那一路的文案是「会议结束了，先把欠的休息补上」，
            // 这里不覆盖——总比在会议中途弹窗强
            if input.canRemind { deferredPending = true }
            reminderFired = false
        }
    }

    private mutating func settleAway(now: Double, away: Bool,
                                     thresholds t: PresenceThresholds,
                                     event: inout PresenceEvent) {
        if away {
            if awaySince == nil { awaySince = now }
            guard !awaySettled, let since = awaySince,
                  now - since >= t.awayMin else { return }
            awaySettled = true
            event.settledAway = true
            event.shouldRecordHabit = settle(t)
        } else {
            // 唤醒通知常常比「睡够 30 秒」到得晚，这里补一次结算
            if let since = awaySince, !awaySettled, now - since >= t.awayMin {
                awaySettled = true
                event.settledAway = true
                event.shouldRecordHabit = settle(t)
            }
            awaySince = nil
            awaySettled = false
        }
    }

    /// 确凿离开的结算：清零。返回「够不够算一次真休息」。
    /// 只有坐够了软提醒阈值才离开，才算打卡——
    /// 随手离开一分钟也能刷天数的话，解锁就失去意义了。
    private mutating func settle(_ t: PresenceThresholds) -> Bool {
        inSilence = false
        inLongSilence = false
        deferredPending = false
        reminderFired = false
        // 确凿离开过一轮，推掉几次的历史不该带到下一轮
        snoozeStreak = 0
        // 注意这里**不**清 awaitingRestSince：确凿离开可能正好是「点了我去走走了」
        // 那次的收尾，要留给 resolveAwaitingRest 去认领并发出 restConfirmed。
        // 别的地方（reset / adopt）清得早没关系，它们本来就不涉及这次确认。
        guard focusSeconds > 0 else { return false }
        let counted = focusSeconds >= t.soft
        focusSeconds = 0
        return counted
    }

    private mutating func accumulate(input: PresenceInput) {
        // 熄屏就是不在座位上，这段时间一秒都不算
        guard !input.away else { return }
        let d = min(max(input.delta, 0), Self.deltaCap)
        focusSeconds += d
        daySitSeconds += d
    }
}
