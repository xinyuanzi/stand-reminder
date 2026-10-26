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
check("出现过伸懒腰", firstRun.contains(.up))
check("出现过出拳", firstRun.contains(.punch1) || firstRun.contains(.punch2))

// 第二段：被戳打断，播完反应要自动接回循环
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
probe.changes.removeAll()
animator.startLoop(MascotRoutine.variants(for: "d"))
RunLoop.main.run(until: Date().addingTimeInterval(14))
let owl = probe.changes
let owlKinds = Set(owl.map { $0.rawValue }).sorted()
print("猫头鹰 14 秒内切换 \(owl.count) 次，种类 \(owlKinds)")
check("猫头鹰动作库在动", owl.count >= 15, "切换 \(owl.count) 次")
check("猫头鹰会站起来", owl.contains(.stand))
check("猫头鹰会展翅", owl.contains(.up))
check("猫头鹰会振翅", owl.contains(.flap1))
check("猫头鹰不出拳", !owl.contains(.punch1) && !owl.contains(.punch2),
      "\(owlKinds)")
animator.reset()

print(fails == 0 ? "\n全部通过" : "\n\(fails) 项失败")
exit(fails == 0 ? 0 : 1)
