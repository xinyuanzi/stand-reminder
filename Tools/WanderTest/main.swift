import AppKit
import SwiftUI

/// 验证游走链路在**真实面板**上确实会动。
///
/// 为什么光有 Wander 的单测不够：单测只能证明算术对，证明不了
/// `NSWindow.setFrameOrigin` 在这个 non-activating + borderless 的面板上真的生效。
/// 这类面板已经坑过一次（系统控件降级、位移动画停在中间态），所以位置类改动
/// 必须拿真窗口验。
///
/// 用法：./Tools/run_wander_test.sh
/// 输出：每 10 帧打印一次 x，最后给结论。
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

let prefs = Prefs.shared
let style = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "c"
prefs.mascotStyle = style

let model = ReminderModel()
model.minutes = 60
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
panel.isMovableByWindowBackground = true

// 和 showReminder 一样：贴着屏幕右下角弹出来
let screen = NSScreen.main ?? NSScreen.screens[0]
let visible = screen.visibleFrame
let margin: CGFloat = 18
let startX = visible.maxX - size.width - margin
panel.setFrameOrigin(NSPoint(x: startX, y: visible.minY + margin))
panel.orderFrontRegardless()

var checks = 0
var failures: [String] = []
func check(_ ok: Bool, _ what: String) {
    checks += 1
    print((ok ? "PASS  " : "FAIL  ") + what)
    if !ok { failures.append(what) }
}

// 起始位置应该就在右边界上，正好等于 maxX
let minX = visible.minX + margin
let maxX = visible.maxX - size.width - margin
check(abs(panel.frame.origin.x - maxX) < 1, "弹出位置应贴着右边界 maxX=\(maxX)，实际 \(panel.frame.origin.x)")

// 真 Timer 驱动，和 wanderStep 完全同一套：30fps、折返规则走 Wander
var direction: CGFloat = -1
var samples: [CGFloat] = [panel.frame.origin.x]
var outOfRange = 0

let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
    guard panel.isVisible else { return }
    guard let x = Wander.stepX(from: panel.frame.origin.x,
                               direction: &direction,
                               minX: minX, maxX: maxX) else { return }
    panel.setFrameOrigin(NSPoint(x: x, y: visible.minY + margin))
    samples.append(x)
    if x < minX || x > maxX { outOfRange += 1 }
}
RunLoop.main.add(t, forMode: .common)

// 跑 3 秒（约 90 帧，能走 180px）
RunLoop.main.run(until: Date().addingTimeInterval(3.0))
t.invalidate()

print("")
print("帧数 \(samples.count)，起点 \(Int(samples[0]))，终点 \(Int(samples.last ?? 0))")
for (i, x) in samples.enumerated() where i % 15 == 0 {
    print("  #\(i)  x=\(Int(x))")
}
print("")

check(samples.count >= 60, "3 秒内至少采到 60 帧（30fps），实际 \(samples.count)")
check(Set(samples).count > 10, "位置必须有变化，实际只出现 \(Set(samples).count) 个不同 x")

let moved = abs((samples.last ?? 0) - samples[0])
check(moved > 100, "3 秒应至少移动 100px，实际 \(Int(moved))px")

check(outOfRange == 0, "全程不该越界，越界 \(outOfRange) 次")

// 逐帧步长：正常是 2px，碰到边界那一帧可能更小
var badSteps = 0
for i in 1..<samples.count {
    let d = abs(samples[i] - samples[i - 1])
    if d > 2.5 { badSteps += 1 }
}
check(badSteps == 0, "单帧位移不该超过 2px（说明用了真实步长），异常 \(badSteps) 帧")

panel.orderOut(nil)

print("")
if failures.isEmpty {
    print("游走验证：\(checks) 项全部通过")
    exit(0)
} else {
    print("游走验证：\(checks) 项里 \(failures.count) 项失败")
    exit(1)
}
