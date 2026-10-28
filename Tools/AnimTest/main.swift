import Foundation
import Combine

/// 动作引擎行为测试。
///
/// 注意：循环现在是「随机挑一套动作 + 套间随机歇 1.4~3.6 秒」，
/// 所以不能再断言固定时长或固定顺序，只能断言行为特征。
final class Probe {
    var last: MascotPose = .sit
    var changes: [MascotPose] = []
    /// 必须持有，否则 sink 返回的 AnyCancellable 一释放订阅就没了
    var bag: [AnyCancellable] = []
    func watch(_ animator: MascotAnimator) {
        animator.$pose.sink { [weak self] pose in
            guard let self, pose != self.last else { return }
            self.last = pose
            self.changes.append(pose)
        }
        .store(in: &bag)
    }
}

var fails = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS  " : "FAIL  ") + name + (detail.isEmpty ? "" : "  → \(detail)"))
    if !ok { fails += 1 }
}

let animator = MascotAnimator()
let probe = Probe()
probe.watch(animator)

// 第一段：观察够一轮的量级，确认循环在跑
//
// 用轮询而不是死等 14 秒：循环每轮随机挑一套（从 3.6 秒的 sleepy
// 到 9.5 秒的 full），套间还随机歇 1.3~3.2 秒、22% 概率歇 5~8 秒。
// 死等一个固定窗口，赶上「睡意 + 长歇脚」就会数不够而误报。
// 判据只问「动没动」，所以给到 20 秒上限，动了就往下走。
animator.startLoop(MascotRoutine.restVariants)
var loopWaited = 0.0
while loopWaited < 20 && probe.changes.count < 15 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    loopWaited += 0.5
}
let firstRun = probe.changes
print("\(String(format: "%.1f", loopWaited)) 秒内姿态切换 \(firstRun.count) 次，种类 \(Set(firstRun.map { $0.rawValue }).sorted())")

check("循环确实在动", firstRun.count >= 15, "切换 \(firstRun.count) 次")

// 「动作库里有」和「这 14 秒里恰好抽到了」是两件事。
// 循环每轮随机挑一套、套间还随机歇 1.3~3.2 秒，用运行结果断言内容会变成
// 测运气：抽到 sleepy（只有坐姿和哈欠）就误报失败。内容查数据，运行只查「在动」。
let restPoses = Set(MascotRoutine.restVariants.flatMap { $0.map { $0.0 } })
check("动作库里有伸懒腰", restPoses.contains(.up),
      "\(restPoses.map { $0.rawValue }.sorted())")
check("动作库里有出拳", restPoses.contains(.punch1) || restPoses.contains(.punch2),
      "\(restPoses.map { $0.rawValue }.sorted())")
check("动作库里有坐下过渡", restPoses.contains(.sitdown))

// 第二段：被戳打断，播完反应要自动接回循环
//
// 反应序列的第一拍是 scratch，而 `pose != last` 的判据会跳过「没变化」的赋值。
// 如果戳的瞬间它本来就在 scratch（动作变快之后撞上的概率不低），
// 这一拍就记不到，测试会误报失败。先等它离开 scratch 再戳，
// 测的是「反应有没有播」，不是「运气好不好」。
var waited = 0
while animator.pose == .scratch && waited < 40 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    waited += 1
}
let mark = probe.changes.count
animator.react([(.scratch, 0.30), (.sit, 0.10)])
RunLoop.main.run(until: Date().addingTimeInterval(2.0))
let duringReact = probe.changes[mark...]
check("被戳播了反应", duringReact.contains(.scratch), "\(duringReact.map { $0.rawValue })")

// 反应之后必须接回循环。
//
// 用轮询而不是死等 8 秒：轮与轮之间随机歇 1.3~3.2 秒，另有 22% 概率歇
// 5~8 秒。死等 8 秒有时正好整段落在歇脚里，一行切换都收不到，看起来像
// 「反应把循环掐断了」—— 实际只是运气差。给它 12 秒上限，抓到就往下走。
var resumed = false
var waitedAfter = 0.0
while waitedAfter < 12 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    waitedAfter += 0.5
    if probe.changes.count > mark + duringReact.count { resumed = true; break }
}
check("反应之后接回循环", resumed,
      resumed ? "反应后 \(String(format: "%.1f", waitedAfter))s 内接回"
              : "等了 12 秒一次切换都没有")

