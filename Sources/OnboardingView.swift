import SwiftUI
import AppKit

/// 首次启动的三屏引导。
///
/// 以前首次启动只是把设置页弹出来——用户看到一堆 Stepper，不知道这是什么、
/// 为什么要调、会不会要权限。三屏各回答一个问题：这是什么 / 要不要授权 / 先调什么。
struct OnboardingView: View {
    @ObservedObject private var prefs = Prefs.shared

    @State private var page: Int
    var onFinish: () -> Void

    /// initialPage 只为离屏预览用（Tools/Preview onboarding 1），正常运行从第 0 屏开始
    init(initialPage: Int = 0, onFinish: @escaping () -> Void) {
        _page = State(initialValue: initialPage)
        self.onFinish = onFinish
    }

    private let cream = Color(red: 0.988, green: 0.957, blue: 0.910)
    private let ink = Color(red: 0.17, green: 0.15, blue: 0.13)

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: permissions
                default: quickSettings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)

            footer
        }
        .frame(width: 520, height: 620)
        .background(cream)
        .preferredColorScheme(.light)
    }

    // MARK: - 第一屏

    private var welcome: some View {
        VStack(spacing: 0) {
            mascot(size: 190)

            Text("歇会儿")
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(ink)
                .padding(.top, 22)

            Text("坐久了，它会来喊你起来")
                .font(.system(size: 14))
                .foregroundColor(ink.opacity(0.55))
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 14) {
                bullet("到点弹一张卡片，配一只正在伸懒腰的猫头鹰")
                bullet("你起身离开，计时自动归零——不用点「我休息了」")
                bullet("一直不理会，它会沿着屏幕下缘慢慢游走")
            }
            .padding(.top, 34)
        }
    }

    // MARK: - 第二屏

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("不需要任何权限")
            subtitle("不会弹授权窗口，也没有「辅助功能」授权这一步。")

            VStack(spacing: 0) {
                permRow("你多久没碰键鼠", "CGEventSource 空闲秒数")
                Divider().opacity(0.4)
                permRow("屏幕熄了没、锁了没", "CGDisplayIsAsleep / 会话状态")
                Divider().opacity(0.4)
                permRow("摄像头麦克风是否被占用", "只问占用，不取内容")
            }
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 26)

            Text("没有网络请求。计时、打卡、形象解锁全部存在本机 UserDefaults。")
                .font(.system(size: 12))
                .foregroundColor(ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
        }
    }

    // MARK: - 第三屏

    private var quickSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("先调这三个")
            subtitle("后面都能在菜单「设置…」里改。")

            VStack(spacing: 18) {
                Stepper(value: $prefs.focusMinutes, in: 15...180, step: 5) {
                    row("坐多久提醒你", "\(prefs.focusMinutes) 分钟")
                }
                Stepper(value: $prefs.silentMinutes, in: 1...30, step: 1) {
                    row("多久没碰键鼠算静默", "\(prefs.silentMinutes) 分钟")
                }
                Toggle(isOn: $prefs.quietEnabled) {
                    row("午休免打扰", prefs.quietEnabled ? "12:00 – 13:30" : "关闭")
                }
                .toggleStyle(.switch)
            }
            .padding(.top, 28)

            Text("静默不等于离开：手停下来思考、看视频都还会照常计时，只是提醒会变得克制，不追着你的鼠标跑。")
                .font(.system(size: 12))
                .foregroundColor(ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
        }
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 10) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(i == page ? ink.opacity(0.75) : ink.opacity(0.18))
                    .frame(width: 6, height: 6)
            }

            Spacer()

            if page < 2 {
                Button("跳过") { finish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(ink.opacity(0.45))

                Button(page == 0 ? "下一步" : "继续") { withAnimation { page += 1 } }
                    .buttonStyle(.borderedProminent)
                    .tint(ink)
                    .controlSize(.large)
            } else {
                Button("开始使用") { finish() }
                    .buttonStyle(.borderedProminent)
                    .tint(ink)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 30)
    }

    // MARK: - 零件

    private func finish() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        onFinish()
    }

    private func mascot(size: CGFloat) -> some View {
        Group {
            if let img = MascotAssets.image(style: "d", pose: "up") {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .medium))
            .foregroundColor(ink)
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(ink.opacity(0.55))
            .padding(.top, 8)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(ink.opacity(0.3))
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permRow(_ what: String, _ how: String) -> some View {
        HStack(spacing: 12) {
            Text(what)
                .font(.system(size: 13))
                .foregroundColor(ink.opacity(0.8))
            Spacer()
            Text(how)
                .font(.system(size: 11))
                .foregroundColor(ink.opacity(0.4))
            Text("无需授权")
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.11, green: 0.42, blue: 0.28))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(red: 0.88, green: 0.95, blue: 0.90))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(ink.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(ink.opacity(0.45))
        }
    }
}
