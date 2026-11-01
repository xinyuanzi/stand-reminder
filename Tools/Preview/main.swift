import AppKit
import SwiftUI

_ = NSApplication.shared

func render<V: View>(_ view: V, size: NSSize, to path: String) {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()
    let fit = hosting.fittingSize
    print("fittingSize:", fit)
    hosting.frame = NSRect(origin: .zero, size: fit)
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        fatalError("no rep")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("no png")
    }
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote", path)
}

let args = CommandLine.arguments

if args.count > 1 && args[1] == "settings" {
    if args.contains("quiet") { Prefs.shared.quietEnabled = true }
    render(SettingsView(), size: NSSize(width: 470, height: 960), to: "/tmp/settings.png")
    exit(0)
}

if args.count > 1 && args[1] == "week" {
    // 本周回顾：造一周假数据，其中周三刻意留空（模拟那天没开机）
    let cal = Calendar.current
    let today = Date()
    let monday = History.startOfWeek(today)
    let empty = args.contains("empty")
    let skip = args.count > 2 ? (Int(args[2]) ?? 2) : 2   // 第几天留空，-1 表示不留空
    var days: [DayRecord] = []
    if !empty {
        let hours: [Double] = [5.2, 6.8, 9.4, 3.1, 7.5, 2.2, 4.6]
        for i in 0..<7 {
            guard i != skip else { continue }
            let d = cal.date(byAdding: .day, value: i, to: monday)!
            days.append(DayRecord(dayKey: History.dayKey(d),
                                  sitSeconds: hours[i] * 3600,
                                  breaks: Int(hours[i]),
                                  reminders: Int(hours[i] / 2),
                                  longestStretch: hours[i] * 3600 / 1.8))
        }
    }
    let view = WeekView(summary: History.summary(days, containing: today),
                        weekStart: monday,
                        todayKey: History.dayKey(today),
                        lastWeekTotal: empty ? nil : 30 * 3600)
    render(view, size: NSSize(width: 460, height: 412), to: "/tmp/week.png")
    exit(0)
}

if args.count > 1 && args[1] == "onboarding" {
    let p = args.count > 2 ? (Int(args[2]) ?? 0) : 0
    render(OnboardingView(initialPage: p) {}, size: NSSize(width: 520, height: 620),
           to: "/tmp/onboarding_\(p).png")
    exit(0)
}

let style = args.count > 1 ? args[1] : "c"
let poseName = args.count > 2 ? args[2] : "sit"
let urgencyName = args.count > 3 ? args[3] : "soft"
let urgency: ReminderUrgency
switch urgencyName {
case "strong": urgency = .strong
case "ultimate": urgency = .ultimate
default: urgency = .soft
}

Prefs.shared.mascotStyle = style
let model = ReminderModel()
model.minutes = 60
model.urgency = urgency
model.stage = (poseName == "up") ? .stretching : .sitting
// 第四个参数是 snooze 次数：传 3 就能渲染「推满了」的样子，
// 用来确认那句替代文案在 286pt 卡片里放得下、不挤掉按钮区
if args.count > 4, let n = Int(args[4]) { model.snoozeStreak = n }
// 任意位置带 soon 就渲染「点了休息但其实没走」那张
if args.contains("soon") { model.returnedSoon = true }
// 文案轮换：CV=0/1/2 选一套，方便把三套都渲染出来对比有没有读不通的
let copyVariant = Int(ProcessInfo.processInfo.environment["CV"] ?? "") ?? 0
model.copyVariant = copyVariant
// DM=1 渲染「会开太久兜底」那一张
if ProcessInfo.processInfo.environment["DM"] != nil { model.duringMeeting = true }

let animator = MascotAnimator()
animator.hold(MascotPose(rawValue: poseName) ?? .sit)

let card = MascotCard(model: model, animator: animator, onRest: {}, onSnooze: {}, onPoke: {})
let suffix = model.canSnooze ? "" : "_nosnooze"
let tag = model.returnedSoon ? "_soon" : suffix
render(card, size: NSSize(width: 342, height: 360),
       to: "/tmp/card_\(style)_\(poseName)_\(urgencyName)\(tag)_cv\(copyVariant).png")