// 第三段：隐藏时 reset 必须彻底停手
animator.reset()
let beforeReset = probe.changes.count
RunLoop.main.run(until: Date().addingTimeInterval(3.0))
check("reset 后彻底静止", probe.changes.count == beforeReset,
      "reset 后新增 \(probe.changes.count - beforeReset) 次")

// 第四段：猫头鹰的动作库必须换成振翅，且绝不能出现拳头
//
// 动作库是纯数据，直接查它包含哪些姿态。原来靠跑 14 秒随机抽变体，
// 抽到 sleepy（只有坐姿和哈欠）就会误报 —— 测的其实是运气。
let owlVariants = MascotRoutine.variants(for: "d")
let owlPoses = Set(owlVariants.flatMap { $0.map { $0.0 } })
check("猫头鹰会站起来", owlPoses.contains(.stand))
check("猫头鹰会展翅", owlPoses.contains(.up))
check("猫头鹰会振翅", owlPoses.contains(.flap1))
check("猫头鹰不出拳", !owlPoses.contains(.punch1) && !owlPoses.contains(.punch2),
      "\(owlPoses.map { $0.rawValue }.sorted())")

// 但「数据里有」不等于「引擎真的播得出来」，所以再跑一段确认在动
probe.changes.removeAll()
animator.startLoop(owlVariants)
// 同上：轮询到够数就走，别死等一个固定窗口
var owlWaited = 0.0
while owlWaited < 16 && probe.changes.count < 6 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    owlWaited += 0.5
}
let owlRun = probe.changes
check("猫头鹰动作库在动", owlRun.count >= 6, "切换 \(owlRun.count) 次")
print("猫头鹰 6 秒内切换 \(owlRun.count) 次，种类 \(Set(owlRun.map { $0.rawValue }).sorted())")
animator.reset()

// 第五段：动作节奏——出拳必须是连击，中间不能回站姿
//
// 原来三拳之间各插 0.11 秒的 stand，视觉上是「挥一下、站好、再挥一下」，
// 像原地招手不像出拳。这条断言把这个规则钉住，免得以后又改回去。
var punchIdx = MascotRoutine.act2.enumerated()
    .filter { $0.element.0 == .punch1 || $0.element.0 == .punch2 }
    .map { $0.offset }
// 只查「第一拳到最后一拳之间」。第一拳之后、最后一拳之后的 stand 是收势，
// 那是设计意图，不是把连击拆开。
var brokeCombo = false
if let first = punchIdx.first, let last = punchIdx.last, punchIdx.count >= 2 {
    for i in first...last where MascotRoutine.act2[i].0 == .stand {
        brokeCombo = true
    }
}
check("出拳是连击，中间不回站姿", !brokeCombo,
      brokeCombo ? "第 \(punchIdx.count) 拳之间插了 stand" : "连续 \(punchIdx.count) 拳")

// 起身是硬切（素材缺 standup），所以要短：坐定太久再站起来像不情愿
let tailSit = MascotRoutine.act1.last
check("第一幕收尾要短促", (tailSit?.1 ?? 9) <= 0.25,
      "收尾 \(tailSit?.0.rawValue ?? "?") \(tailSit?.1 ?? 0)s")

// 第六段：坐姿族 / 站姿族之间的接缝
//
// 这个工具只有关键姿态、两帧之间不补间。但「相邻两帧姿态不同」本身不是问题
// —— 哈欠接挠耳朵、出拳接出拳，那本来就是动画在推进。真正会造成视觉跳变的
// 只有一族到另一族：
//
//   坐姿族（猫在椅子上）：sit / blink / yawn1 / yawn2 / scratch / sitdown
//   站姿族（猫站在椅子旁）：stand / up / punch1 / punch2 / flap1 / flap2
//
// 跨族时整只动物在画面里的位置换了地方，所以每一处跨族都必须是设计好的那一步：
//   坐姿族 → 站姿族   只能是 sit → stand       （缺 standup 帧，这一跳躲不掉）
//   站姿族 → 坐姿族   只能是 stand → sitdown   （这个方向有中间帧顶着）
//
// 换句话说：谁要是把 `.yawn2` 直接接 `.up`，猫会「打了个哈欠然后凭空站起来」，
// 而这正是这条断言要拦的东西。
let seated: Set<MascotPose> = [.sit, .blink, .yawn1, .yawn2, .scratch, .sitdown]
// standup 归站姿族：屁股已经离座、身体探出椅子，画面位置已经是「椅子外」了。
// 它存在的意义就是把 sit→stand 这一跳拆成两小步。
let standing: Set<MascotPose> = [.standup, .stand, .up, .punch1, .punch2, .flap1, .flap2]

