import CoreGraphics
import Foundation

/// 卡片横向游走的步进规则。
///
/// 抽成纯函数是为了能测。边界反弹看着简单，但很容易写坏：
/// 贴边后方向忘了反过来（下一帧又撞同一边，卡片钉在边界上）、
/// 或者判断写成 `<` 而不是 `<=`（差一像素到不了边，来回抖）。
/// 这类毛病在真窗口上只能靠盯，抽出来就能用数字验。
enum Wander {
    /// 每帧位移（30fps × 2px = 60px/s）
    static let speed: CGFloat = 2

    /// 强提醒沿右缘纵向巡逻的每帧位移（30fps × 3.4px ≈ 102px/s）。
    ///
    /// 比横向游走快一档。这一档的语义是「主动找你」而不是「在旁边晃」，
    /// 但它仍然是匀速可预测的——见 D-32，加速不等于抽搐。
    static let patrolSpeed: CGFloat = 3.4

    /// 单轴走一步，返回新坐标；`direction` 在撞到边界时原地翻转。
    ///
    /// 横向游走和纵向巡逻共用这一段：边界反弹的坑只值得踩一次
    /// （贴边后方向忘了翻、判断写成 `<` 而不是 `<=` 导致差一像素来回抖）。
    /// 两个轴在数学上是同一件事，没必要各写一遍、各踩一遍。
    ///
    /// 返回 nil 表示这一段没有可走的空间（面板比屏幕还大），调用方应原地不动。
    static func step(_ current: CGFloat,
                     direction: inout CGFloat,
                     lower: CGFloat,
                     upper: CGFloat,
                     speed: CGFloat = Wander.speed) -> CGFloat? {
        guard upper > lower, speed > 0 else { return nil }
        var v = current + direction * speed
        if v <= lower {
            v = lower
            direction = 1
        } else if v >= upper {
            v = upper
            direction = -1
        }
        return v
    }

    /// 横向版，保留原签名（测试和调用方都用它）。
    static func stepX(from current: CGFloat,
                      direction: inout CGFloat,
                      minX: CGFloat,
                      maxX: CGFloat,
                      speed: CGFloat = Wander.speed) -> CGFloat? {
        step(current, direction: &direction, lower: minX, upper: maxX, speed: speed)
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

/// 强提醒沿屏幕右缘上下巡逻的状态与步进规则。
///
/// 为什么单独抽出来：「到端停一下再折返」是这一档的关键手感——匀速往返像扫地机器人，
/// 停半秒才像「站在那儿等你」。这条规矩如果只写在 AppDelegate 的 30fps 回调里，
/// 就只能靠肉眼盯，抽出来才能用数字验。
struct PatrolState: Equatable {
    var y: CGFloat
    /// +1 向上，-1 向下
    var direction: CGFloat
    /// 停顿到什么时候；nil 表示没在停
    var pausedUntil: TimeInterval?
}

enum Patrol {
    /// 到达上/下端后停多久
    static let pause: TimeInterval = 0.5

    /// 推进一步。停顿中返回原状态；到端时翻转方向并安排下一次停顿。
    ///
    /// `y` 由调用方每次同步成真实窗口坐标（用户可能刚拖过它），
    /// 这里不假设状态里的 y 一定是最新的。
    static func step(_ s: PatrolState,
                     now: TimeInterval,
                     lower: CGFloat,
                     upper: CGFloat,
                     speed: CGFloat = Wander.patrolSpeed,
                     pause: TimeInterval = Patrol.pause) -> PatrolState {
        var next = s

        if let until = s.pausedUntil {
            if now < until { return next }
            next.pausedUntil = nil
        }

        let before = s.direction
        guard let y = Wander.step(s.y, direction: &next.direction,
                                  lower: lower, upper: upper, speed: speed) else {
            // 屏幕高度装不下卡片：原地停着，别在边界上抖
            return next
        }
        next.y = y
        if next.direction != before {
            next.pausedUntil = now + pause
        }
        return next
    }
}
