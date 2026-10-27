import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var habits = Habits.shared
    @State private var loginEnabled = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("吉祥物") {
                HStack(spacing: 10) {
                    ForEach(Unlocks.styles, id: \.style) { rule in
                        mascotButton(rule)
                    }
                }
                .padding(.vertical, 2)

                Text(habits.progressLine()
                     + (habits.doneToday ? " · 今日已打卡" : " · 今天还没打卡"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section("习惯") {
                HStack {
                    statBlock("连续坚持", "\(habits.streak) 天")
                    Divider().frame(height: 28)
                    statBlock("最长记录", "\(habits.best) 天")
                    Divider().frame(height: 28)
                    statBlock("累计", "\(habits.totalDays) 天")
                }
                .padding(.vertical, 2)

                if habits.friendMode {
                    Text("老友模式已开启：文案换成熟人语气，不再是催促。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("连续 30 天进入老友模式。规则：坐够软提醒时长之后真的起身离开，"
                         + "或点一次「我去走走了」，当天就算打卡。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("提醒节奏") {
                Stepper(value: $prefs.focusMinutes, in: 15...180, step: 5) {
                    labeled("软提醒", "\(prefs.focusMinutes) 分钟时弹窗")
                }
                Stepper(value: $prefs.strongMinutes, in: 30...240, step: 5) {
                    labeled("强提醒", "\(prefs.strongMinutes) 分钟时升级")
                }
                Stepper(value: $prefs.dailyCap, in: 1...30) {
                    labeled("每日上限", "最多提醒 \(prefs.dailyCap) 次")
                }
                Stepper(value: $prefs.snoozeMinutes, in: 1...30) {
                    labeled("稍后提醒", "延迟 \(prefs.snoozeMinutes) 分钟")
                }
            }

            Section("免打扰") {
                Toggle(isOn: $prefs.quietEnabled) {
                    labeled("启用免打扰时段", "该时段内不弹提醒")
                }
                if prefs.quietEnabled {
                    HStack {
                        DatePicker("", selection: timeBinding(isFrom: true),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("至").foregroundColor(.secondary)
                        DatePicker("", selection: timeBinding(isFrom: false),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Spacer()
                    }
                }
            }

            Section("行为") {
                Toggle(isOn: $prefs.wanderEnabled) {
                    labeled("不理会时自动游走", "弹出后沿屏幕下缘左右移动")
                }
                Stepper(value: $prefs.escalateSeconds, in: 5...60, step: 1) {
                    labeled("升级为起身动作", "\(Int(prefs.escalateSeconds)) 秒无响应后切换姿态")
                }
                Stepper(value: Binding(
                    get: { Int(prefs.restSeconds / 60) },
                    set: { prefs.restSeconds = Double($0 * 60) }
                ), in: 1...15) {
                    labeled("冻结计时", "\(Int(prefs.restSeconds / 60)) 分钟没碰键鼠就暂停累加（不清零）")
                }
                Stepper(value: $prefs.awayMinutes, in: 10...120, step: 5) {
                    labeled("兜底归零", "熄屏或锁屏立刻归零；这条只在屏幕永不休眠时生效（\(prefs.awayMinutes) 分钟）")
                }
                Toggle(isOn: $prefs.meetingAware) {
                    labeled("开会时暂缓提醒", "摄像头或麦克风占用时不弹，会议结束后补发")
                }
            }

            Section("启动") {
                Toggle(isOn: $loginEnabled) {
                    labeled("开机自动启动", loginError ?? "登录后在菜单栏静默运行")
                }
                .onChange(of: loginEnabled) { enabled in
                    applyLogin(enabled)
                }
            }

            // 这一行是为了「我改了怎么没生效」这类问题存在的。
            // 菜单栏常驻 app 换掉磁盘上的二进制不会影响正在跑的进程，
            // 没有版本号就只能靠 PID 猜跑的是哪一版。
            Section {
                HStack {
                    Text("歇会儿").font(.system(size: 11))
                    Spacer()
                    Text(Self.versionLine)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 470)
        // 高度交给窗口决定，Form 自带滚动。
        // 写死高度（含 fixedSize）的后果是每加一个区块就把底部截掉一截。
    }

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(short) (\(build))"
    }

    private func labeled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(detail).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    private func statBlock(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 15, weight: .semibold))
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func mascotButton(_ rule: UnlockRule) -> some View {
        let unlocked = Unlocks.isUnlocked(rule.style, streak: habits.streak,
                                          forceAll: prefs.debugUnlockAll)
        let selected = prefs.mascotStyle == rule.style

        return Button {
            guard unlocked else { return }
            prefs.mascotStyle = rule.style
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if let image = MascotAssets.image(style: rule.style, pose: "up") {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 58)
                            .opacity(unlocked ? 1 : 0.16)
                            .saturation(unlocked ? 1 : 0)
                    }
                    if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 58)

                Text(rule.name).font(.system(size: 11))

                Text(unlocked
                     ? (selected ? "使用中" : "已解锁")
                     : "还差 \(rule.days - habits.streak) 天")
                    .font(.system(size: 10))
                    .foregroundColor(unlocked ? .secondary : Color.orange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(selected ? 0.16 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    private func applyLogin(_ enabled: Bool) {
        do {
            if enabled {
                try LaunchAtLogin.enable()
            } else {
                try LaunchAtLogin.disable()
            }
            loginError = nil
        } catch {
            loginError = "设置失败：\(error.localizedDescription)"
            loginEnabled = LaunchAtLogin.isEnabled
        }
    }

    private func timeBinding(isFrom: Bool) -> Binding<Date> {
        Binding(
            get: { SettingsView.date(from: isFrom ? prefs.quietFrom : prefs.quietTo) },
            set: { newValue in
                let value = SettingsView.minutes(from: newValue)
                if isFrom { prefs.quietFrom = value } else { prefs.quietTo = value }
            }
        )
    }

    static func date(from minutes: Int) -> Date {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        return base.addingTimeInterval(TimeInterval(minutes * 60))
    }

    static func minutes(from date: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }
}
