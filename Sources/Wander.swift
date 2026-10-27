import CoreGraphics

/// 卡片横向游走的步进规则。
///
/// 抽成纯函数是为了能测。边界反弹看着简单，但很容易写坏：
/// 贴边后方向忘了反过来（下一帧又撞同一边，卡片钉在边界上）、
/// 或者判断写成 `<` 而不是 `<=`（差一像素到不了边，来回抖）。
/// 这类毛病在真窗口上只能靠盯，抽出来就能用数字验。
enum Wander {
    /// 每帧位移（30fps × 2px = 60px/s）
    static let speed: CGFloat = 2

    /// 走一步，返回新的 x；`direction` 在撞到边界时原地翻转。
    ///
    /// 返回 nil 表示这一段没有可走的空间（面板比屏幕还宽），调用方应原地不动。
    static func stepX(from current: CGFloat,
                      direction: inout CGFloat,
                      minX: CGFloat,
                      maxX: CGFloat,
                      speed: CGFloat = Wander.speed) -> CGFloat? {
        guard maxX > minX, speed > 0 else { return nil }
        var x = current + direction * speed
        if x <= minX {
            x = minX
            direction = 1
        } else if x >= maxX {
            x = maxX
            direction = -1
        }
        return x
    }

    /// 收到 `NSWindow.didMoveNotification` 时，判断这次移动是不是程序自己造成的。
    ///
    /// AppKit 对「定时器挪窗口」和「用户拖窗口」发的是同一个通知，通知里
    /// 也没有任何来源字段（有测试：Tools/MoveNotifyTest）。游走 30fps，
    /// 意味着每秒有 30 次「窗口被移动」需要甄别，只能用坐标反推：
    /// 位置正好等于上一帧自己设的那个点，就是自动移动。
    ///
    /// 容差取 1.5px：比半个像素的坐标取整误差大，比用户拖动的最小位移小。
    static func isAutoMove(actual: CGPoint,
                           expected: CGPoint,
                           tolerance: CGFloat = 1.5) -> Bool {
        abs(actual.x - expected.x) <= tolerance
            && abs(actual.y - expected.y) <= tolerance
    }
}
