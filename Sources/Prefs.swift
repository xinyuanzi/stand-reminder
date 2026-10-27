import Foundation
import Combine

final class Prefs: ObservableObject {
    static let shared = Prefs()

    private let store = UserDefaults.standard

    @Published var focusMinutes: Int {
        didSet { store.set(focusMinutes, forKey: "focusMinutes") }
    }

    @Published var snoozeMinutes: Int {
        didSet { store.set(snoozeMinutes, forKey: "snoozeMinutes") }
    }

    /// 静默判定：多久没碰键鼠算「进入静默」。
    /// 静默期间**照常计时**，只是先不弹窗——手一回来立刻补提醒。
    /// 思考、跟旁边人说话、线下开会听讲，全都会落到这段里。
    @Published var silentMinutes: Int {
        didSet { store.set(silentMinutes, forKey: "silentMinutes") }
    }

    var silentSeconds: Double { Double(silentMinutes * 60) }

    /// 兜底归零：屏幕永不休眠时（拿不到熄屏信号），只能靠时长判断离开。
    /// 平时用不到——熄屏、锁屏会直接触发归零。
    @Published var awayMinutes: Int {
        didSet { store.set(awayMinutes, forKey: "awayMinutes") }
    }

    /// 兜底归零的秒数阈值。强制比静默阈值大，防止两个值被调反后互相打架。
    var awayResetSeconds: Double {
        max(Double(awayMinutes * 60), silentSeconds + 60)
    }

    /// 强提醒阈值：超过这个时长仍未响应，弹窗升级为强提醒
    @Published var strongMinutes: Int {
        didSet { store.set(strongMinutes, forKey: "strongMinutes") }
    }

    /// 摄像头/麦克风被占用时暂缓弹窗，结束后补发
    @Published var meetingAware: Bool {
        didSet { store.set(meetingAware, forKey: "meetingAware") }
    }

    @Published var dailyCap: Int {
        didSet { store.set(dailyCap, forKey: "dailyCap") }
    }

    /// 吉祥物风格："a" 3D 毛绒橘猫 / "b" 手绘水彩水獭 / "c" 羊毛毡小熊
    @Published var mascotStyle: String {
        didSet { store.set(mascotStyle, forKey: "mascotStyle") }
    }

    /// 一直不点弹窗时，是否让它沿屏幕下缘游走
    @Published var wanderEnabled: Bool {
        didSet { store.set(wanderEnabled, forKey: "wanderEnabled") }
    }

    /// 弹出后多少秒无响应，切换到伸懒腰姿态并开始游走
    @Published var escalateSeconds: Double {
        didSet { store.set(escalateSeconds, forKey: "escalateSeconds") }
    }

    @Published var quietEnabled: Bool {
        didSet { store.set(quietEnabled, forKey: "quietEnabled") }
    }

    /// 免打扰起始时间，从 0 点起的分钟数
    @Published var quietFrom: Int {
        didSet { store.set(quietFrom, forKey: "quietFrom") }
    }

    @Published var quietTo: Int {
        didSet { store.set(quietTo, forKey: "quietTo") }
    }

    /// 调试用：跳过解锁门槛，直接换任意形象（自己开发时不然要等 15 天）
    @Published var debugUnlockAll: Bool {
        didSet { store.set(debugUnlockAll, forKey: "debugUnlockAll") }
    }

    private init() {
        focusMinutes = store.object(forKey: "focusMinutes") as? Int ?? 60
        snoozeMinutes = store.object(forKey: "snoozeMinutes") as? Int ?? 5
        silentMinutes = store.object(forKey: "silentMinutes") as? Int ?? 5
        awayMinutes = store.object(forKey: "awayMinutes") as? Int ?? 30
        strongMinutes = store.object(forKey: "strongMinutes") as? Int ?? 90
        meetingAware = store.object(forKey: "meetingAware") as? Bool ?? true
        dailyCap = store.object(forKey: "dailyCap") as? Int ?? 8
        mascotStyle = store.string(forKey: "mascotStyle") ?? "c"
        wanderEnabled = store.object(forKey: "wanderEnabled") as? Bool ?? true
        escalateSeconds = store.object(forKey: "escalateSeconds") as? Double ?? 12
        quietEnabled = store.object(forKey: "quietEnabled") as? Bool ?? false
        quietFrom = store.object(forKey: "quietFrom") as? Int ?? 720
        quietTo = store.object(forKey: "quietTo") as? Int ?? 810
        debugUnlockAll = store.object(forKey: "debugUnlockAll") as? Bool ?? false
    }

    /// 当前是否处于免打扰时段（支持跨午夜）
    func inQuietHours(now: Date = Date()) -> Bool {
        guard quietEnabled, quietFrom != quietTo else { return false }
        let cal = Calendar.current
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        if quietFrom < quietTo {
            return minutes >= quietFrom && minutes < quietTo
        }
        return minutes >= quietFrom || minutes < quietTo
    }
}
