import AppKit
import SwiftUI

/// 真窗口取图：验证「窗口未激活」时卡片的实际长相，以及动作循环是否真的在跑。
///
/// 为什么必须用真窗口：离屏 NSHostingView 永远按 active 渲染，
/// 会把 non-activating 面板的降级外观问题全部掩盖掉（按钮白底白字就是这么漏的）。
///
/// 用法：
///   winshot a soft          → 1.2s 后取一张 /tmp/win_a_soft.png
///   winshot a soft strip    → 每 0.3s 取一张，连续取 22 张 /tmp/strip_XX.png
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

let prefs = Prefs.shared
let args = CommandLine.arguments
let style = args.count > 1 ? args[1] : "a"
let urgency: ReminderUrgency = (args.count > 2 && args[2] == "strong") ? .strong : .soft
let strip = args.contains("strip")
prefs.mascotStyle = style

let model = ReminderModel()
model.minutes = 60
model.urgency = urgency
model.stage = .sitting

let animator = MascotAnimator()
let card = MascotCard(model: model, animator: animator, onRest: {}, onSnooze: {}, onPoke: {})
let host = NSHostingView(rootView: card)
let size = host.fittingSize

let panel = ReminderPanel(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false)
panel.contentView = host
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
panel.setFrameOrigin(NSPoint(x: 200, y: 200))
panel.orderFrontRegardless()

// 让 App 回到非激活态，模拟真实场景（提醒面板弹出时用户还在别的 App 里）
NSApp.deactivate()

func grab(_ path: String) -> Bool {
    guard let view = panel.contentView,
          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?
        .write(to: URL(fileURLWithPath: path))
    return true
}

var index = 0
var timer: Timer?

if strip {
    print("开始循环，每 0.08s 取一张，共 150 张")
    animator.startLoop(MascotRoutine.variants(for: style))
    let t = Timer(timeInterval: 0.08, repeats: true) { _ in
        let name = String(format: "/tmp/strip_%02d.png", index)
        _ = grab(name)
        index += 1
        if index >= 150 {
            timer?.invalidate()
            print("wrote 34 frames, appActive=\(NSApp.isActive) keyWindow=\(panel.isKeyWindow)")
            exit(0)
        }
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
} else {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        let name = "\(style)_\(urgency == .strong ? "strong" : "soft")"
        let path = "/tmp/win_\(name).png"
        _ = grab(path)
        print("wrote", path, "appActive=\(NSApp.isActive) keyWindow=\(panel.isKeyWindow)")
        exit(0)
    }
}

NSApp.run()
