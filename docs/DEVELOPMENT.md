# 开发指南

面向要改这个项目的人。包括：怎么编译、代码怎么分层、**素材怎么生产**（这部分的坑最多）、怎么验证改动没坏。

---

## 1. 环境

| 依赖 | 版本 | 必需 | 说明 |
|---|---|---|---|
| macOS | 13.0+ | ✅ | 已验 14 / arm64 |
| Xcode Command Line Tools | Swift 6.0.3 | ✅ | `xcode-select --install`，**不需要完整 Xcode** |
| Python | 3.11+ | 仅改素材时需要 | 需要 `Pillow`（`pip install pillow`）、`numpy` |
| ffmpeg | 任意 | 仅做预览视频时需要 | `brew install ffmpeg` |

> ⚠️ **Pillow 版本坑**：PIL 12.1.1 保存 80 帧 GIF 只会写出 1 帧。预览视频请用 ffmpeg 出 mp4，不要用 `Image.save(save_all=True)`。

## 2. 构建

```bash
./build.sh
open 歇会儿.app
```

`build.sh` 三步：

1. **编译** — `swiftc -O -target arm64-apple-macos13.0` 把 15 个 `Sources/*.swift` 编成单个可执行文件
   - 纯 SwiftUI + AppKit，**没有任何第三方依赖**，也没有 `Package.swift` / `.xcodeproj`
   - 顺序无关，`swiftc` 直接吃整个文件列表
2. **组装 bundle** — 拷 `Resources/Info.plist`，以及整个 `Resources/mascots/` 目录进 `.app/Contents/Resources/`（保留按形象分的子目录）
3. **临时签名** — `codesign --force --deep --sign -`，本地自用够

改完代码直接重跑 `./build.sh`。**改素材也一样要重跑**，因为素材是拷进 bundle 的，不是运行时读取源码目录。

## 3. 目录结构

```
.
├── build.sh                  构建脚本（编译 + 组装 bundle + 临时签名）
├── package.sh                打 dmg（dist/歇会儿-<版本>.dmg）
├── Sources/                  2907 行，无第三方依赖
│   ├── main.swift            NSApplication + .accessory（不占 Dock）
│   ├── AppDelegate.swift     全部调度：喂判定机、弹窗、菜单、鼠标互动      (924)
│   ├── PresenceMachine.swift **判定机（纯函数，可测）**                     (215)
│   ├── IdleClock.swift       读系统空闲秒数（零权限）                     (13)
│   ├── Presence.swift        熄屏/锁屏检测，确凿判定离开（零权限）        (32)
│   ├── SessionStore.swift    计时落盘，重启不归零                         (88)
│   ├── Prefs.swift           UserDefaults 配置 + 免打扰时段判定           (115)
│   ├── Habits.swift          打卡、连续天数、形象解锁规则                (147)
│   ├── LaunchAtLogin.swift   LaunchAgent 开机自启                         (69)
│   ├── MeetingDetector.swift 摄像头/麦克风占用检测                        (54)
│   ├── ReminderPanel.swift   NSPanel 子类，禁止成为 key/main 窗口        (7)
│   ├── MascotAnimator.swift  姿态枚举、动作库、三层动画引擎              (365)
│   ├── MascotCard.swift      SwiftUI 卡片视图 + 表情层覆盖               (405)
│   ├── SettingsView.swift    SwiftUI 设置页「Form」                      (235)
│   └── OnboardingView.swift  三屏首次启动引导（可离屏预览）              (231)
├── Resources/
│   ├── Info.plist
│   ├── mascots/{style}/{pose}.png  成品素材（512×512 透明 PNG）
│   └── frames/{style}/{pose}_raw.png  AI 原始出图（1024×1024，**不入库**）
├── Tools/                    开发期脚本与测试工具，不参与发布
│   ├── run_tests.sh          判定机用例的唯一入口（一条命令 3 秒跑完）
│   ├── run_fullscreen_test.sh 全屏 Space 验证（会切一次全屏，6 秒）
│   ├── paths.py              素材路径的唯一出处（改目录结构只改这里）
│   ├── normalize.py          白底抠透明 + 统一裁切
│   ├── add_up_frames.py      反解裁切窗口 + render
│   ├── chair_align.py        对齐①：按椅子锚点
│   ├── content_align.py      对齐②：按内容包围盒
│   ├── fixed_align.py        对齐③：固定取景（推荐）
│   ├── warm_align.py         实验失败，留作反向教材
│   ├── group_align.py        按头顶宽度定缩放
│   ├── make_icon.py          生成 AppIcon.icns（猫头鹰头部特写）
│   ├── make_hero_gif.py      帧序 → README 首屏 GIF（铺底 + 压色 + 控体积）
│   ├── presence_check.swift  熄屏/锁屏三信号探针（换判定依据时先跑它）
│   ├── PresenceTest/         判定机时间轴用例（改判定逻辑必跑）
│   ├── FullscreenTest/       全屏 Space 验证（改窗口层级/collectionBehavior 必跑）
│   ├── AnimTest/             动作引擎行为测试
│   ├── PokeTest/             验证开窗口拖动的面板上按钮仍能点
│   ├── GazeTest/             验证视线切换真的换图
│   ├── WindowShot/           真窗口取图（单张，cacheDisplay）
│   ├── GifShot/              真窗口抓帧序（CGWindowListCreateImage，能录到插值动画）
│   ├── Preview/              离屏渲染设置页
│   └── LoginTest/            自启 plist 验证
└── docs/
    ├── DEVELOPMENT.md        本文件
    ├── DECISIONS.md          设计决策与踩坑
    ├── ROADMAP.md            路线图
    └── images/               README 用图
```

