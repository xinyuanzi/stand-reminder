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

let animator = MascotAnimator()
animator.hold(MascotPose(rawValue: poseName) ?? .sit)

let card = MascotCard(model: model, animator: animator, onRest: {}, onSnooze: {}, onPoke: {})
let suffix = model.canSnooze ? "" : "_nosnooze"
let tag = model.returnedSoon ? "_soon" : suffix
render(card, size: NSSize(width: 342, height: 360),
       to: "/tmp/card_\(style)_\(poseName)_\(urgencyName)\(tag).png")
