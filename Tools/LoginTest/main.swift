import Foundation

// 被 launchd 拉起时 ppid 为 1，立刻退出，避免递归自测
if getppid() == 1 { exit(0) }

let path = LaunchAtLogin.agentURL.path

print("初始状态 isEnabled =", LaunchAtLogin.isEnabled)

do {
    try LaunchAtLogin.enable()
    print("enable() 成功")
} catch {
    print("enable() 失败:", error.localizedDescription)
    exit(1)
}

let exists = FileManager.default.fileExists(atPath: path)
print("plist 已写入 =", exists, "路径 =", path)

if let dict = NSDictionary(contentsOfFile: path) {
    print("plist 内容:")
    for (k, v) in dict.sorted(by: { "\($0.key)" < "\($1.key)" }) {
        print("  \(k) = \(v)")
    }
} else {
    print("plist 无法解析！")
}

let printTask = Process()
printTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
printTask.arguments = ["print", "gui/\(getuid())/io.github.xinyuanzi.xiehuier"]
let pipe = Pipe()
printTask.standardOutput = pipe
printTask.standardError = pipe
try? printTask.run()
printTask.waitUntilExit()
let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
print("launchctl print 退出码 =", printTask.terminationStatus)
for line in out.split(separator: "\n").prefix(8) { print("  |", line) }

do {
    try LaunchAtLogin.disable()
    print("disable() 成功")
} catch {
    print("disable() 失败:", error.localizedDescription)
}
print("最终 isEnabled =", LaunchAtLogin.isEnabled)
