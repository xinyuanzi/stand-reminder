import AppKit
import SwiftUI

/// 验证头像点击在「允许背景拖动」的面板上仍能触发。
///
/// 这是最容易被静默破坏的一处：面板开了 isMovableByWindowBackground 之后，
/// 落在非控件区域的 mouseDown 会被窗口拿去拖窗口，SwiftUI 手势收不到。
/// 所以这里查两件事：
///   ① 头像中心命中到的视图是否允许「按下即拖动窗口」（必须是 false）
///   ② 真投递一对 mouseDown/mouseUp 进去，看 onPoke 有没有被调用
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

let prefs = Prefs.shared
prefs.mascotStyle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "c"

let model = ReminderModel()
model.minutes = 60
var pokes = 0

let animator = MascotAnimator()
let card = MascotCard(
    model: model,
    animator: animator,
    onRest: {},
    onSnooze: {},
    onPoke: { pokes += 1 }
)
let host = NSHostingView(rootView: card)
let size = host.fittingSize
host.frame = NSRect(origin: .zero, size: size)
host.layoutSubtreeIfNeeded()

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
panel.isMovableByWindowBackground = true
panel.setFrameOrigin(NSPoint(x: 240, y: 240))
panel.orderFrontRegardless()
NSApp.deactivate()

// 头像在卡片顶部居中。窗口坐标系原点是左下角，所以要翻过来算。
let avatar = NSPoint(x: size.width / 2, y: size.height - (MascotCard.shadowPad + 2 + 63))

DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
    print("窗口尺寸 \(size)  头像点 \(avatar)")

    if let hit = host.hitTest(avatar) {
        print("命中视图 \(type(of: hit))  mouseDownCanMoveWindow=\(hit.mouseDownCanMoveWindow)")
    } else {
        print("命中视图 nil —— 头像区域没有可点内容")
    }

    for (kind, delay) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.06)] {
        guard let ev = NSEvent.mouseEvent(
            with: kind,
            location: avatar,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + delay,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: kind == .leftMouseDown ? 1 : 0
        ) else { continue }
        NSApp.postEvent(ev, atStart: false)
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
    print("onPoke 触发次数 = \(pokes)")
    print(pokes > 0 ? "PASS 头像点击能触发" : "FAIL 头像点击被吞")

    // 顺带取一张「被戳说话」的样子，确认这句台词在标题一行里放得下
    model.pokedLine = "戳了也不管用"
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "/tmp/poke_card.png"))
            print("wrote /tmp/poke_card.png")
        }
        exit(pokes > 0 ? 0 : 1)
    }
}

NSApp.run()
