import Foundation
import Combine

/// 吉祥物的动作帧。序列帧按 60fps 以下的时间轴切换，形成真实动作而非静态换图。
enum MascotPose: String {
    case sit
    case blink
    case yawn1
    case yawn2
    case scratch
    case punch1
    case punch2
    /// 猫头鹰的「拳头」。鸟没有手，卖力那一拍改用振翅：
    /// flap1 = 双翅抬到与肩齐、半张开，flap2 = 翅膀收拢贴回身体两侧。
    /// 两个位来回切就是一次扇动，不需要额外的中间帧。
    case flap1
    case flap2
    /// 从椅子上下来之后的站定姿势
    case stand
    /// 伸懒腰（站着）
    case up
    /// 从椅子上起身到一半（介于 sit 与 stand 之间）。
    /// 只有橘猫、猫头鹰、柴犬有椅子的三只出了这个素材；其余两只缺帧时会退回 stand。
    case standup
    /// 坐回椅子
    case sitdown
    /// 视线跟随：朝鼠标方向的四个变体（只在坐姿上生效）
    case gazeLeft = "gaze_left"
    case gazeRight = "gaze_right"
    case gazeUp = "gaze_up"
    case gazeDown = "gaze_down"
}

/// 编好的动作序列。
///
/// 改成「三幕小剧场」，而不是原来那套广播体操式的连续动作：
///   第一幕 试探 —— 假装自己也困，打哈欠、挠头看你
///   第二幕 卖力 —— 下椅子，两次才伸完的懒腰，三拳（间隔不等）
///   第三幕 摆烂 —— 摊手坐回去，长定格，像叹了口气
///
/// 趣味不来自姿态数量，来自**结构和节奏**：动作之间留定格、同一动作拆两段做完、
/// 拳头间隔故意不等（0.15/0.15/0.14 配不同的收势）、最后用一段长停顿收尾。
/// 这些全用已有姿态就能做出来，不需要新素材。
enum MascotRoutine {

    /// 第一幕 · 试探
    static let act1: [(MascotPose, TimeInterval)] = [
        (.sit, 0.55),
        (.yawn1, 0.24), (.yawn2, 0.55), (.yawn1, 0.24), (.sit, 0.50),
        (.scratch, 0.42), (.sit, 0.34),
        (.blink, 0.13), 
        // 收得短一点：起身本来就是个快动作，坐太久反而显得它不情愿。
        // 从这一帧到下一幕的 stand 是硬切，中间没有起身过渡帧可插
        // （素材缺 standup），所以让「还没坐稳就站起来」比「坐定再站」更不突兀。
        (.sit, 0.20)
    ]

    /// 第二幕 · 卖力
    static let act2: [(MascotPose, TimeInterval)] = [
        // 起身分两步：先半起着（屁股离座、身体前倾），再站直。
        // 直接 sit → stand 是一步跨过「椅子中央 → 椅子右侧」的位移，
        // 看起来就是猫原地瞬移了一下。
        (.standup, 0.26), (.stand, 0.30),
        // 伸到一半先停一下再伸完，比一次拉满像活的
        (.up, 0.62), (.stand, 0.26),
        (.up, 0.72), (.stand, 0.30),
        // 连打三拳，中间不回站姿。
        // 原来每拳之间都插 0.11 秒的 stand，视觉上等于「挥一下、站好、
        // 再挥一下」，像在原地招手而不是出拳。连起来才是一口气的连击。
        (.punch1, 0.15), (.punch2, 0.13), (.punch1, 0.14),
        // 收势拉长，像打完喘了口气
        (.stand, 0.55)
    ]

    /// 第三幕 · 摆烂
    static let act3: [(MascotPose, TimeInterval)] = [
        // 坐下也是快动作。0.30 秒太从容，反而让人看清椅子是突然出现的
        (.sitdown, 0.24), (.sit, 0.55),
        (.scratch, 0.48), (.sit, 0.40),
        (.blink, 0.13), (.sit, 1.10)
    ]

    /// 全套三幕
    static let full: [(MascotPose, TimeInterval)] = act1 + act2 + act3

    /// 急脾气：不铺垫，下椅子就是两拳
    static let impatient: [(MascotPose, TimeInterval)] =
        [(MascotPose.sit, 0.30)] + act2
        + [(.sitdown, 0.24), (.sit, 0.45), (.blink, 0.13), (.sit, 0.60)]

    /// 困得不想动：只打哈欠，然后眯着
    static let sleepy: [(MascotPose, TimeInterval)] = [
        (.sit, 0.45),
        (.yawn1, 0.26), (.yawn2, 0.62), (.yawn1, 0.26), (.sit, 0.45),
        (.scratch, 0.50), (.sit, 0.35),
        (.blink, 0.13), (.sit, 0.45),
        (.blink, 0.12), (.sit, 1.05)
    ]

