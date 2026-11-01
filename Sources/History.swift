import Foundation

/// 一天的成绩单。
///
/// 只存**能被系统信号验证**的东西：
/// - `sitSeconds`：坐着多久（判定机算的）
/// - `breaks`：确凿离开（≥60 秒）了几次
/// - `reminders`：当天弹了几次
/// - `longestStretch`：最长的一次连续坐
///
/// 不存「打卡天数」——那个在 `Habits` 里，是另一条线（成就是成，行为是行为）。
/// 也不存喝水量：喝水无法被任何系统信号验证，记进去就是编数字（见 D-36）。
struct DayRecord: Codable, Equatable {
    var dayKey: String
    var sitSeconds: Double = 0
    var breaks: Int = 0
    var reminders: Int = 0
    var longestStretch: Double = 0
}

/// 一周的汇总。给菜单那一行和回顾面板顶部的三个数字用。
struct WeekSummary: Equatable {
    /// 本周 7 天，缺数据的那天是 nil
    var perDay: [DayRecord?] = Array(repeating: nil, count: 7)
    /// 七天加起来坐了多少秒
    var totalSit: Double = 0
    /// 有数据的天数（用来算日均，不能除以 7）
    var daysWithData: Int = 0
    /// 站起来的次数
    var totalBreaks: Int = 0
    /// 最长的一段
    var longestStretch: Double = 0

    /// 日均。**除以「有数据的天数」而不是 7**：周一才过两天就报「日均 40 分钟」
    /// 是把没开机的日子当成坐了 0 分钟，数字会假得离谱。
    var dailyAverage: Double {
        daysWithData > 0 ? totalSit / Double(daysWithData) : 0
    }
}

enum History {
    /// 保留多少天。7 天给本周，另外 7 天用来算「比上周」。
    static let keepDays = 14

    /// 把当天记录写进去（同 `dayKey` 覆盖），按日期升序，只留最近 `keeping` 天。
    ///
    /// `dayKey` 用的是 `YYYY-MM-DD`，字典序就是时间序，不用解析成 Date 再比。
    static func upsert(_ record: DayRecord, into list: [DayRecord],
                       keeping: Int = History.keepDays) -> [DayRecord] {
        var next = list.filter { $0.dayKey != record.dayKey }
        next.append(record)
        next.sort { $0.dayKey < $1.dayKey }
        if next.count > keeping { next.removeFirst(next.count - keeping) }
        return next
    }

    static func dayKey(_ date: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 本周一 00:00。
    ///
    /// 不看系统的「每周第一天」设置——macOS 默认是周日，而这里的图表固定周一到周日。
    static func startOfWeek(_ date: Date, _ calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return cal.startOfDay(for: start)
    }

    /// 本周 7 天（周一 → 周日），**缺的那天是 nil，不是 0**。
    ///
    /// 没开机和坐了 0 分钟是两件事。混成一根 0 高度的柱子，这张图就在骗人——
    /// 而「不骗人」是这个项目唯一舍不得让步的东西。
    static func week(_ list: [DayRecord], containing date: Date,
                     calendar: Calendar = .current) -> [DayRecord?] {
        let monday = startOfWeek(date, calendar)
        return (0..<7).map { offset in
            let d = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            let key = dayKey(d, calendar)
            return list.first { $0.dayKey == key }
        }
    }

    static func summary(_ list: [DayRecord], containing date: Date,
                        calendar: Calendar = .current) -> WeekSummary {
        let perDay = week(list, containing: date, calendar: calendar)
        var s = WeekSummary(perDay: perDay)
        for r in perDay.compactMap({ $0 }) {
            s.totalSit += r.sitSeconds
            s.totalBreaks += r.breaks
            s.longestStretch = max(s.longestStretch, r.longestStretch)
            s.daysWithData += 1
        }
        return s
    }

    /// 上周总坐（用于「比上周少坐 N 小时」）。没有上周数据就返回 nil。
    static func lastWeekTotal(_ list: [DayRecord], containing date: Date,
                              calendar: Calendar = .current) -> Double? {
        let monday = startOfWeek(date, calendar)
        guard let lastMonday = calendar.date(byAdding: .day, value: -7, to: monday) else { return nil }
        let keys = Set((0..<7).map { offset -> String in
            let d = calendar.date(byAdding: .day, value: offset, to: lastMonday) ?? lastMonday
            return dayKey(d, calendar)
        })
        let hits = list.filter { keys.contains($0.dayKey) }
        guard !hits.isEmpty else { return nil }
        return hits.reduce(0) { $0 + $1.sitSeconds }
    }
}

/// 落盘。14 条记录，JSON 存 `UserDefaults`，和 `Habits` 同一层。
final class HistoryStore {
    static let shared = HistoryStore()

    private let store = UserDefaults.standard
    private let key = "history.v1"
    private(set) var days: [DayRecord] = []

    private init() { load() }

    /// 写入今天的记录。同一天反复调用是覆盖，不是追加。
    func recordToday(_ record: DayRecord) {
        let next = History.upsert(record, into: days)
        guard next != days else { return }
        days = next
        if let data = try? JSONEncoder().encode(days) {
            store.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = store.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DayRecord].self, from: data) else { return }
        days = decoded
    }
}
