import AppKit

/// 不抢键盘焦点的浮动面板：能盖在所有窗口之上，但不会打断你正在打的字
final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
