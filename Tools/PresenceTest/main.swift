import Foundation

// 判定机的时间轴用例。没有 XCTest（本机只有 Command Line Tools），
// 所以就是一个可执行文件：全过退出码 0，有失败退出码 1，CI 和本地都能跑。
//
// 跑法：./Tools/run_tests.sh

var checks = 0
var failures: [String] = []

func check(_ ok: Bool, _ what: String) {
    checks += 1
    if !ok { failures.append(what) }
}

func near(_ a: Double, _ b: Double, _ tol: Double = 0.01) -> Bool {
    abs(a - b) <= tol
}

/// 默认阈值：软 60 分 / 强 90 分 / 静默 5 分 / 长静默 30 分
let T = PresenceThresholds(focusMinutes: 60, strongMinutes: 90,
                           silentMinutes: 5, longSilentMinutes: 30)

/// 一次正常的心跳
func beat(_ now: Double, idle: Double = 0.4, away: Bool = false,
          meeting: Bool = false, delta: Double = 1,
          panel: Bool = false, canRemind: Bool = true) -> PresenceInput {
    PresenceInput(idle: idle, away: away, inMeeting: meeting,
                  delta: delta, panelVisible: panel, canRemind: canRemind)
}

// MARK: - 1. 连续工作 60 分钟：到点弹一次

do {
    var m = PresenceMachine()
    var now = 0.0
    var shows = 0
    for _ in 1...3600 {
        now += 1
        if m.step(now: now, input: beat(now), thresholds: T).shouldShowReminder { shows += 1 }
    }
    check(near(m.focusSeconds, 3600), "连续 60 分钟应累计 3600 秒，实际 \(m.focusSeconds)")
    check(shows == 1, "到点只该弹一次，实际 \(shows) 次")
    check(!m.inSilence, "每秒都有输入不该进静默")
}

// MARK: - 2. 锁屏 5 秒：不该抹掉累计

do {
    var m = PresenceMachine()
    var now = 0.0
    for _ in 1...600 { now += 1; _ = m.step(now: now, input: beat(now), thresholds: T) }
    var settled = false
    for _ in 1...5 {
        now += 1
        let e = m.step(now: now, input: beat(now, away: true), thresholds: T)
        if e.settledAway { settled = true }
    }
    for _ in 1...10 { now += 1; _ = m.step(now: now, input: beat(now), thresholds: T) }
    check(!settled, "锁屏 5 秒不该结算")
    check(near(m.focusSeconds, 610), "锁屏 5 秒后应继续累计到 610 秒，实际 \(m.focusSeconds)")
}

// MARK: - 3. 锁屏 40 秒：清零并记一次打卡，回来重新从头算

do {
    var m = PresenceMachine()
    var now = 0.0
    for _ in 1...3700 { now += 1; _ = m.step(now: now, input: beat(now), thresholds: T) }
    var settledCount = 0
    var habit = false
    for _ in 1...40 {
        now += 1
        let e = m.step(now: now, input: beat(now, away: true), thresholds: T)
        if e.settledAway { settledCount += 1; habit = habit || e.shouldRecordHabit }
    }
    check(settledCount == 1, "一轮离开只该结算一次，实际 \(settledCount) 次")
    check(habit, "坐够 3700 秒后离开，应记一次打卡")
    check(near(m.focusSeconds, 0), "离开后专注时长应清零，实际 \(m.focusSeconds)")
    check(m.daySitSeconds >= 3700, "今日累计不该被清零，实际 \(m.daySitSeconds)")

    // 回来之后从头算，满 60 分钟再弹
    var shows = 0
    for _ in 1...3600 {
        now += 1
        if m.step(now: now, input: beat(now), thresholds: T).shouldShowReminder { shows += 1 }
    }
    check(shows == 1, "回来重新坐满 60 分钟应再弹一次，实际 \(shows) 次")
}

// MARK: - 4. 看视频 50 分钟：累计一秒不少，但不打断；看完手一动就补上

