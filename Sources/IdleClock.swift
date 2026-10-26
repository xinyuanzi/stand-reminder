import Foundation
import CoreGraphics

/// 读取系统"距离上次键鼠操作"的秒数。零权限、零轮询开销。
enum IdleClock {

    /// kCGAnyInputEventType = ~0，表示任意输入事件
    private static let anyInput: CGEventType = CGEventType(rawValue: UInt32.max) ?? .null

    static var seconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
