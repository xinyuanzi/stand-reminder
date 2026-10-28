import SwiftUI
import AppKit

/// 吉祥物素材。动作帧每 0.13~0.6 秒换一张，如果每次都 NSImage(contentsOf:)
/// 就是每秒几次读盘 200KB+，所以统一走内存缓存。
///
/// 素材按形象分目录：`Resources/mascots/{style}/{pose}.png`。
/// 一个形象 13~16 张，四个形象平铺在 Resources 根目录时是近 60 个同前缀文件，
/// 加第五个形象就彻底没法扫了。
enum MascotAssets {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(style: String, pose: String) -> NSImage? {
        let key = "\(style)/\(pose)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = load(style: style, pose: pose) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func load(style: String, pose: String) -> NSImage? {
        // 正常路径：.app bundle 里的子目录
        if let url = Bundle.main.url(forResource: pose, withExtension: "png",
                                     subdirectory: "mascots/\(style)"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // 兜底：Tools/ 下的测试工具是裸可执行文件，没有 bundle 结构，
        // 此时 Bundle.main.resourcePath 就是可执行文件所在目录，直接拼路径。
        guard let root = Bundle.main.resourcePath else { return nil }
        return NSImage(contentsOfFile: "\(root)/mascots/\(style)/\(pose).png")
    }
}

enum ReminderStage {
    case sitting
    case stretching
}

enum ReminderUrgency {
    case soft
    case strong
}

/// 视线方向。以头像中心为原点，按鼠标所在方位判定。
enum GazeDirection {
    case center
    case left
    case right
    case up
    case down

    var pose: MascotPose? {
        switch self {
        case .center: return nil
        case .left: return .gazeLeft
        case .right: return .gazeRight
        case .up: return .gazeUp
        case .down: return .gazeDown
        }
    }
}

final class ReminderModel: ObservableObject {
    @Published var stage: ReminderStage = .sitting
    @Published var urgency: ReminderUrgency = .soft
    @Published var minutes: Int = 60
    /// 因为开会被压后补发的提醒
    @Published var deferred: Bool = false
    /// 被戳之后临时顶替标题的那句话，几秒后自动清空
    @Published var pokedLine: String?
    /// 面板是否在屏幕上。隐藏时停掉常驻动画，别对着不可见的视图烧电。
    @Published var visible = false
    /// 当前视线方向，由 AppDelegate 按鼠标位置更新
    @Published var gaze: GazeDirection = .center
    /// 这一轮已经推掉了几次「再等 N 分钟」，由 AppDelegate 从判定机同步过来
    @Published var snoozeStreak: Int = 0

    /// 「再等一会儿」最多给几次。
    ///
    /// 不是拍脑袋定的数：一次 snooze 把累计往回拨 5 分钟，三次就是 15 分钟，
    /// 已经是「我手头这点事马上完」能用的全部额度了。再给下去，
    /// 90 分钟的强提醒会被无限推迟——那正是这个工具唯一不能失守的地方。
    static let maxSnoozeStreak = 3

    var canSnooze: Bool { snoozeStreak < Self.maxSnoozeStreak }
}

/// 被戳时说的短句。都控制在 8 字内，标题一行放得下。
enum PokeLines {
    static let all = [
        "戳我干嘛",
        "别戳啦",
        "去倒杯水吧",
        "戳了也不管用",
        "手放下，站起来",
        "我还在这儿呢"
    ]

    static func random() -> String {
        all.randomElement() ?? "戳我干嘛"
    }
}

struct MascotCard: View {
    @ObservedObject var model: ReminderModel
    @ObservedObject var animator: MascotAnimator
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var habits = Habits.shared

    var onRest: () -> Void
    var onSnooze: () -> Void
    var onPoke: () -> Void

    @State private var pulse = false
    /// 待机层的呼吸起伏（常驻）
    @State private var breathe = false
    /// 待机层的重心摆动，和呼吸错开周期，避免两条动画同频显得像机械振动
    @State private var sway = false
    /// 被戳时的整体下压反馈
    @State private var poked = false

