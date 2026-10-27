import Foundation
import CoreGraphics

/// 「人到底在不在」的硬信号。
///
/// 空闲时长只能**猜**——读文档、看视频、起身倒水在传感器上是同一个读数。
/// 这两条能**确凿**判定离开，而且都不需要授权：
///   - 显示器已休眠 ⇒ 人肯定不在屏幕前
///   - 会话已锁定   ⇒ 同上（锁屏时屏幕可能还亮着，但没人在用）
///
/// 都不成立时（屏幕亮着、没锁屏），人大概率还在座位上——
/// 看视频、开会听讲、盯着问题想，屏幕都是亮的。
enum Presence {

    /// 主显示器是否已休眠
    static var displayAsleep: Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    /// 会话是否已锁屏，或已切到别的登录用户（Fast User Switching）
    static var sessionInactive: Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let locked = info["CGSSessionScreenIsLocked"] as? Bool, locked { return true }
        if let onConsole = info["kCGSSessionOnConsoleKey"] as? Bool, !onConsole { return true }
        return false
    }

    /// 确凿离开：熄屏或锁屏，任一成立即可立刻清零
    static var isAway: Bool {
        displayAsleep || sessionInactive
    }
}