## 4. 运行时架构

```
每秒 tick（AppDelegate.tick）
│
├── 采集信号：IdleClock.seconds / Presence.isAway / MeetingDetector.isBusy（限频 5s）
│
├── PresenceMachine.step(now:input:thresholds:)  ← 纯函数，不读时钟不碰 UI
│   │
│   ├── 结算离开（awaySince 由熄屏/系统睡眠通知在事发瞬间写入）
│   │     ├── 持续 ≥ 30s → 清零；坐够软阈值的话顺手记一次打卡
│   │     └── < 30s     → 当作没走成，什么都不动
│   │
│   ├── 累计 focusSeconds += min(delta, 3)
│   │     ├── 熄屏 / 锁屏   → 这一秒不算
│   │     └── 间隔 > 3 秒    → 只认 3 秒（定时器被挂起过，不认识的间隔不补）
│   │
│   ├── 静默   idle ≥ 5 分钟  → 只压制升级：不起升级计时、不追鼠标
│   ├── 长静默 idle ≥ 30 分钟 → **累计照涨**，但先不弹；手一回来立刻补发
│   │
│   └── 该弹了？focusSeconds ≥ 软阈值 且 本轮没弹过 且 允许提醒（非暂停/免打扰/已满）
│         ├── 离开 / 开会 / 长静默 → deferredPending = true（恢复后补发）
│         └── 否则                 → shouldShowReminder
│
├── 按事件执行：settledAway → hideReminder()；shouldShowReminder → showReminder()
├── 落盘：约每 10 秒写一次 ~/Library/Application Support/XieHuiEr/session.json
└── 菜单刷新（专注时长 / 今日坐多久 / 静默与会议说明）
```

**三段逻辑为什么这么分**

| 层 | 谁 | 职责 | 能不能测 |
|---|---|---|---|
| 采集 | `IdleClock` / `Presence` / `MeetingDetector` | 只负责把系统信号读成三个值 | 不能（依赖真实机器状态） |
| 判定 | `PresenceMachine` | 只回答「记多少、清不清、弹不弹」 | **能**，15 组时间轴用例 |
| 执行 | `AppDelegate` | 弹窗、动画、菜单、落盘 | 不能（要真窗口） |

