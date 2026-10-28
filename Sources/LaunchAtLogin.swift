import Foundation

/// 开机自启：写入 ~/Library/LaunchAgents 的 LaunchAgent 并交给 launchd。
/// 不依赖开发者证书，本地自建 App 也能稳定生效。
enum LaunchAtLogin {

    private static let label = "io.github.xinyuanzi.xiehuier"

    static var agentURL: URL {
        let dir = ("~/Library/LaunchAgents" as NSString).expandingTildeInPath
        return URL(fileURLWithPath: dir).appendingPathComponent("\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func enable() throws {
        let bundlePath = Bundle.main.bundleURL.path

        let dir = agentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 用 open -a 走 LaunchServices，避免登录时重复拉起第二个实例
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", bundlePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                      format: .xml,
                                                      options: 0)
        try data.write(to: agentURL)

        // 立即在当前会话生效属于锦上添花；失败也不影响下次登录自动启动
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        _ = run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentURL.path])
    }

    static func disable() throws {
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        if FileManager.default.fileExists(atPath: agentURL.path) {
            try FileManager.default.removeItem(at: agentURL)
        }
    }

    /// App 被移动过位置后，重新写一次 plist 让路径自愈
    static func refreshIfNeeded() {
        guard isEnabled else { return }
        try? enable()
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }
}
