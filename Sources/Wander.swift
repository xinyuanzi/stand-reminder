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
}