**这是 v0.11.0 的关键改动**：v0.9.2–v0.9.5 连续四个版本改的都是同一段判定逻辑，每次只能靠「重启 → 盯菜单栏」手测，因为它和 UI、定时器、系统读取缠在一起。抽成纯函数之后，`合盖 8 小时` 就是把 `now` 往前跳 28800 秒，3 秒跑完。

**落盘策略：只续数字，不补间隙**（[D-23](DECISIONS.md#d-23--落盘只续数字不补间隙)）

```
每 tick：  now - lastPersistAt >= 10s  → 写 { focusSeconds, daySitSeconds, todayCount, savedAt, dayKey }
启动时：  SessionStore.restore(snapshot)
            ├── dayKey 不同        → 全部从 0
            ├── focusSeconds       → 仅当 savedAt 在 10 分钟内才续
            └── daySitSeconds / todayCount → 同一天就续
退出时：  applicationWillTerminate → 立刻写一次
```

**关闭期间流逝的时间永远不加回去**——那段时间没有任何证据，加进去就是编造。

**弹窗的生命周期**

```
showReminder()
  ├── 建 NSPanel（只建一次，之后复用）
  ├── animator.startLoop(MascotRoutine.variants(for: style))
  ├── 定位到鼠标所在屏的右下角
  ├── alpha 0 → 1 淡入（0.22s）
  ├── startEscalation()    escalateSeconds 后开始游走
  └── startGazeTracking()  15fps 更新视线

hideReminder()
  ├── 停掉所有 timer
  └── alpha 1 → 0 淡出（0.18s）→ **在 completion 里**才 animator.reset()
```

### 动画三层

| 层 | 在哪 | 触发 | 会打断别的层吗 |
|---|---|---|---|
| 待机层 | `MascotCard` 的 SwiftUI 修饰符 | 常驻（浮沉 2.9s / 横移 5.3s，**只平移不缩放不旋转**） | 不会，只是叠一层位移 |
| 表情层 | `MascotAnimator.eyeClosed` + `ReminderModel.gaze` | 随机 3.2~8.2s / 15fps | 不会，只在 `pose == .sit` 时覆盖 |
| 事件层 | `MascotAnimator` 的队列 | 循环播放、被戳反应 | 会，`react()` 会接管队列，播完接回 |

**这个分层是「活着」和「停在某帧」的分界线。** 只有事件层的时候，动物在两次动作之间就是一张静止图片，看起来像贴纸。

### 表情层为什么只覆盖坐姿

`blink` / `gaze_*` 素材都是坐姿。站着或伸懒腰时套用会**直接跳回坐姿**——不是叠加，是整个人换了一张图。

```swift
// MascotCard.swift
private var displayPose: MascotPose {
    guard animator.pose == .sit else { return animator.pose }
    if animator.eyeClosed { return .blink }
    if let gazePose = model.gaze.pose { return gazePose }
    return .sit
}
```

## 5. 素材生产流水线

这是本项目最特殊的一段：**没有美术，全部素材是 AI 出图 + 脚本对齐**。

### 5.1 命名约定

**一个形象一个文件夹**。四个形象 × 13~16 张 = 近 60 个文件，平铺在 `Resources/` 根目录时前缀全一样，加第五个形象就没法扫了。

```
Resources/frames/{style}/{pose}_raw.png      ← AI 原始图，1024×1024，白底（不入库）
Resources/mascots/{style}/{pose}.png         ← 抠图对齐后的成品，512×512，透明
```

`style`：`a` 橘猫 / `b` 水獭 / `c` 小熊 / `d` 猫头鹰
`pose`：`sit` `blink` `yawn1` `yawn2` `scratch` `stand` `up` `punch1` `punch2` `flap1` `flap2` `sitdown` `gaze_left` `gaze_right` `gaze_up` `gaze_down`

路径只在两处出现，改结构时都改这两处：

| 位置 | 怎么用 |
|---|---|
| `Tools/paths.py` | 所有 Python 脚本调 `frame_raw(style, pose)` / `mascot_png(style, pose)`，路径基于 `__file__` 计算，**脚本可以在任何目录执行** |
| `MascotAssets.image(style:pose:)` | App 侧唯一入口。`.app` 里走 `Bundle.main.url(forResource:subdirectory: "mascots/{style}")`，裸可执行文件（测试工具）走 `resourcePath` 拼路径兜底 |

**加形象不需要改任何路径代码**，建个 `Resources/mascots/e/` 目录就能用。

**缺素材不会崩**，`MascotCard.image(for:)` 会按 `fallbackName` 退到语义最接近的一帧（比如所有 gaze 退到 `sit`）。但**别把没画完的姿态先注册进 `Unlocks`**——用户选中后会因为缺素材全部回落同一帧，等于一只不动的雕塑。

### 5.2 出图：提示词模板

一致性全靠**图生图 + 锁死的否定清单**。核心模板：

```
保持这张图完全不变：同一只{角色描述}、同样的羽毛/毛发颜色和材质、
同一张灰色带轮办公椅、同一机位、同一缩放、同一纯白背景、同样的柔和光线。

只改变一件事：{动作描述，越具体越好}

眼睛保持和原来一样的半睁、困倦下垂的样子，不要睁大，不要变成惊喜表情。

不要改变机位角度，不要推近或拉远，不要裁切画面，
不要移动{角色}在画面里的位置和大小。不要添加文字。
```

三条硬规则，都是踩出来的：

1. **必须把「不要改机位/缩放/裁切」写进去**。不写，AI 会自作主张推近一档，下一帧就对不上。
2. **眼睛状态要单独锁**。「保持半睁下垂」，不写的话 AI 会顺手把眼睛瞪大——视线左右切换时等于在闪，而且丢了原本的困倦感。
3. **一次只改一件事**。想同时改姿势和表情，两样都做不好。

参考图用**上一个成功的成品 raw**，不要用抠过的 PNG（透明底会让 AI 困惑）。给 `input_fidelity: "high"`。

### 5.3 抠图

```bash
PYTHONPATH=Tools python3 -c "from normalize import strip_background; ..."
```

`normalize.strip_background()` 从画布四边做**泛洪填充**（不是简单的白→透明），这样被角色包住的白底不会被误抠掉。点判定：`min(r,g,b) >= 205 且 max >= 218 且 max-min <= 18`。

### 5.4 对齐：三个工具，别用错

| 工具 | 锚点 | 适用场景 | 什么时候会失效 |
|---|---|---|---|
| `chair_align.py` | 椅子包围盒 | 换姿势幅度大（起身/伸懒腰） | 角色把椅子挡住，只量到露出的扶手 → 缩放完全错 |
| `content_align.py` | 内容包围盒 | **同姿势只改局部**（视线、眨眼） | AI 把某帧画大/小一点，会被强行缩回去 → 每帧体型微动 = 抖 |
| `fixed_align.py` | **固定窗口**，只从参照帧解一次 | **原始图机位没动的一整批**（推荐默认） | 某帧 AI 真画错了尺寸——这时应该**重生成**，不是对齐 |

```bash
# 推荐：整批统一取景（路径由 Tools/paths.py 计算，可以在任何目录执行）
PYTHONPATH=Tools python3 Tools/fixed_align.py d sit stand up flap1 flap2 sitdown

# 只改局部（如视线）
PYTHONPATH=Tools python3 Tools/content_align.py a sit gaze_left gaze_right gaze_up gaze_down
```

`fixed_align.py` 会打印每帧的原始内容高，与参照差 > 24px 就报警——**这个报警是让你去重生成，不是让你去调参数**。猫头鹰的 `punch2` 就是这么被揪出来的（626 vs 804）。

### 5.5 验证素材没做坏

```bash
# ① 包围盒一致性：同一姿势家族应该几乎完全相等
python3 -c "
from PIL import Image
for p in ['sit','blink','yawn1']:
    a=Image.open(f'Resources/mascots/d/{p}.png').convert('RGBA').split()[3]
    print(p, a.getbbox())
"

# ② 像素差异：确认「改的地方真的改了」
#    gaze 帧与 sit 的差异应该 >1 万像素（512² 的 4% 以上）
```

**判断能不能看出来，必须按真实显示尺寸算**：头像区只有 112pt，512 下差 1.9% 的抖动到 112pt 只剩几点像素。低于 blink 的差异量级（约 65 像素）就等于不可见，不用为它做额外素材。

### 5.6 出预览视频

```bash
# 用真窗口抓帧序（Tools/WindowShot）
cd /tmp/ws4 && ./run d soft strip     # 每 0.08s 一张，共 150 张 → /tmp/strip_*.png
ffmpeg -y -framerate 12.5 -i /tmp/strip_%02d.png -c:v libx264 -pix_fmt yuv420p out.mp4
```

`12.5 = 1/0.08`。**采样间隔要短于最短的动作节拍**（振翅是 0.12~0.17s，所以用 0.08s），否则会混叠，看起来像掉帧。

### 5.7 出 README 首屏 GIF

```bash
# ① 抓帧（100 帧 × 0.1s = 一整轮全套三幕）
swiftc -O -target arm64-apple-macos13.0 -framework AppKit -framework SwiftUI \
  Sources/MascotAnimator.swift Sources/Prefs.swift Sources/Habits.swift \
  Sources/MascotCard.swift Sources/ReminderPanel.swift \
  Tools/GifShot/main.swift -o /tmp/gs/run
cp -R Resources/mascots /tmp/gs/
/tmp/gs/run d 100 0.1 /tmp/gifshot full

# ② 拼 GIF
python3 Tools/make_hero_gif.py /tmp/gifshot docs/images/card-routine.gif
```

两个必须知道的点：

- **不能用 `WindowShot` 的 `cacheDisplay` 抓 GIF**。它抓的是**模型值**，而待机层的呼吸/摆动全是 `repeatForever` 的 CA 插值——模型值永远不变，抓出来只有姿势切换、中间一片静止，做成 GIF 比真实效果还差。`GifShot` 改用 `CGWindowListCreateImage` 读窗口合成结果，插值状态才算数（抓自己的窗口不需要屏幕录制权限）。
- **`ReminderModel.visible` 默认是 `false`**，而待机动画在 `onAppear` 里要靠它才启动。测试工具忘了设这一行，抓出来的就是幻灯片。设了之后帧间差异立刻从「大量 0」变成每帧都有几百到几千像素。

GIF 体积控制在 4MB 以内（460px 宽 / 128 色 / 10fps，100 帧实测 1.4MB）。超了就降宽度，别降帧率——降帧率会让振翅那几下糊成一团。

> ⚠️ 无 bundle 的命令行工具里 `Bundle.main.resourcePath` = 可执行文件所在目录，不是项目 `Resources/`。跑测试工具前先把素材目录拷到二进制旁边：`cp -R Resources/mascots /tmp/ws4/`。

## 6. 测试工具

**改判定逻辑之前，先跑这条：**

```bash
./Tools/run_tests.sh     # 全过退出 0，有失败退出 1（约 3 秒）
```

`Tools/PresenceTest/main.swift` 用时间轴回放 13 组场景，共 46 项断言：

| 场景 | 断言什么 |
|---|---|
| 连续工作 60 分钟 | 累计 3600 秒，到点只弹一次 |
| 锁屏 5 秒 | 不结算、累计不丢 |
| 锁屏 40 秒 | 结算一次、记打卡、清零；回来后重新满 60 分钟再弹 |
| 看视频 50 分钟 | 累计一秒不少；长静默期间不弹；手一动立刻补发 |
| 开会 60 分钟 | 记账不停、不弹；会后补发 |
| 合盖 8 小时 | 清零 + 记打卡；不把 8 小时算进今日累计 |
| `delta = 600` | 只认 3 秒（不认识的间隔不补） |
| 永不休眠 3 小时 | 累计照涨、不弹、挂着待补发 |
| 手停 20 分钟 | 到点照弹，只是不升级、不标补发 |
| 暂停 / 免打扰 / 已满 | 不弹，也不该攒成待补发 |
| 落盘恢复 | 2 分钟前续全部；1 小时前只续今日累计；隔天全不续 |
| 落盘往返 | 真写一次磁盘再读回来 |
| 续上 30 分钟后再坐 30 分钟 | 到点必须弹——续上不能把提醒吞掉 |
| 续上的数已过阈值 | 启动后立刻提醒一次 |
| 跨零点 | 当日累计归零，这一轮的专注时长不断 |

其余是行为测试，没有框架，用一次性可执行文件：

```bash
# 动作引擎（约 35s）
swiftc -O -target arm64-apple-macos13.0 -framework AppKit -framework SwiftUI \
  Sources/MascotAnimator.swift Tools/AnimTest/main.swift -o /tmp/animtest && /tmp/animtest

# 真窗口取图（需要额外源码 + 拷素材）
swiftc -O -target arm64-apple-macos13.0 -framework AppKit -framework SwiftUI \
  Sources/MascotAnimator.swift Sources/Prefs.swift Sources/Habits.swift \
  Sources/MascotCard.swift Sources/ReminderPanel.swift \
  Tools/WindowShot/main.swift -o /tmp/ws4/run
cp -R Resources/mascots /tmp/ws4/
/tmp/ws4/run d soft        # 单张 → /tmp/win_d_soft.png
/tmp/ws4/run d soft strip  # 帧序 → /tmp/strip_*.png
```

| 工具 | 断言什么 |
|---|---|
| `PresenceTest` | 判定机 15 组时间轴场景（见上） |
| `FullscreenTest` | 真全屏下卡片是否浮得上来：在屏、跟 Space、层级、前后顺序 |
| `AnimTest` | 循环在动（14s 内 ≥15 次切换）、出现伸懒腰/出拳、被戳后能接回循环、reset 后彻底静止、猫头鹰动作库不出拳 |
| `PokeTest` | `mouseDownCanMoveWindow = true` 时头像 Button 仍能拿到点击 |
| `GazeTest` | 同姿势切 gaze 画面真的变；非坐姿忽略 gaze |
| `WindowShot` | non-activating 面板的实际长相（离屏渲染会掩盖降级问题） |
| `Preview` | 设置页 / 引导页离屏渲染 → `/tmp/settings.png` |
| `LoginTest` | LaunchAgent plist 写入与路径自愈 |

**为什么必须用真窗口测视觉**：离屏 `NSHostingView` 永远按「窗口已激活」渲染，会把 non-activating 面板的降级外观问题全部掩盖掉——按钮白底白字就是这么漏出去的。

**为什么判定逻辑必须能离屏测**：它每秒跑一次，靠人盯菜单栏只能验「这一刻对不对」，验不了「昨天合盖一夜之后对不对」。判定的全部风险都在长尾场景里，而长尾场景只能靠把时间轴快进。

**全屏 Space 怎么自动化验**：`CGWindowListCopyWindowInfo` 不需要屏幕录制权限——它给不了窗口**内容**，但给得了窗口**存在**、`kCGWindowLayer`（层级）和列表顺序（前 → 后）。所以 `FullscreenTest` 自己 `toggleFullScreen` 进真全屏，再把面板弹出来，然后从系统窗口列表里确认三件事：面板在 `optionOnScreenOnly` 里、层级等于 `NSWindow.Level` 的 rawValue、下标小于全屏窗口的下标。再加上 `panel.isOnActiveSpace`，就是「跟不跟得上全屏 Space」的全部可验部分。

> ⚠️ `kCGWindowBounds` 是 CFDictionary，`as? [String: CGFloat]` 会**静默失败**（返回 nil，看起来像「窗口不存在」）。要用 `CGRect(dictionaryRepresentation:)`。这个坑害我第一轮白跑了一次。

## 7. 新增一个形象（Checklist）

1. **先只出 1 张坐姿定妆照**给相关人确认。别一次画 10 张，造型不对就全废
2. 定妆照转成品：`normalize.py` → 作为该形象的参照帧 `Resources/mascots/{x}/sit.png`
3. 按 [5.2](#52-出图提示词模板) 逐张出动作，命名 `{x}_{pose}_raw.png`
4. 坐姿家族（blink / yawn / scratch / sitdown / gaze_*）→ `fixed_align.py`
5. 站立家族（stand / up / punch 或 flap）→ 先确认机位没变，再 `fixed_align.py`
6. 验证：包围盒一致 + 像素差异足够
7. `MascotPose` 不够用的话加枚举（`rawValue` 用下划线命名以匹配文件名）
8. 语汇不匹配的形象，在 `MascotRoutine.variants(for:)` 里给它自己的动作库
9. 补 `fallbackName` 映射，防止缺素材时哑掉
10. 最后才注册进 `Unlocks.styles`
11. 跑 `AnimTest` + `WindowShot` 验收

## 8. 打包与分发

本地自用，`build.sh` 里的 `codesign -s -` 就够了。**要发给别人**，必须过 Gatekeeper：

```bash
# 1. 用开发者证书签名（需要 Apple Developer Program）
codesign --force --deep --options runtime \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" 歇会儿.app

# 2. 打包成 dmg（可选）
hdiutil create -volname "歇会儿" -srcfolder 歇会儿.app -ov -format UDZO 歇会儿.dmg

# 3. 公证
xcrun notarytool submit 歇会儿.dmg \
  --apple-id "you@example.com" --team-id TEAMID --password "app-specific-password" --wait

# 4. 装订票据
xcrun stapler staple 歇会儿.dmg
```

没做这一步之前，别人下载后必须**右键 → 打开**才能运行。

## 9. 工程约束（容易踩）

- **`nonactivatingPanel` 上的系统控件会降级**：所有按钮自绘，别用 `.borderedProminent`
- **位移 + 透明度双动画在 borderless 面板上会停在中间态**，留下固定偏移。只做透明度
- **`animator.$pose.sink{}` 的返回值必须持有**，写成 `_ =` 会立刻取消订阅
- **`NSWindow.didMoveNotification` 要指定 `object:`**，用 `nil` 会把设置窗口的拖动也算进来
- **`NSScreen.main` 不可作为定位依据**，会随窗口焦点在双屏间漂移。用 `NSEvent.mouseLocation` 反查
- **状态栏 title 每秒无脑赋值会触发重排重绘**，只在文案真的变了才写
- **`ReminderModel.visible` 默认 `false`**，待机动画靠它启动。离屏/抓帧工具不设它，看到的永远是静止画面
- **会议检测不便宜**，不要每秒查。只在「快到该提醒了」或「有欠着的提醒」时轮询，且限频 5s
- **不要用「每秒 +1」记账**。定时器会被 App Nap 拉长、被系统睡眠挂起，`+= 1` 会把 8 小时的间隔当成 8 秒。要用真实间隔，并且**封顶**（`min(delta, 3)`）——不认识的间隔不补
- **只有确凿信号能删数据**。熄屏、锁屏可以清零；任何「手停了多少分钟」的判断都只能改提醒强度，不能碰累计（[D-21](DECISIONS.md#d-21--去掉冻结状态只有离开才清零)、[D-22](DECISIONS.md#d-22--归零兜底改成长静默能删数据的只有确凿信号)）
- **判定逻辑不进 `AppDelegate`**。只要一段逻辑不读时钟、不碰 UI，就抽成纯结构体放进 `Sources/`，并在 `Tools/PresenceTest` 里补一条时间轴用例
