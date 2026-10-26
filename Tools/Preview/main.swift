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

let style = args.count > 1 ? args[1] : "c"
let poseName = args.count > 2 ? args[2] : "sit"
let urgency: ReminderUrgency = (args.count > 3 && args[3] == "strong") ? .strong : .soft

Prefs.shared.mascotStyle = style
let model = ReminderModel()
model.minutes = 60
model.urgency = urgency
model.stage = (poseName == "up") ? .stretching : .sitting

let animator = MascotAnimator()
animator.hold(MascotPose(rawValue: poseName) ?? .sit)

let card = MascotCard(model: model, animator: animator, onRest: {}, onSnooze: {}, onPoke: {})
render(card, size: NSSize(width: 342, height: 360),
       to: "/tmp/card_\(style)_\(poseName)_\(urgency == .strong ? "strong" : "soft").png")