    /// 高冷：不看你也不招呼，自己伸个懒腰就坐回去
    static let aloof: [(MascotPose, TimeInterval)] = [
        (.sit, 0.40),
        (.stand, 0.42),
        (.up, 1.00), (.stand, 0.26),
        (.up, 0.60), (.stand, 0.40),
        (.sitdown, 0.24), (.sit, 0.60),
        (.blink, 0.13), (.sit, 0.55)
    ]

    /// 权重不平均：全套占两份，其余各一份
    static let restVariants: [[(MascotPose, TimeInterval)]] = [
        full, full, impatient, sleepy, aloof
    ]

    // MARK: - 猫头鹰（style d）

    /// 猫头鹰共用第一幕和第三幕，只有「卖力」那一段换语汇。
    ///
    /// 为什么必须换：前三只是拟人化的哺乳动物，站着伸懒腰、握拳捶两下都成立；
    /// 猫头鹰是**栖鸟**，翅膀长在体侧、没有可握的手，让它握拳打人既不合解剖也画不出来
    /// （试过两版 punch 帧，出来的是「伸翅膀打招呼」，而且 AI 每版都把体型画小一圈）。
    ///
    /// 同一套叙事、换一套肢体 —— 这才是「一致性」该有的样子：
    /// 结构一致（困 → 起身卖力 → 瘫回去），而不是逼所有动物做同一个动作。
    enum Owl {
        /// 第二幕 · 卖力（振翅版）
        static let act2: [(MascotPose, TimeInterval)] = [
            (.stand, 0.46),
            // 展翅两次，第二次更久、收得更慢，像真的把筋拉开了
            (.up, 0.64), (.stand, 0.26),
            (.up, 0.78), (.stand, 0.30),
            // 三下振翅，抬手快、落下慢，最后一下收势拉长
            (.flap1, 0.17), (.stand, 0.12),
            (.flap1, 0.16), (.stand, 0.12),
            (.flap1, 0.15), (.stand, 0.55)
        ]

        static let full: [(MascotPose, TimeInterval)] = act1 + act2 + act3

        /// 急脾气：不铺垫，站起来就扇
        static let impatient: [(MascotPose, TimeInterval)] =
            [(.sit, 0.30)] + act2
            + [(.sitdown, 0.24), (.sit, 0.45), (.blink, 0.13), (.sit, 0.60)]

        /// 困得不想动：猫头鹰熬夜是专业的，打哈欠这一段天然合身，直接沿用
        static let sleepy: [(MascotPose, TimeInterval)] = MascotRoutine.sleepy

        /// 高冷：自己展一次翅就坐回去，全程不正眼看你
        static let aloof: [(MascotPose, TimeInterval)] = [
            (.sit, 0.40),
            (.stand, 0.42),
            (.up, 1.00), (.stand, 0.26),
            (.up, 0.60), (.stand, 0.40),
            (.sitdown, 0.24), (.sit, 0.60),
            (.blink, 0.13), (.sit, 0.55)
        ]

        static let variants: [[(MascotPose, TimeInterval)]] = [
            full, full, impatient, sleepy, aloof
        ]
    }

    /// 按形象取对应的动作库。缺素材时不会静音，只会退回坐姿（见 MascotCard.image(for:)）。
    ///
    /// E（柴犬）是哺乳动物，两条后腿站得起、前爪握得成拳，和前三只共用同一套动作。
    /// 只有猫头鹰需要换语汇，理由见上面 Owl 的注释。
    static func variants(for style: String) -> [[(MascotPose, TimeInterval)]] {
        switch style {
        case "d": return Owl.variants
        default: return restVariants
        }
    }
}

/// 驱动吉祥物的微表情与动作组合。
///
/// 分三层：
/// - 待机层（呼吸、重心摆动）在视图里用 SwiftUI 动画常驻，不进这里
/// - 表情层（本体眨眼）用独立的随机定时器，不打断正在播的动作
/// - 事件层（哈欠/伸懒腰/打拳、被戳的反应）走队列
final class MascotAnimator: ObservableObject {

    @Published private(set) var pose: MascotPose = .sit
    /// 表情层的闭眼状态。和 pose 分开，才能在不打断动作的前提下自主眨眼。
    @Published private(set) var eyeClosed = false

    private var timer: Timer?
    private var blinkTimer: Timer?
    private var queue: [(MascotPose, TimeInterval)] = []
    private var idleActive = false
    private var loopVariants: [[(MascotPose, TimeInterval)]] = []
    private var looping = false
    private var onComboDone: (() -> Void)?
    /// 被戳等外部事件打断了循环，播完要接着演
    private var resumeLoopAfterReaction = false

    // MARK: - 对外

    /// 开始随机微表情循环（不需要连续动作时用）
    func startIdle() {
        reset()
        idleActive = true
        scheduleIdle(after: Double.random(in: 1.2...2.4))
    }