do {
    var m = PresenceMachine()
    var now = 0.0
    var shows = 0
    for i in 1...3000 {
        now += 1
        let e = m.step(now: now, input: beat(now, idle: Double(i)), thresholds: T)
        if e.shouldShowReminder { shows += 1 }
    }
    check(near(m.focusSeconds, 3000), "看视频 50 分钟应累计 3000 秒，实际 \(m.focusSeconds)")
    check(shows == 0, "未到阈值不该弹")
    check(m.inSilence, "5 分钟没输入应进静默")
    check(m.inLongSilence, "30 分钟没输入应进长静默")

    for i in 3001...3600 {
        now += 1
        if m.step(now: now, input: beat(now, idle: Double(i)), thresholds: T).shouldShowReminder {
            shows += 1
        }
    }
    check(shows == 0, "长静默期间不该弹窗，实际 \(shows) 次")
    check(m.deferredPending, "长静默到点应记一条待补发")

    now += 1
    let e = m.step(now: now, input: beat(now, idle: 0.2), thresholds: T)
    check(e.shouldShowReminder, "手一回来应立刻补发")
    check(e.reminderIsDeferred, "补发的这条应带上「刚才在忙」标记")
    check(!e.inLongSilence && !e.inSilence, "手回来后静默应解除")
}

// MARK: - 5. 开会 60 分钟：记账不停，会后补发

do {
    var m = PresenceMachine()
    var now = 0.0
    var shows = 0
    for _ in 1...3600 {
        now += 1
        let e = m.step(now: now, input: beat(now, meeting: true), thresholds: T)
        if e.shouldShowReminder { shows += 1 }
    }
    check(shows == 0, "开会期间不该弹，实际 \(shows) 次")
    check(near(m.focusSeconds, 3600), "开会期间记账不该停，实际 \(m.focusSeconds)")
    check(m.deferredPending, "开会到点应记一条待补发")

    now += 1
    let e = m.step(now: now, input: beat(now), thresholds: T)
    check(e.shouldShowReminder && e.reminderIsDeferred, "会后应补发")
}

// MARK: - 6. 合盖 8 小时：清零、记打卡，且不把 8 小时算进今天

do {
    var m = PresenceMachine()
    var now = 0.0
    for _ in 1...3700 { now += 1; _ = m.step(now: now, input: beat(now), thresholds: T) }
    let sitBefore = m.daySitSeconds

    m.noteAwayOnset(now: now)          // 合盖那一刻由通知记下
    now += 28800                        // 八小时后唤醒，才等到第一次 tick
    let e = m.step(now: now, input: beat(now, idle: 28800, delta: 28800), thresholds: T)

    check(e.settledAway, "合盖 8 小时应结算")
    check(e.shouldRecordHabit, "结算时应记一次打卡")
    check(near(m.focusSeconds, PresenceMachine.deltaCap),
          "唤醒后只该认最后 3 秒，实际 \(m.focusSeconds)")
    check(near(m.daySitSeconds, sitBefore + PresenceMachine.deltaCap),
          "今日累计不该被 8 小时撑爆，实际 \(m.daySitSeconds)")
}

// MARK: - 7. 不认识的间隔不补

do {
    var m = PresenceMachine()
    var now = 0.0
    for _ in 1...10 { now += 1; _ = m.step(now: now, input: beat(now), thresholds: T) }
    now += 600
    _ = m.step(now: now, input: beat(now, delta: 600), thresholds: T)
    check(near(m.focusSeconds, 13), "600 秒的空档最多只认 3 秒，实际 \(m.focusSeconds)")
}

// MARK: - 8. 屏幕永不休眠、三小时没碰键鼠：累计照涨，只是先不弹

do {
    var m = PresenceMachine()
    var now = 0.0
    var shows = 0
    for i in 1...10800 {
        now += 1
        if m.step(now: now, input: beat(now, idle: Double(i)), thresholds: T).shouldShowReminder {
            shows += 1
        }
    }
    check(near(m.focusSeconds, 10800), "三小时应累计 10800 秒，实际 \(m.focusSeconds)")
    check(shows == 0, "长静默期间不该弹，实际 \(shows) 次")
    check(m.deferredPending, "手停三小时也要记着欠着一条")
}

// MARK: - 9. 手停 20 分钟（不到长静默）：到点照弹，只是不升级

do {
    var m = PresenceMachine()
    var now = 0.0
    var shows = 0
    var last = PresenceEvent()
    for i in 1...3600 {
        now += 1
        last = m.step(now: now, input: beat(now, idle: min(Double(i), 1200)), thresholds: T)
        if last.shouldShowReminder { shows += 1 }
    }
    check(shows == 1, "手停 20 分钟到点仍该弹，实际 \(shows) 次")
    check(!last.reminderIsDeferred, "这条不该带补发标记")
    check(m.inSilence && !m.inLongSilence, "应处于静默但不是长静默")
}

// MARK: - 10. 暂停 / 免打扰 / 今日已满：不弹，也不该攒成待补发

