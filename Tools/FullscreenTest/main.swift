import AppKit
import SwiftUI

/// 全屏 Space 验证：卡片到底能不能浮在全屏窗口之上。
///
/// 这个场景一直是「配了 `.fullScreenAuxiliary` 但从没验过」。之前以为只能人肉看，
/// 其实不用录屏权限——`CGWindowListCopyWindowInfo` 能拿到窗口的存在、层级和前后顺序。
///
/// 做法：自己进真全屏（等同于一个全屏视频 App 占了一个 Space），再把提醒面板弹出来，
/// 然后从系统窗口列表里确认：面板在屏上、层级更高、排在前面、尺寸对得上、跟进了这个 Space。
///
/// 跑法：./Tools/run_fullscreen_test.sh
/// 注意：会短暂切一次全屏，桌面会闪一下，约 6 秒。

var failures: [String] = []
var checks = 0

func check(_ ok: Bool, _ what: String) {
    checks += 1
    if !ok { failures.append(what) }
    print(ok ? "  ✓ \(what)" : "  ✗ \(what)")
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.regular)

let model = ReminderModel()
model.minutes = 61
model.urgency = .soft
model.stage = .sitting

let animator = MascotAnimator()
let card = MascotCard(model: model, animator: animator, onRest: {}, onSnooze: {}, onPoke: {})
let side = 286 + MascotCard.shadowPad * 2

/// 主窗口：扮演「全屏播放的视频」——它是当前 Space 里最大的那个窗口
let stage = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
    styleMask: [.titled, .closable, .resizable],
    backing: .buffered, defer: false
)
stage.title = "模拟全屏视频"
stage.collectionBehavior = [.fullScreenPrimary]
stage.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)

/// 和 AppDelegate 里一模一样的面板参数。差一个 flag，这个测试就没有意义。
let panel = ReminderPanel(
    contentRect: NSRect(x: 0, y: 0, width: side, height: side),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered, defer: false
)
panel.contentView = NSHostingView(rootView: card)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
panel.isMovableByWindowBackground = true

func ourWindows() -> [[String: Any]] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                         kCGNullWindowID) as? [[String: Any]] ?? []
    return list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() }
}

/// kCGWindowBounds 是 CFDictionary（四个 CGFloat），直接 as? [String: CGFloat] 会失败
func boundsOf(_ info: [String: Any]) -> CGRect? {
    guard let raw = info[kCGWindowBounds as String],
          let dict = raw as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: dict)
}

func dumpWindows(_ title: String) {
    print("  [\(title)] 本进程在屏上的窗口：")
    for (i, info) in ourWindows().enumerated() {
        let b = boundsOf(info) ?? .zero
        let layer = info[kCGWindowLayer as String] as? Int ?? -1
        print("    #\(i) layer=\(layer) \(Int(b.width))×\(Int(b.height)) @(\(Int(b.minX)),\(Int(b.minY)))")
    }
}

/// 从系统窗口列表里找面板那个窗口，返回它在列表里的下标（越小越靠前）。
/// 尺寸以 NSWindow.frame 为准——SwiftUI 内容的 fittingSize 和 side 差几像素是常态。
func panelIndex() -> Int? {
    let target = panel.frame.size
    return ourWindows().firstIndex { info in
        guard let b = boundsOf(info) else { return false }
        return abs(b.width - target.width) < 4 && abs(b.height - target.height) < 4
    }
}

func stageIndex() -> Int? {
    ourWindows().firstIndex { info in
        guard let b = boundsOf(info) else { return false }
        return b.width > 600 && b.height > 400
    }
}

func layerOf(_ index: Int) -> Int? {
    guard let info = ourWindows()[safe: index] else { return nil }
    return info[kCGWindowLayer as String] as? Int
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

func later(_ seconds: Double, _ block: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
}

later(0.8) {
    print("进入全屏…")
    stage.toggleFullScreen(nil)
}

later(2.6) {
    check(stage.styleMask.contains(.fullScreen), "主窗口已进入真全屏（占据独立 Space）")

    // 落在全屏所在屏的右下角，和真实弹窗一致
    let screen = stage.screen ?? NSScreen.main!
    let f = screen.visibleFrame
    panel.setFrameOrigin(NSPoint(x: f.maxX - side - 24, y: f.minY + 24))
    panel.orderFrontRegardless()
}

later(3.6) {
    print("\n弹出后检查：")
    dumpWindows("弹出后")
    check(panel.isVisible, "面板 isVisible")
    check(panel.isOnActiveSpace, "面板跟进了当前（全屏）Space")

    let idx = panelIndex()
    check(idx != nil, "系统窗口列表里能看到这个面板（说明真的画到屏上了）")

    let sIdx = stageIndex()
    check(sIdx != nil, "全屏主窗口也在列表里（对照组成立）")
    if let p = idx, let s = sIdx {
        check(p < s, "面板排在全屏窗口之前（前 → 后顺序：面板 #\(p) < 全屏 #\(s)）")
    }
    if let p = idx, let layer = layerOf(p) {
        check(layer == NSWindow.Level.floating.rawValue,
              "软提醒层级 = \(NSWindow.Level.floating.rawValue)，实际 \(layer)")
    } else {
        check(false, "读不到面板的窗口层级")
    }

    // 强提醒的层级更高，同样要压过全屏
    panel.level = .screenSaver
}

later(4.2) {
    print("\n强提醒层级：")
    if let p = panelIndex(), let layer = layerOf(p), let s = stageIndex() {
        check(layer == NSWindow.Level.screenSaver.rawValue,
              "强提醒层级 = \(NSWindow.Level.screenSaver.rawValue)，实际 \(layer)")
        check(p < s, "强提醒仍排在全屏窗口之前")
    } else {
        check(false, "强提醒下读不到窗口信息")
    }
    check(panel.collectionBehavior.contains(.canJoinAllSpaces), "保留了 canJoinAllSpaces（切 Space 也跟得上）")
    check(panel.collectionBehavior.contains(.fullScreenAuxiliary), "保留了 fullScreenAuxiliary")
}

later(4.8) {
    print("")
    if failures.isEmpty {
        print("全屏验证：\(checks) 项全部通过")
    } else {
        print("全屏验证：\(checks) 项里 \(failures.count) 项失败")
    }
    exit(failures.isEmpty ? 0 : 1)
}

NSApp.run()
