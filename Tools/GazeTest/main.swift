import AppKit
import SwiftUI

/// 验证视线跟随的接线：
///   ① 同一坐姿下切换 gaze，画面必须真的变（否则等于没接）
///   ② 非坐姿（伸懒腰/站立）时必须忽略 gaze，否则会跳回坐姿穿帮
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

let prefs = Prefs.shared
prefs.mascotStyle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "a"

let model = ReminderModel()
model.minutes = 60
model.visible = true
let animator = MascotAnimator()
let card = MascotCard(model: model, animator: animator, onRest: {}, onSnooze: {}, onPoke: {})
let host = NSHostingView(rootView: card)
let panel = ReminderPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
panel.contentView = host
panel.orderFrontRegardless()
NSApp.deactivate()

func grab(_ name: String) {
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?
        .write(to: URL(fileURLWithPath: "/tmp/gaze_\(name).png"))
}

var steps: [(String, () -> Void)] = []
for (label, gaze) in [("center", GazeDirection.center), ("left", .left), ("right", .right),
                      ("up", .up), ("down", .down)] {
    steps.append((label, { model.gaze = gaze }))
}
// 非坐姿：伸懒腰时应忽略视线
steps.append(("standing_left", { animator.hold(.up); model.gaze = .left }))
steps.append(("standing_right", { model.gaze = .right }))

func run(_ i: Int) {
    guard i < steps.count else {
        print("wrote \(steps.count) shots")
        exit(0)
    }
    let (label, action) = steps[i]
    action()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        grab(label)
        run(i + 1)
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { run(0) }
NSApp.run()
