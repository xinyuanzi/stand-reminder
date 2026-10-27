import Foundation

/// 计时落盘。程序退出、崩溃、系统重启都不该把「已经坐了 52 分钟」抹成 0。
///
/// **只做「不丢」，不做「补」**：恢复时把快照里的数字原样拿回来，
/// 绝不把关闭期间流逝的时间加进去。我们没有那段时间的任何证据，
/// 加回去就是编造——而编造出来的分钟数，正是让人不再相信这个工具的东西。
enum SessionStore {

    struct Snapshot: Codable, Equatable {
        var focusSeconds: Double
        var daySitSeconds: Double
        var todayCount: Int
        var savedAt: Date
        var dayKey: String

        init(focusSeconds: Double, daySitSeconds: Double, todayCount: Int,
             savedAt: Date = Date(), dayKey: String? = nil) {
            self.focusSeconds = focusSeconds
            self.daySitSeconds = daySitSeconds
            self.todayCount = todayCount
            self.savedAt = savedAt
            self.dayKey = dayKey ?? SessionStore.dayKey(savedAt)
        }
    }

    /// 多久之内的快照还值得续上。
    /// 超过这个间隔，我们既不知道人有没有坐在那儿，也不知道他是不是刚睡了一觉，
    /// 续上一个陈旧的数字只会骗人——不如从 0 开始，让数字始终等于「我亲眼看见的」。
    static let restoreWindow: TimeInterval = 600

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    /// 恢复决策。纯函数，磁盘那层只是它的壳，测试里直接喂快照验。
    static func restore(_ snapshot: Snapshot, now: Date = Date())
        -> (focus: Double, daySit: Double, todayCount: Int) {
        guard snapshot.dayKey == dayKey(now) else { return (0, 0, 0) }
        let gap = now.timeIntervalSince(snapshot.savedAt)
        let fresh = gap >= 0 && gap <= restoreWindow
        return (fresh ? max(0, snapshot.focusSeconds) : 0,
                max(0, snapshot.daySitSeconds),
                max(0, snapshot.todayCount))
    }

    // MARK: - 磁盘

    /// 测试里指向临时文件，正常运行指 Application Support
    static var fileURL: URL = defaultFileURL

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("XieHuiEr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    static func load(from url: URL? = nil) -> Snapshot? {
        guard let data = try? Data(contentsOf: url ?? fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// 写盘失败不该影响计时，所以这里静默吞掉错误——顶多丢掉几秒的精度
    @discardableResult
    static func save(_ snapshot: Snapshot, to url: URL? = nil) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        do {
            try data.write(to: url ?? fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func clear(at url: URL? = nil) {
        try? FileManager.default.removeItem(at: url ?? fileURL)
    }
}