    static let shadowPad: CGFloat = 28

    private var alertColor: Color { Color(red: 0.72, green: 0.24, blue: 0.04) }

    private var titleColor: Color {
        if model.urgency == .strong || model.stage == .stretching {
            return alertColor
        }
        return Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    private var cardFill: Color {
        model.urgency == .strong
            ? Color(red: 1.0, green: 0.965, blue: 0.918)
            : Color(red: 0.998, green: 0.996, blue: 0.990)
    }

    private var strokeColor: Color {
        model.urgency == .strong
            ? Color(red: 0.85, green: 0.42, blue: 0.10).opacity(pulse ? 0.85 : 0.25)
            : Color.black.opacity(0.08)
    }

    /// 主按钮底色。面板永远是 non-activating、不成为 key window，
    /// 系统 .borderedProminent 会按「窗口未激活」渲染成浅底浅字（等于看不见），
    /// 所以按钮外观全部自绘，不依赖系统样式。
    private var primaryFill: Color {
        model.urgency == .strong
            ? Color(red: 0.78, green: 0.30, blue: 0.05)
            : Color(red: 0.13, green: 0.44, blue: 0.90)
    }

    private var title: String {
        // 被戳之后先用一句话顶替标题，几秒后由 AppDelegate 清空
        if let line = model.pokedLine { return line }
        if model.deferred { return "刚才在开会吧？" }
        if model.urgency == .strong { return "已经 \(model.minutes) 分钟了" }
        if model.stage == .sitting {
            // 连续坚持到老友模式之后，语气从「提醒」变成「招呼」
            return habits.friendMode
                ? "又到 \(model.minutes) 分钟啦"
                : "你已经坐了 \(model.minutes) 分钟"
        }
        return "喂——还在坐？"
    }

    private var subtitle: String {
        if model.deferred { return "会议结束了，先把欠的休息补上" }
        if model.urgency == .strong { return "站起来走一圈，只要两分钟" }
        if model.stage == .sitting {
            return habits.friendMode
                ? "老地方见，起来走两步\n我一直在这儿"
                : "起身走两步、喝口水\n五分钟就缓过来了"
        }
        return "再不动一动\n我可要自己走开了"
    }

    /// 各形象构图比例不同，塞进正方形头像区后的视觉占比差别很大。
    /// B 是横卧构图（宽高约 2:1），等比缩放后高度只用一半，需要放大取景。
    /// D 的坐姿帧里椅子的五条腿占掉了下半张图，不放大的话猫头鹰本体
    /// 只有 126pt 圆圈的一半，比橘猫显小一圈。
    private var mascotZoom: CGFloat {
        switch prefs.mascotStyle {
        case "b": return 1.45
        case "d": return 1.30
        case "a": return 1.0
        default: return 1.0
        }
    }

    private var mascotOffset: CGSize {
        switch prefs.mascotStyle {
        case "b": return CGSize(width: 2, height: -8)
        case "d": return CGSize(width: 0, height: 2)
        default: return .zero
        }
    }

    /// 某个形象缺这个姿态的素材时，退到语义最接近的一张，避免整段动画哑掉。
    private func fallbackName(for pose: MascotPose) -> String {
        switch pose {
        case .up: return "up"
        case .stand: return "up"
        case .sitdown: return "sit"
        // 只有猫头鹰有振翅素材，其它形象退到语义最接近的展翅/站定
        case .flap1: return "up"
        case .flap2: return "stand"
        // 某个形象还没画视线素材时退回普通坐姿，不会出现空白圆圈
        case .gazeLeft, .gazeRight, .gazeUp, .gazeDown: return "sit"
        default: return "sit"
        }
    }

    /// 表情层覆盖：本体眨眼时只把这一帧换成闭眼图，不动 pose。
    /// blink 素材是坐姿，站着时套用会跳回坐姿，所以只在坐姿上放。
    ///
    /// 视线跟随同理，只覆盖坐姿。站着/伸懒腰/打拳时忽略朝向——
    /// 那些姿态是整体构图变化，硬套一张坐姿视线图会直接穿帮。
    private var displayPose: MascotPose {
        guard animator.pose == .sit else { return animator.pose }
        if animator.eyeClosed { return .blink }
        if let gazePose = model.gaze.pose { return gazePose }
        return .sit
    }

    private func image(for pose: MascotPose) -> NSImage? {
        let style = prefs.mascotStyle
        let candidates = [pose.rawValue, fallbackName(for: pose)]
        for name in candidates {
            if let image = MascotAssets.image(style: style, pose: name) {
                return image
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 10) {
            // 头像做成真 Button 而不是 onTapGesture：
            // 面板开了 isMovableByWindowBackground，非控件的点击会被窗口拖动吞掉。
            // Button 会被 AppKit 识别为控件，优先级高于背景拖动。
            Button(action: handlePokeTap) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.988, green: 0.957, blue: 0.910))
                        .frame(width: 126, height: 126)

                    ZStack {
                        if let image = image(for: displayPose) {
                            Image(nsImage: image)
                                // 素材 512px 要塞进 112pt（@2x 是 224pt 的 1.3 倍 ≈ 291px），
                                // 縮小采样交给高质量插值，否则毛发边缘会糊成一片。
                                .interpolation(.high)
                                .antialiased(true)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 112, height: 112)
                                // 换图不吃动画，硬切。
                                //
                                // 2D 逐帧本来就该硬切：AI 生成的多帧不是真正的中间帧，
                                // 两张姿态图叠在一起会被看成「两只动物闪一下」，
                                // 比硬切难看得多。这里用 `.animation(nil, value:)`
                                // 而不是 `.transaction { $0.animation = nil }`——
                                // 后者会连待机层的呼吸/摆动一起吃掉，实测抓帧
                                // 呼吸位移直接变成 0。
                                .animation(nil, value: displayPose)
                                // 注：不要给 Image 加 `.id(displayPose)` 来「强制重建」。
                                // 试过，它确实能让每次换帧都重建视图，但重建会把
                                // 外层的 repeatForever 动画一起掐断 —— 实测切成站姿后
                                // 呼吸位移恒为 0，直到下一次重建才恢复，观感就是
                                // 「站起来之后变成一张静止图片」。残影要在窗口层解决
                                // （见 AppDelegate 里的 layerContentsRedrawPolicy），
                                // 不能靠重建视图。
                        }
                    }
                    // 不做交叉淡入。AI 生成的多帧不是真正的中间帧，
                    // 两张姿态图叠 85ms 在 126pt 里会被看成「两只动物闪一下」，
                    // 比硬切难看得多。2D 逐帧动画本来就该硬切。
                    //
                    // 待机层：浮沉 + 微横移。**只用平移，不用缩放也不用旋转。**
                    // 缩放和旋转会让整张图每一帧都重新插值，在 126pt 里表现为整体发虚、
                    // 毛发边缘出现第二层轮廓（旧版绕底部转 ±0.9° 就是这么糊的）；
                    // 平移在整数像素下只是搬纹理，零重采样，图永远 1:1 清晰。
                    // 幅度取整数，@2x 下正好落在物理像素上。
                    .offset(x: sway ? 1 : -1, y: breathe ? -2 : 0)
                    .modifier(ZoomIfNeeded(zoom: mascotZoom))
                    .offset(mascotOffset)
                }
                .frame(width: 126, height: 126)
                .clipShape(Circle())
                .contentShape(Circle())
            }
            .buttonStyle(BareButtonStyle())
            .padding(.top, 2)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(titleColor)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.42, green: 0.41, blue: 0.39))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 5) {
                Button(action: onRest) {
                    Text("我去走走了")
                }
                .buttonStyle(PrimaryButtonStyle(color: primaryFill))

                if model.canSnooze {
                    Button(action: onSnooze) {
                        Text("再等 \(prefs.snoozeMinutes) 分钟")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    // 位置留着、只是不再给按钮：卡片是固定 292pt 高的，
                    // 少一个控件不会让它变矮，只会空出一块——那比明说更奇怪。
                    // 这句话的作用是解释「按钮去哪了」，而不是补一个更狠的按钮。
                    Text("推了 \(ReminderModel.maxSnoozeStreak) 次了，这次我真的不走")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(red: 0.55, green: 0.54, blue: 0.51))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .padding(.top, 1)
        }
        .padding(18)
        .frame(width: 286, height: 292)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardFill)
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(strokeColor, lineWidth: model.urgency == .strong ? 1.6 : 0.5)
        )
        .scaleEffect(poked ? 0.965 : 1)
        // 四周留出阴影绘制空间，否则窗口边界会把柔边和圆角切出生硬直角
        .padding(Self.shadowPad)
        .onAppear {
            syncPulse()
            if model.visible { startIdleMotion() }
        }
        .onChange(of: model.urgency) { _ in syncPulse() }
        .onChange(of: model.visible) { visible in
            // 面板 orderOut 之后不该继续跑重复动画，纯烧电
            if visible { startIdleMotion() } else { stopIdleMotion() }
        }
    }

    /// 被戳：整体下压 4%，松回去的时候带一点回弹
    private func handlePokeTap() {
        withAnimation(.easeOut(duration: 0.09)) { poked = true }
        withAnimation(.easeOut(duration: 0.24).delay(0.09)) { poked = false }
        onPoke()
    }

    /// 待机层：浮沉与重心微移。两条动画周期故意错开（2.9s / 5.3s），
    /// 同周期会让两个方向同时到极点，看起来像整体在机械振动。
    ///
    /// 两者都只驱动 `offset`（平移），不碰缩放和旋转 —— 见 body 里的注释，
    /// 缩放/旋转会让整张图持续重新插值，肉眼就是发虚和边缘重影。
    private func startIdleMotion() {
        withAnimation(.easeInOut(duration: 2.9).repeatForever(autoreverses: true)) {
            breathe = true
        }
        withAnimation(.easeInOut(duration: 5.3).repeatForever(autoreverses: true)) {
            sway = true
        }
    }

    private func stopIdleMotion() {
        withAnimation(.linear(duration: 0.08)) {
            breathe = false
            sway = false
        }
    }

    /// 呼吸式描边只在强提醒时才跑。之前无条件 repeatForever，
    /// 等于让 SwiftUI 在卡片整个可见期间持续 60fps 重绘，纯浪费电。
    private func syncPulse() {
        if model.urgency == .strong {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.12)) { pulse = false }
        }
    }
}

/// 只在真要放大时才叠一层变换。
///
/// `.scaleEffect(1)` 看着是空操作，但 SwiftUI 仍会为它创建变换层 ——
/// 在 isOpaque = false 的透明面板上，多一层合成就多一个可能残留旧内容
/// 的环节。橘猫（a）和柴犬（e）的 zoom 都是 1.0，走无变换分支。
private struct ZoomIfNeeded: ViewModifier {
    let zoom: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if zoom == 1 {
            content
        } else {
            content.scaleEffect(zoom)
        }
    }
}

/// 只保留点击行为、不加任何视觉修饰的按钮样式。
/// 头像自己已经用 poked 状态做了按下反馈，不需要系统再压一层。
private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// 主按钮：实心填充 + 白色粗体，任何窗口状态下的观感都一致。
private struct PrimaryButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

/// 次按钮：无填充的浅灰小字，和主按钮形成明确层级。
private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5))
            .foregroundColor(Color(red: 0.55, green: 0.54, blue: 0.51))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}
