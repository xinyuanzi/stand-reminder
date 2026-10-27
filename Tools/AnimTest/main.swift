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

// 第一段：观察 14 秒，够跑完一轮再进下一轮
animator.startLoop(MascotRoutine.restVariants)
RunLoop.main.run(until: Date().addingTimeInterval(14))
let firstRun = probe.changes
print("14 秒内姿态切换 \(firstRun.count) 次，种类 \(Set(firstRun.map { $0.rawValue }).sorted())")

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

RunLoop.main.run(until: Date().addingTimeInterval(8.0))
let afterReact = probe.changes[mark...]
check("反应之后接回循环", afterReact.count > duringReact.count,
      "反应后新增 \(afterReact.count - duringReact.count) 次切换")

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
RunLoop.main.run(until: Date().addingTimeInterval(6))
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

print(fails == 0 ? "\n全部通过" : "\n\(fails) 项失败")
exit(fails == 0 ? 0 : 1)
