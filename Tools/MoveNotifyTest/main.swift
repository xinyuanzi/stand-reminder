import AppKit

/// 验证两件 AppKit 事实，它们是「游走被误判成用户拖动」的前提：
///
/// 1. `setFrameOrigin` 会发 `NSWindow.didMoveNotification`。
///    游走是 30fps，等于每秒发 30 次「窗口被移动」的通知。
/// 2. 这个通知里**没有任何字段**能说明是谁移动的。
///    所以 `handlePanelMoved` 只能靠 `NSEvent.pressedMouseButtons` 猜，
///    而「按着鼠标」≠「在拖窗口」—— 用户只是按住卡片、或者点完手没抬起来，
///    就会被误判成拖拽，游走被停掉。
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
panel.isMovableByWindowBackground = true
panel.setFrameOrigin(NSPoint(x: 200, y: 200))
panel.orderFrontRegardless()

var notifyCount = 0
let obs = NotificationCenter.default.addObserver(
    forName: NSWindow.didMoveNotification, object: panel, queue: nil
) { _ in notifyCount += 1 }

// 模拟游走：30 帧，每帧 2px
var direction: CGFloat = -1
let minX: CGFloat = 10
let maxX: CGFloat = 900
for _ in 0..<30 {
    guard let x = Wander.stepX(from: panel.frame.origin.x,
                               direction: &direction,
                               minX: minX, maxX: maxX) else { break }
    panel.setFrameOrigin(NSPoint(x: x, y: panel.frame.origin.y))
    RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 30.0))
}

var checks = 0
var failures: [String] = []
func check(_ ok: Bool, _ what: String) {
    checks += 1
    print((ok ? "PASS  " : "FAIL  ") + what)
    if !ok { failures.append(what) }
}

print("30 帧 setFrameOrigin 触发了 \(notifyCount) 次 didMoveNotification")
print("")

check(notifyCount >= 25, "setFrameOrigin 应触发 didMoveNotification（证明游走每帧都在发通知）")
check(Notification(name: NSWindow.didMoveNotification).userInfo == nil,
      "该通知不带 userInfo，无法区分是程序移动还是用户拖动")
check(panel.frame.origin.x < 200, "面板确实移动了，x 从 200 变成 \(panel.frame.origin.x)")

NotificationCenter.default.removeObserver(obs)
panel.orderOut(nil)

print("")
if failures.isEmpty {
    print("移动通知验证：\(checks) 项全部通过")
    exit(0)
} else {
    print("移动通知验证：\(checks) 项里 \(failures.count) 项失败")
    exit(1)
}