func family(_ p: MascotPose) -> String {
    if seated.contains(p) { return "坐" }
    if standing.contains(p) { return "站" }
    return "?"
}

// sit→standup 和 sit→stand 都允许：有椅子素材的三只走前者，
// 水獭和小熊没有椅子素材，缺帧时退回 stand，走的还是后者。
let allowedCrossings: Set<String> = [
    "坐→站:sit→standup", "坐→站:sit→stand",
    "站→坐:stand→sitdown",
]

var badCuts: [String] = []
var badEnds: [String] = []
var badDurations: [String] = []
var unclassified: [String] = []

for (libName, lib) in [("哺乳动物", MascotRoutine.restVariants),
                       ("猫头鹰", MascotRoutine.Owl.variants)] {
    for (i, seq) in lib.enumerated() {
        guard let head = seq.first?.0, let tail = seq.last?.0 else {
            badEnds.append("\(libName)#\(i) 是空序列")
            continue
        }
        // 6.1 每一段都必须从坐姿开始、回坐姿结束。
        // 轮与轮之间 `playNextCycle` 会把姿态置成 .sit 再歇 1.3~8 秒，
        // 所以任何一段不以 sit 收尾，都会在「歇一下」那一刻凭空跳一次。
        if head != .sit { badEnds.append("\(libName)#\(i) 开头是 \(head.rawValue)") }
        if tail != .sit { badEnds.append("\(libName)#\(i) 结尾是 \(tail.rawValue)") }

        var crossings = 0
        for j in 1..<seq.count {
            let prev = seq[j - 1].0, cur = seq[j].0
            if family(prev) == "?" { unclassified.append("\(libName)#\(i) \(prev.rawValue)") }
            guard family(prev) != family(cur) else { continue }
            crossings += 1
            let key = "\(family(prev))→\(family(cur)):\(prev.rawValue)→\(cur.rawValue)"
            if !allowedCrossings.contains(key) {
                badCuts.append("\(libName)#\(i) 第 \(j) 帧：\(prev.rawValue)→\(cur.rawValue)")
            }
        }
        // 6.2 一段动作里最多起身一次、坐下一次。
        // 多出来的跨族（哪怕方向合法）说明序列被拼重了。
        if crossings > 2 {
            badCuts.append("\(libName)#\(i) 跨族 \(crossings) 次，一段里只该起身+坐下各一次")
        }

        // 6.3 时长只做防手滑：0 会让这一帧根本看不见，太长会让动作僵住
        for (pose, d) in seq where d <= 0 || d > 1.5 {
            badDurations.append("\(libName)#\(i) \(pose.rawValue) \(d)s")
        }
    }
}

check("每一段都该以坐姿开头结尾（轮次之间靠 .sit 接缝）", badEnds.isEmpty,
      badEnds.joined(separator: "；"))
check("跨族换帧只准是 sit→standup / sit→stand 和 stand→sitdown", badCuts.isEmpty,
      badCuts.joined(separator: "；"))
check("单帧时长应在 0~1.5 秒之间", badDurations.isEmpty,
      badDurations.joined(separator: "；"))
check("每个姿态都该归到某一族（新增姿态时别忘了归类）", unclassified.isEmpty,
      Set(unclassified).sorted().joined(separator: "；"))

// 把跨族次数打出来：每段最多两处（起身一次、坐下一次），
// 超过就说明有段动作被拼重了，或者新加的帧归错了族
let allLibs = MascotRoutine.restVariants + MascotRoutine.Owl.variants
let crossCount = allLibs.reduce(0) { acc, seq in
    acc + (1..<max(seq.count, 1)).filter { family(seq[$0].0) != family(seq[$0 - 1].0) }.count
}
print("共 \(allLibs.count) 段动作，跨族换帧 \(crossCount) 处（每段最多起身 + 坐下各一次）")

print(fails == 0 ? "\n全部通过" : "\n\(fails) 项失败")
exit(fails == 0 ? 0 : 1)