do {
    var m = PresenceMachine()
    var now = 0.0
    for _ in 1...3700 {
        now += 1
        _ = m.step(now: now, input: beat(now, canRemind: false), thresholds: T)
    }
    check(!m.deferredPending, "不允许提醒时不该攒待补发")
    check(near(m.focusSeconds, 3700), "不允许提醒时仍要记账")
}

// MARK: - 11. 落盘恢复：只续「新鲜」的专注时长

do {
    let now = Date()
    let today = SessionStore.dayKey(now)

    let fresh = SessionStore.Snapshot(focusSeconds: 1800, daySitSeconds: 5400, todayCount: 3,
                                      savedAt: now.addingTimeInterval(-120), dayKey: today)
    let r = SessionStore.restore(fresh, now: now)
    check(near(r.focus, 1800) && near(r.daySit, 5400) && r.todayCount == 3,
          "两分钟前的快照应完整续上")

    let stale = SessionStore.Snapshot(focusSeconds: 1800, daySitSeconds: 5400, todayCount: 3,
                                      savedAt: now.addingTimeInterval(-3600), dayKey: today)
    let s = SessionStore.restore(stale, now: now)
    check(near(s.focus, 0), "一小时前的快照不该续专注时长，实际 \(s.focus)")
    check(near(s.daySit, 5400), "今日累计照续，实际 \(s.daySit)")
    check(s.todayCount == 3, "今日次数照续，实际 \(s.todayCount)")

    let yesterday = SessionStore.Snapshot(focusSeconds: 1800, daySitSeconds: 5400, todayCount: 3,
                                          savedAt: now.addingTimeInterval(-86400),
                                          dayKey: SessionStore.dayKey(now.addingTimeInterval(-86400)))
    let y = SessionStore.restore(yesterday, now: now)
    check(y.focus == 0 && y.daySit == 0 && y.todayCount == 0, "隔天的快照一律不续")
}

// MARK: - 12. 落盘往返（真写一次磁盘）

do {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xiehuier_session_test.json")
    SessionStore.clear(at: tmp)
    check(SessionStore.load(from: tmp) == nil, "没有快照时应返回 nil")

    let snap = SessionStore.Snapshot(focusSeconds: 42, daySitSeconds: 99, todayCount: 1)
    check(SessionStore.save(snap, to: tmp), "写盘应成功")
    let back = SessionStore.load(from: tmp)
    check(back?.focusSeconds == 42 && back?.daySitSeconds == 99 && back?.todayCount == 1,
          "读回来的值应与写入一致")
    SessionStore.clear(at: tmp)
}

// MARK: - 13. 跨零点：当日累计归零，这一轮的专注时长不打断

do {
    var m = PresenceMachine()
    var now = 0.0
    for _ in 1...600 { now += 1; _ = m.step(now: now, input: beat(now), thresholds: T) }
    m.rolloverDay()
    check(near(m.daySitSeconds, 0), "跨零点当日累计应归零，实际 \(m.daySitSeconds)")
    check(near(m.focusSeconds, 600), "跨零点不该打断这一轮的专注时长，实际 \(m.focusSeconds)")
}

// MARK: - 14. 续上计时之后，到点仍然要弹

do {
    var m = PresenceMachine()
    m.adopt(focusSeconds: 1800, daySitSeconds: 5400)
    check(near(m.focusSeconds, 1800), "续上 1800 秒，实际 \(m.focusSeconds)")
    check(near(m.daySitSeconds, 5400), "续上今日累计 5400 秒，实际 \(m.daySitSeconds)")

    var now = 0.0
    var shows = 0
    for _ in 1...1800 {
        now += 1
        if m.step(now: now, input: beat(now), thresholds: T).shouldShowReminder { shows += 1 }
    }
    check(shows == 1, "续上 30 分钟后再坐 30 分钟必须弹（续上不能把提醒吞掉），实际 \(shows) 次")
}

// MARK: - 15. 续上的数已经超过阈值：下一步就该弹，而不是等下个 60 分钟

do {
    var m = PresenceMachine()
    m.adopt(focusSeconds: 3700, daySitSeconds: 3700)
    let e = m.step(now: 1, input: beat(1), thresholds: T)
    check(e.shouldShowReminder, "续上的数已经过阈值，启动后应立刻提醒一次")
    check(!e.reminderIsDeferred, "这条不该带补发标记")
}

// MARK: - 汇总

if failures.isEmpty {
    print("全部 \(checks) 项检查通过")
    exit(0)
} else {
    print("\(checks) 项检查里 \(failures.count) 项失败：")
    for f in failures { print("  ✗ \(f)") }
    exit(1)
}