    /// 开始一段循环演出的动作。每次从 variants 里随机挑一套，套与套之间随机歇一会儿。
    func startLoop(_ variants: [[(MascotPose, TimeInterval)]]) {
        timer?.invalidate()
        timer = nil
        queue.removeAll()
        idleActive = false
        loopVariants = variants.isEmpty ? [MascotRoutine.full] : variants
        looping = true
        resumeLoopAfterReaction = false
        startBlinking()
        playNextCycle()
    }

    func stopLoop() {
        looping = false
    }

    /// 临时播一段「反应」（被戳、躲开），播完自动接回原来的循环。
    ///
    /// 这是零素材交互的关键：不用为「被戳」单独做素材，
    /// 把已有姿态拼成一段短反应就够了。
    func react(_ steps: [(MascotPose, TimeInterval)]) {
        resumeLoopAfterReaction = looping
        looping = false
        play(steps) { [weak self] in
            guard let self else { return }
            if self.resumeLoopAfterReaction {
                self.resumeLoopAfterReaction = false
                self.looping = true
                self.playNextCycle()
            } else {
                self.pose = .sit
            }
        }
    }

    /// 播放一整段动作，播完回调
    func play(_ steps: [(MascotPose, TimeInterval)], completion: (() -> Void)? = nil) {
        timer?.invalidate()
        timer = nil
        idleActive = false
        onComboDone = completion
        queue = steps
        advance()
    }

    /// 定格在某个姿态（比如站起来之后一直保持）
    func hold(_ target: MascotPose) {
        timer?.invalidate()
        timer = nil
        queue.removeAll()
        idleActive = false
        looping = false
        resumeLoopAfterReaction = false
        onComboDone = nil
        pose = target
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        blinkTimer?.invalidate()
        blinkTimer = nil
        queue.removeAll()
        idleActive = false
        looping = false
        resumeLoopAfterReaction = false
        onComboDone = nil
        eyeClosed = false
        pose = .sit
    }

    // MARK: - 循环调度

    private func playNextCycle() {
        guard looping else { return }
        guard let steps = loopVariants.randomElement() else { return }
        play(steps) { [weak self] in
            guard let self, self.looping else { return }
            // 轮与轮之间歇一会儿。间隔固定是「机械感」最直接的来源，
            // 另外留 22% 概率歇得久一点，避免听起来像节拍器。
            self.pose = .sit
            let gap: TimeInterval = Double.random(in: 0...1) < 0.22
                ? Double.random(in: 5.0...8.0)
                : Double.random(in: 1.3...3.2)
            self.timer?.invalidate()
            let t = Timer(timeInterval: gap, target: self, selector: #selector(self.cycleGapTick),
                          userInfo: nil, repeats: false)
            RunLoop.main.add(t, forMode: .common)
            self.timer = t
        }
    }

    @objc private func cycleGapTick() {
        guard looping else { return }
        playNextCycle()
    }

    // MARK: - 表情层：自主眨眼

    private func startBlinking() {
        blinkTimer?.invalidate()
        scheduleBlink(after: Double.random(in: 2.8...7.0))
    }

    private func scheduleBlink(after delay: TimeInterval) {
        blinkTimer?.invalidate()
        let t = Timer(timeInterval: delay, target: self, selector: #selector(blinkTick),
                      userInfo: nil, repeats: false)
        RunLoop.main.add(t, forMode: .common)
        blinkTimer = t
    }

    @objc private func blinkTick() {
        // 只在坐姿上覆盖眨眼。blink 素材本身是坐姿，
        // 站着或正打哈欠时强行闭眼会直接跳姿，等于两个动作打架。
        if pose == .sit {
            eyeClosed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.eyeClosed = false
            }
        }
        // 偶尔连眨两下，比等间隔单眨真实
        scheduleBlink(after: Bool.random() ? 0.22 : Double.random(in: 3.2...8.2))
    }

    // MARK: - 序列推进

    private func scheduleIdle(after delay: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: delay, target: self, selector: #selector(idleTick),
                      userInfo: nil, repeats: false)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func idleTick() {
        guard idleActive else { return }
        switch Int.random(in: 0..<10) {
        case 0..<5:
            queue = [(.blink, 0.13)]
        case 5..<7:
            queue = [(.blink, 0.12), (.sit, 0.17), (.blink, 0.12)]
        case 7..<9:
            queue = [(.scratch, 0.5), (.scratch, 0.3)]
        default:
            queue = [(.yawn1, 0.18), (.yawn2, 0.45), (.yawn1, 0.18)]
        }
        advance()
    }

    private func advance() {
        guard !queue.isEmpty else {
            if idleActive {
                pose = .sit
                scheduleIdle(after: Double.random(in: 2.6...5.4))
            } else {
                // 序列结束不强制回坐姿，交给回调决定落点，避免闪一帧
                let done = onComboDone
                onComboDone = nil
                done?()
            }
            return
        }

        let (next, duration) = queue.removeFirst()
        pose = next

        timer?.invalidate()
        let t = Timer(timeInterval: duration, target: self, selector: #selector(stepTick),
                      userInfo: nil, repeats: false)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func stepTick() {
        advance()
    }
}
