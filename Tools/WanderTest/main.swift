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

// MARK: - 强提醒的纵向巡逻

// 1) 纯规则：60 秒里应该来回跑几趟，到端停一下，全程不越界
print("")
let pLow: CGFloat = 4
let pHigh: CGFloat = 900 - size.height - 4
var ps = PatrolState(y: pLow, direction: 1, pausedUntil: nil)
var pnow = 0.0
var flips = 0
var pausedFrames = 0
var pOutOfRange = 0
var maxStep: CGFloat = 0
var lastY = ps.y
var lastDir = ps.direction

for _ in 0..<1800 {                     // 60 秒 @30fps
    pnow += 1.0 / 30.0
    ps = Patrol.step(ps, now: pnow, lower: pLow, upper: pHigh)
    if ps.y < pLow - 0.01 || ps.y > pHigh + 0.01 { pOutOfRange += 1 }
    if ps.pausedUntil != nil { pausedFrames += 1 }
    if ps.direction != lastDir { flips += 1; lastDir = ps.direction }
    maxStep = max(maxStep, abs(ps.y - lastY))
    lastY = ps.y
}
check(pOutOfRange == 0, "巡逻全程不该越界，越界 \(pOutOfRange) 帧")
check(flips >= 4, "60 秒该来回至少两趟（翻转 ≥4 次），实际 \(flips) 次")
check(pausedFrames > 0, "到端应该有停顿帧，实际 \(pausedFrames) 帧")
check(maxStep <= Wander.patrolSpeed + 0.01, "单帧位移不该超过 patrolSpeed=\(Wander.patrolSpeed)，实际 \(maxStep)")

// 2) 停顿会自己结束：停完之后要接着走
var hold = PatrolState(y: pLow, direction: -1, pausedUntil: nil)
hold = Patrol.step(hold, now: 1.0, lower: pLow, upper: pHigh)   // 撞底 → 翻转 + 安排停顿
let yAtBounce = hold.y
let resumeAt = hold.pausedUntil ?? 0
let during = Patrol.step(hold, now: resumeAt - 0.1, lower: pLow, upper: pHigh)
check(abs(during.y - yAtBounce) < 0.01, "停顿期间不该移动，\(yAtBounce) → \(during.y)")
let after = Patrol.step(hold, now: resumeAt + 0.01, lower: pLow, upper: pHigh)
check(after.y > yAtBounce, "停顿结束后应继续向上，\(yAtBounce) → \(after.y)")

// 3) 真窗口：纵向 setFrameOrigin 也得生效（这张面板坑过位移）
print("")
panel.setFrameOrigin(NSPoint(x: maxX, y: pLow))
var i = 0
var travel: CGFloat = 0
var lastPos = panel.frame.origin.y
let t2 = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
    guard panel.isVisible else { return }
    ps.y = panel.frame.origin.y
    ps = Patrol.step(ps, now: Date().timeIntervalSince1970,
                     lower: pLow, upper: pHigh)
    panel.setFrameOrigin(NSPoint(x: maxX, y: ps.y))
    travel += abs(panel.frame.origin.y - lastPos)
    lastPos = panel.frame.origin.y
    i += 1
}
RunLoop.main.add(t2, forMode: .common)
RunLoop.main.run(until: Date().addingTimeInterval(2.0))
t2.invalidate()

check(i >= 50, "2 秒内至少采到 50 帧，实际 \(i)")
check(travel > 100, "2 秒该在纵向移动 100px 以上，实际 \(Int(travel))px")
check(abs(panel.frame.origin.x - maxX) < 1, "巡逻时横坐标应钉在右缘 \(maxX)，实际 \(panel.frame.origin.x)")

panel.orderOut(nil)

print("")
if failures.isEmpty {
    print("游走验证：\(checks) 项全部通过")
    exit(0)
} else {
    print("游走验证：\(checks) 项里 \(failures.count) 项失败")
    exit(1)
}
