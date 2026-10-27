// 「人还在不在」三个硬信号的探针。
//
// 用途：`CGDisplayIsAsleep` 只在屏幕真的熄灭时才返回 1，日常开发时永远测不到真分支。
// 用它取代「改代码 → 编译 → 重启 app → 熄屏 → 看菜单栏」，一遍就能看清三个值。
//
// 用法：
//   swiftc -O Tools/presence_check.swift -o /tmp/presence_check
//   /tmp/presence_check            # 打印一次
//   /tmp/presence_check 1          # 每秒打印，持续到 Ctrl-C（熄屏前先跑起来，再合盖/锁屏）
//
// 预期：
//   正常使用        → displayAsleep: 0  locked: nil  onConsole: 1
//   等待显示器休眠  → displayAsleep: 1
//   锁屏（屏幕仍亮）→ locked: 1（此时 displayAsleep 可能仍是 0）
//   切到别的用户    → onConsole: 0

import Foundation
import CoreGraphics

func sample() -> String {
    let asleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
    let info = CGSessionCopyCurrentDictionary() as? [String: Any]
    let locked = info?["CGSSessionScreenIsLocked"] as? Bool ?? false
    let onConsole = info?["kCGSSessionOnConsoleKey"] as? Bool ?? true
    let away = asleep || locked || !onConsole
    let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    return String(
        format: "%@   DisplayAsleep: %-5@  Locked: %-5@  OnConsole: %-5@  →  %@",
        stamp,
        asleep ? "1" : "0",
        locked ? "1" : "0",
        onConsole ? "1" : "0",
        away ? "判定离开（会清零）" : "判定在位（最多冻结）"
    )
}

let loop = CommandLine.arguments.count > 1
print(loop ? "每秒采样，Ctrl-C 结束。" : "")
repeat {
    print(sample())
    if loop { Thread.sleep(forTimeInterval: 1) }
} while loop
