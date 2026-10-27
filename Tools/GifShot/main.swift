import AppKit
import SwiftUI

/// 给 README 首屏出 GIF 用的抓帧器。
///
/// 和 `WindowShot` 的区别：那边用 `cacheDisplay`，抓的是**模型值**——
/// SwiftUI 里 `repeatForever` 的呼吸/摆动全是 CA 插值，模型值永远不变，
/// 抓出来就是一张张静止图，两帧之间只有姿势切换。做成 GIF 会变成幻灯片，
/// 比真实效果还差。
///
/// 这里改用 `CGWindowListCreateImage` 读**窗口合成后的内容**，插值状态才算数。
/// 抓自己的窗口不需要屏幕录制权限。
///
/// 用法：gifshot <style> <帧数> <间隔秒> <输出目录>
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

let args = CommandLine.arguments
let style = args.count > 1 ? args[1] : "d"
let count = args.count > 2 ? (Int(args[2]) ?? 120) : 120
let interval = args.count > 3 ? (Double(args[3]) ?? 0.08) : 0.08
let outDir = args.count > 4 ? args[4] : "/tmp/gifshot"

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let model = ReminderModel()
model.minutes = 60
model.urgency = .soft
model.stage = .sitting
// 关键：visible 默认是 false，而待机层动画在 onAppear 里要靠它才启动。
// 不设这一行，抓出来的每一帧都是静止的——只有姿势切换，没有呼吸浮动。
model.visible = true

let animator = MascotAnimator()
let card = MascotCard(model: model, animator: animator, onRest: {}, onSnooze: {}, onPoke: {})
let host = NSHostingView(rootView: card)
let size = host.fittingSize

let panel = ReminderPanel(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false)
panel.contentView = host
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
panel.setFrameOrigin(NSPoint(x: 120, y: 120))
panel.orderFrontRegardless()

NSApp.deactivate()

func grab(_ path: String) -> Bool {
    let id = CGWindowID(panel.windowNumber)
    guard id > 0,
          let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id,
                                              [.boundsIgnoreFraming, .bestResolution])
    else { return false }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return false }
    try? data.write(to: URL(fileURLWithPath: path))
    return true
}

var index = 0
var failures = 0

// 加 "full" 参数就只跑「全套三幕」，不随机挑变体——
// 录 GIF 要的是每次一样，随机变体会让重录出来的时长对不上。
let routine = args.contains("full")
    ? Array(MascotRoutine.variants(for: style).prefix(1))
    : MascotRoutine.variants(for: style)

DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    animator.startLoop(routine)
    let t = Timer(timeInterval: interval, repeats: true) { timer in
        let name = String(format: "%@/%03d.png", outDir, index)
        if !grab(name) { failures += 1 }
        index += 1
        if index >= count {
            timer.invalidate()
            let first = NSImage(contentsOfFile: String(format: "%@/000.png", outDir))
            print("抓到 \(index) 帧 → \(outDir)，失败 \(failures) 帧")
            print("单帧尺寸：\(first.map { "\(Int($0.size.width))×\(Int($0.size.height))" } ?? "无")")
            exit(failures == count ? 1 : 0)
        }
    }
    RunLoop.main.add(t, forMode: .common)
}

NSApp.run()
