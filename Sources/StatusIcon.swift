import AppKit

/// 菜单栏图标。
///
/// 猫脸是线描的：两只耳朵、闭合的弯眼睛、ω 嘴；正常态还有两侧胡须。
/// 参考的是手绘猫脸那种"温和、不像仪表盘"的观感——只画两个圆点眼睛太呆，
/// 弯眼加嘴之后才像一张脸。
///
/// 画布 20pt（菜单栏容得下），因为胡须要伸到脸外面，18pt 会被裁。
/// 带角标的状态（观察 / 已满 / 强提醒）会**去掉胡须**、把脸往左挪：
/// 胡须正占着右下角那块，和角标叠在一起会糊成一团。
/// 暂停中挂一个暂停符号；免打扰暂时沿用普通猫（文字已经写明）。
///
/// 暂停和免打扰不单独做图标——那是用户自己设的，旁边文字已经写明，图标不必再喊一遍。
/// 全部走 `isTemplate`：只画黑色，由系统在深色菜单栏里自动翻白。
enum StatusIconState: Hashable {
    /// 正常计时
    case normal
    /// 「我去走走了」的观察窗口，右下角一只放大镜
    case observing
    /// 强提醒：闪电
    case strong
    /// 终极提醒：喇叭（它真的会跟着你的光标喊）
    case ultimate
    /// 暂停中：暂停符号
    case paused
    /// 免打扰时段：咖啡杯
    case quiet

    private static var cache: [StatusIconState: NSImage] = [:]

    var image: NSImage {
        if let hit = Self.cache[self] { return hit }
        let made = Self.render(self)
        Self.cache[self] = made
        return made
    }

    // MARK: - 绘制

    private static let side: CGFloat = 20

    private static func render(_ state: StatusIconState) -> NSImage {
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let box = NSRect(x: 0, y: 0, width: side, height: side)
            NSColor.black.set()

            if state == .normal {
                catFace(in: box, whiskers: true)
            } else {
                // 有角标时：脸缩一点、往上左挪，胡须关掉，把右下角让出来
                // 不缩脸，只往上左挪，避免状态切换时脸突然变小
                // 胡须照画：右下那根会被角标的透明缝盖断，看起来像角标挡在前面。
                // 直接删掉一根反而显得脸是残的。
                catFace(in: NSRect(x: box.minX - 1.8, y: box.minY + 0.8,
                                   width: box.width, height: box.height),
                        whiskers: true)
                switch state {
                case .observing: glyphBadge("magnifyingglass", in: box, size: 8.4)
                case .strong:    glyphBadge("bolt.fill", in: box, size: 8.0)
                case .ultimate:  glyphBadge("megaphone.fill", in: box, size: 6.4)
                case .paused:    glyphBadge("pause.fill", in: box, size: 7.2)
                case .quiet:     glyphBadge("cup.and.saucer.fill", in: box, size: 7.6)
                case .normal:    break   // 上面的 if 已处理
                }
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - 猫脸

    /// 参考图的猫脸：一条闭合路径（含耳朵）、弯眼、ω 嘴、可选胡须
    private static func catFace(in box: NSRect, whiskers: Bool) {
        let s = box.width / 20.0
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: box.minX + x * s, y: box.minY + y * s)
        }
        NSColor.black.set()

        let head = NSBezierPath()
        head.move(to: p(4.6, 6.2))
        head.curve(to: p(5.2, 12.4), controlPoint1: p(4.2, 8.4), controlPoint2: p(4.4, 11.0))
        head.line(to: p(6.0, 16.4))                    // 左耳尖
        head.line(to: p(8.4, 13.8))                    // 左耳内沿
        head.curve(to: p(11.6, 13.8),                  // 头顶
                   controlPoint1: p(9.2, 14.3), controlPoint2: p(10.8, 14.3))
        head.line(to: p(14.0, 16.4))                   // 右耳尖
        head.line(to: p(14.8, 12.4))
        head.curve(to: p(15.4, 6.2), controlPoint1: p(15.6, 11.0), controlPoint2: p(15.8, 8.4))
        head.curve(to: p(10.0, 3.4),                   // 下巴
                   controlPoint1: p(15.0, 4.4), controlPoint2: p(12.6, 3.4))
        head.curve(to: p(4.6, 6.2),
                   controlPoint1: p(7.4, 3.4), controlPoint2: p(5.0, 4.4))
        head.close()
        head.lineWidth = 1.7 * s
        head.lineJoinStyle = .round
        head.stroke()

        // 闭着的弯眼（向上鼓）
        for cx in [7.3, 12.7] as [CGFloat] {
            let e = NSBezierPath()
            e.appendArc(withCenter: p(cx, 9.4), radius: 1.25 * s,
                        startAngle: 25, endAngle: 155, clockwise: false)
            e.lineWidth = 1.15 * s
            e.lineCapStyle = .round
            e.stroke()
        }

        // ω 嘴：两段小弧
        for cx in [9.15, 10.85] as [CGFloat] {
            let m = NSBezierPath()
            m.appendArc(withCenter: p(cx, 7.9), radius: 0.85 * s,
                        startAngle: 200, endAngle: 340, clockwise: false)
            m.lineWidth = 1.05 * s
            m.lineCapStyle = .round
            m.stroke()
        }

        guard whiskers else { return }
        for (y1, y2) in [(9.4, 9.9), (7.6, 7.1)] as [(CGFloat, CGFloat)] {
            for (x1, x2) in [(4.4, 1.8), (15.6, 18.2)] as [(CGFloat, CGFloat)] {
                let w = NSBezierPath()
                w.move(to: p(x1, y1))
                w.line(to: p(x2, y2))
                w.lineWidth = 1.0 * s
                w.lineCapStyle = .round
                w.stroke()
            }
        }
    }

    /// 系统符号角标：先挖一圈透明缝，再把符号压上去
    private static func glyphBadge(_ name: String, in box: NSRect, size: CGFloat) {
        let center = NSPoint(x: box.maxX - 2.9, y: box.minY + 3.3)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        let r: CGFloat = 4.2
        NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r,
                                    width: r * 2, height: r * 2)).fill()
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)

        NSColor.black.set()
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return }
        let target = NSRect(x: box.maxX - 7.6, y: box.minY - 0.4, width: 7.4, height: 7.4)
        let s = img.size
        let k = min(target.width / s.width, target.height / s.height)
        img.draw(in: NSRect(x: target.midX - s.width * k / 2, y: target.midY - s.height * k / 2,
                            width: s.width * k, height: s.height * k))
        NSGraphicsContext.restoreGraphicsState()
    }
}
