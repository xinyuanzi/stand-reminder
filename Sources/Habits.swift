import Foundation
import Combine

/// 解锁规则：连续坚持多少天，放出哪个吉祥物。
struct UnlockRule {
    let style: String
    let name: String
    let days: Int
}

enum Unlocks {
    /// 默认送羊毛毡小熊；其余四只靠坚持解锁。
    ///
    /// 间隔统一 5 天，柴犬摆在最后一档：它是四只里唯一「先有定妆照、
    /// 再按定妆照批量出动作」的，制作成本最高，放在 20 天当压轴。
    static let styles: [UnlockRule] = [
        UnlockRule(style: "c", name: "羊毛毡小熊", days: 0),
        UnlockRule(style: "a", name: "毛绒橘猫", days: 5),
        UnlockRule(style: "d", name: "圆胖猫头鹰", days: 10),
        UnlockRule(style: "b", name: "水彩水獭", days: 15),
        UnlockRule(style: "e", name: "圆胖柴犬", days: 20)
    ]

    /// 连续 30 天进「老友模式」：文案不再是催促，改成熟人语气
    static let friendModeDays = 30

    static func rule(for style: String) -> UnlockRule? {
        styles.first { $0.style == style }
    }

    static func requiredDays(for style: String) -> Int {
        rule(for: style)?.days ?? 0
    }

    static func isUnlocked(_ style: String, streak: Int, forceAll: Bool = false) -> Bool {
        if forceAll { return true }
        return streak >= requiredDays(for: style)
    }

    /// 当前连坚持天数下，应该默认用哪个形象（取解锁里进度最靠后的那个）
    static func bestUnlocked(streak: Int) -> String {
        styles.filter { streak >= $0.days }.max { $0.days < $1.days }?.style ?? "c"
    }

    /// 下一个待解锁的形象，没有则返回 nil
    static func next(after streak: Int) -> UnlockRule? {
        styles.filter { $0.days > streak }.min { $0.days < $1.days }
    }
}

/// 习惯记录。一天完成一次「坐够了并且真的起身」就算打卡。
///
/// 判定口径故意从紧：只有在专注时长已达软提醒阈值之后才发生的休息才算数。
/// 否则随手离开一分钟就能刷天数，解锁会失去意义。
final class Habits: ObservableObject {
    static let shared = Habits()

    private let store = UserDefaults.standard

    private enum Key {
        static let lastDone = "habit.lastDoneDay"
        static let streak = "habit.streak"
        static let best = "habit.best"
        static let total = "habit.totalDays"
    }

    @Published private(set) var streak: Int
    @Published private(set) var best: Int
    @Published private(set) var totalDays: Int
    @Published private(set) var doneToday: Bool

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        streak = store.integer(forKey: Key.streak)
        best = store.integer(forKey: Key.best)
        totalDays = store.integer(forKey: Key.total)
        doneToday = Habits.isToday(store.string(forKey: Key.lastDone))
        // 断签就把连续天数归零，避免显示一个早已中断的数字
        if !doneToday, !Habits.isYesterday(store.string(forKey: Key.lastDone)) {
            streak = 0
        }
    }

    var friendMode: Bool { streak >= Unlocks.friendModeDays }

    /// 今天完成一次休息。一天只记一次，重复调用无副作用。
    func markDoneToday() {
        let today = Habits.dayFormatter.string(from: Date())
        let last = store.string(forKey: Key.lastDone)
        guard last != today else { return }

        if Habits.isYesterday(last) {
            streak += 1
        } else {
            streak = 1
        }
        best = max(best, streak)
        totalDays += 1
        doneToday = true

        store.set(today, forKey: Key.lastDone)
        store.set(streak, forKey: Key.streak)
        store.set(best, forKey: Key.best)
        store.set(totalDays, forKey: Key.total)
    }

    /// 跨过零点后重新对齐状态。
    ///
    /// App 常常连着开几天不退出，如果只在 init 里算一次 `doneToday`，
    /// 昨天的「已打卡」会一路带到今天，菜单上看着像今天已经打过卡了。
    func refreshForNewDay() {
        let last = store.string(forKey: Key.lastDone)
        let today = Habits.isToday(last)
        if doneToday != today { doneToday = today }
        if !today, !Habits.isYesterday(last), streak != 0 {
            streak = 0
            store.set(0, forKey: Key.streak)
        }
    }

    /// 菜单里那行进度文案
    func progressLine() -> String {
        if let next = Unlocks.next(after: streak) {
            let left = next.days - streak
            return "连续坚持 \(streak) 天 · 再 \(left) 天解锁\(next.name)"
        }
        return "连续坚持 \(streak) 天 · 全部形象已解锁"
    }

    // MARK: - 日期比较

    private static func isToday(_ value: String?) -> Bool {
        guard let value else { return false }
        return value == dayFormatter.string(from: Date())
    }

    private static func isYesterday(_ value: String?) -> Bool {
        guard let value, let date = dayFormatter.date(from: value) else { return false }
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))
        else { return false }
        return cal.isDate(date, inSameDayAs: yesterday)
    }
}
