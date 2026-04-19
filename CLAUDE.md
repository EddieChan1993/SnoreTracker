# SnoreTracker — Claude Project Guide

## Project Overview
iOS app (SwiftUI, iOS 15+) that manually-triggered background microphone monitoring, detects snoring via FFT frequency analysis, auto-records each snoring event, and displays per-session sleep reports.

## Project Structure
```
SnoreTracker/
├── project.yml                          # xcodegen config — deploymentTarget: 15.0
├── SnoreTracker/
│   ├── SnoreTrackerApp.swift            # App entry point; injects ThemeManager as @EnvironmentObject
│   ├── Info.plist                       # NSMicrophoneUsageDescription, UIBackgroundModes: audio
│   ├── Assets.xcassets/AppIcon.appiconset/  # AppIcon-1024.png (fruit-themed, pink-purple gradient)
│   ├── Models/
│   │   └── SleepModels.swift            # SnoringEvent, SleepSession (Codable, Identifiable)
│   ├── Services/
│   │   ├── AudioMonitorService.swift    # AVAudioEngine tap + FFT snoring detection + recording
│   │   ├── SleepSessionManager.swift    # ObservableObject bridging audio service ↔ SwiftUI
│   │   └── SleepStore.swift             # JSON persistence to Documents/sleep_sessions.json
│   ├── Theme/
│   │   ├── AppTheme.swift               # AppTheme struct with semantic color tokens
│   │   └── ThemeManager.swift           # ObservableObject; @AppStorage("selectedThemeID")
│   └── Views/
│       ├── ContentView.swift            # TabView: 监测 / 报告 / 设置; applies theme to tab bar
│       ├── HomeView.swift               # Manual start/stop; circle level indicator
│       ├── ReportsView.swift            # Per-session list with swipe-to-delete
│       ├── SessionDetailView.swift      # Summary card, SnoringTimeline, recordings playback
│       └── SettingsView.swift           # Sensitivity sliders, theme picker, data management
```

## Architecture

### Session Lifecycle
- **Manual start only** — no auto-start on launch; user taps "开始监测"
- **Each start = new SleepSession** — `toggleMonitoring()` calls `startNewSession()` every time
- **Stop writes endTime** — `closeCurrentSession()` stamps `endTime = Date()` and persists
- **Orphan recovery on launch** — `recoverOrphanedSessions()` in `SleepSessionManager.init()`:
  - Sessions with events + `endTime == nil` → set `endTime = Date()` and save (app was force-killed)
  - Sessions with no events + `endTime == nil` → delete (empty, no useful data)

### Theme System
- `AppTheme` struct: `bgColors`, `bgSnoringColors`, `accent`, `accentLight`, `snoringAccent`, `liveIndicator`, `tabBarBackground`, `cardOpacity`
- `ThemeManager: ObservableObject` with `@AppStorage("selectedThemeID")` — persists across launches
- All views: `@EnvironmentObject var themeManager: ThemeManager`, use `themeManager.current.xxx`
- Two themes: `.dark` (deep navy/blue) and `.fruitJelly` (purple-berry/pink/mint/orange)

### Snoring Detection (AudioMonitorService.swift)
- **Algorithm**: RMS gate → 4096-pt FFT (Accelerate/vDSP) → band energy ratio
- **Snoring band**: 80–800 Hz；`totalE` 范围 80–6000 Hz（`highHi` 作为上界，`highLo` 已删除）
- **Score formula**: `snoreE / totalE`（纯比值，**无高频惩罚项**）
  - `totalE` 从 `snoreLo`（80 Hz）开始，**不包含** 0–80 Hz 次低频
  - 高频惩罚项已彻底移除——打鼾泛音天然延伸至 1 kHz+，惩罚项会系统性压低真实打鼾得分
- **默认阈值**：`minimumRMS = 0.003`，`snoreScoreThreshold = 0.12`（手机放床头 1–2 m 远仍能检测）
- **State machine**: `onLoud()` → `confirmTimer` → `beginSnoring()`；`onSilent()` → `silenceTimer` → `endSnoring()`
- Settings restored from `UserDefaults` in `init()`: `minimumRMS`, `snoreScoreThreshold`, `confirmDelay`, `silenceDelay`

### Scoring (SleepModels.swift)
- **Dual metric**: takes the **worse** of snoring-time-percentage and events-per-hour
- `pctLevel()` / `cphLevel()` 是 `SleepSession` 的私有方法，`snoringScore` 和 `snoringScoreColor` 共用
- Events/hour thresholds (ref: medical AHI): 优秀 <5, 良好 <15, 一般 <30, 较差 ≥30
- Percentage thresholds: 优秀 <5%, 良好 <15%, 一般 <30%, 较差 ≥30%
- `snoringScoreColor` 与 `snoringScore` 使用**同一套**双指标逻辑，颜色和标签不会不一致

### SnoringTimeline (SessionDetailView.swift)
- Track background = full session duration; empty = non-snoring time
- Block X = proportional to `event.startTime` within session
- Block width = `event.duration / sessionDuration * trackWidth` (min 4pt)
- Blocks: plain rectangles, no corner radius; clipped to rounded track via `ctx.drawLayer { lc.clip(to:) }`
- Labels: `HH:mm` at block center x; edges at track start/end; overlapping labels skipped with `prevRight` cursor

### Level Ring Animation
- EMA smoothing: `smoothLevel = rms > smoothLevel ? rms : 0.2 * rms + 0.8 * smoothLevel` — instant attack, slow decay
- SwiftUI: `.animation(.spring(response: 0.12, dampingFraction: 0.7), value: currentLevel)`
- Combine binding in `SleepSessionManager`: **no** `.receive(on: DispatchQueue.main)` — displayTimer already on main thread, async re-dispatch breaks 20 Hz smoothness

### Performance Optimizations (AudioMonitorService.swift)
- **SnoringDetector**: all FFT buffers pre-allocated in `init()` (zero per-frame malloc); Hann window pre-computed once; bin indices pre-computed
- **Sample rate**: requests `preferredSampleRate(16000)` — 64% less DSP data vs 44100 Hz
- **Buffer size**: `bufferSize: 2048` + `preferredIOBufferDuration(0.1)` → ~10 callbacks/sec; UI 流畅且后台不被 iOS 杀进程
- **FFT size**: 4096 — stride-based downsampling covers full buffer regardless of size (`stride = max(1, n / fftSize)`)
- **RMS computed once** per frame, passed into `score()` — no duplicate `vDSP_rmsqv` call
- **Session mode**: `.measurement` (optimized for capture apps vs `.default`)

### Background Audio
- `AVAudioSession` category: `.playAndRecord`, mode: `.measurement`, options: `.mixWithOthers`
- `UIBackgroundModes: audio` in Info.plist

### Data Persistence
- `SleepStore`: JSON-encoded `[SleepSession]` at `Documents/sleep_sessions.json` — survives recompiles
- Recordings: `Documents/snore_<timestamp>.m4a`
- `addSession()` inserts at index 0 → newest first in list

---

## ⚠️ 踩坑记录

### 1. 性能优化引入的 Bug

> 源于一次"优化 CPU/电量/内存"请求，前后花了大量来回才修复。

| 错误改动 | 后果 |
|----------|------|
| `bufferSize` 调大到 8192 | 16kHz 下每次回调 = 512ms 音频 → UI **仅 ~2Hz** 更新，电平环极度卡顿 |
| `preferredIOBufferDuration(0.2)` 配合大 bufferSize | 进一步降低回调率 |
| `bufferSize 1024 + IOBufferDuration 0.05` | 20Hz 回调，后台 CPU 压力过大 → **iOS 在夜间主动杀进程，数据丢失** |
| `fftSize` 4096 → 2048 | FFT 只分析缓冲区前 25%，呼噜大量漏检 |
| 加入 `stableFrames` 跳过 FFT | 呼噜刚开始时正好被跳过，造成漏检 |

**电平环卡顿排查走了 5 次弯路：**

1. 调 EMA 平滑系数 → 无效
2. 去掉 Combine `.receive(on: DispatchQueue.main)` → 无效
3. 加 30Hz `displayTimer` 插值 → 仍卡
4. 改用 SwiftUI spring 动画 → 仍卡
5. **找到根因**：bufferSize 太大，数据源本身只有 ~2Hz，动画参数怎么调都没用 ✅

**教训：**

1. **`bufferSize` 直接决定 UI 刷新率**，不是纯粹的性能参数。调大省 CPU，但电平环会卡，必须权衡。
2. **遇到视觉卡顿，先查数据源频率，再查动画参数**。数据源慢，动画再好也是无用功。
3. **`stableFrames` 类"跳过"优化风险极高**——边缘状态下（刚开始打呼噜）会漏检，不值得为边际省电引入。
4. **性能优化要分离三个维度**：检测精度（fftSize）/ UI 响应（bufferSize、IOBufferDuration）/ 电量（采样率、模式），三者独立评估，不能一刀切。
5. **后台进程存活与回调频率直接相关**：稳定值是 bufferSize 2048 + IOBufferDuration 0.1 = 10Hz，再快会被杀进程，再慢电平环卡顿。
6. **`AVAudioEngineConfigurationChange` 在正常运行中也会触发**，不能在其回调里做 `restartEngine()`——会重置 `lastIsLoud` 但不重置 `isSnoring`，导致状态机死锁，后续呼噜永远不再计数。每次加新通知处理前，必须先确认触发时机并走一遍完整状态流。

---

### 2. FFT 评分公式 Bug（导致呼噜识别不精准）

#### Bug A — `totalE` 包含 0–80 Hz 次低频噪声（漏报）
**文件**: `AudioMonitorService.swift` `score()` 函数

原代码：`let totalE = bandSum(1, highHi)` 从 bin 1（接近 0 Hz）起算，把空调嗡嗡声、路面振动等次低频噪声纳入分母，压低 `snoreE / totalE` → 呼噜得分偏低 → 漏报。

修复：`let totalE = bandSum(snoreLo, highHi)`，只统计 80 Hz 以上相关频段。

> **规则**：totalE 的起点必须与 snoreLo 对齐，分母不能包含检测频段之外的噪声能量。

#### Bug B — 高频惩罚项系统性压低打鼾得分（严重漏报）
**文件**: `AudioMonitorService.swift` `score()` 函数

原公式带高频惩罚项 `* max(0, 1 - highRatio * N)`。问题根源：**打鼾本身的泛音天然延伸到 1 kHz 以上**，惩罚项把真实打鼾的得分也一并压低。即使系数从 1.5 → 1.2 → 0.8 逐步放宽，仍然导致检测不灵敏——排查了很长时间。

最终修复：**彻底删除惩罚项**，score = `snoreE / totalE`（纯低频比值）。

> **规则**：**禁止重新引入高频惩罚项**。打鼾和语音/环境音的区分靠 `minimumRMS` 门控 + 频率比值阈值，而不是惩罚高频。惩罚项在任何系数下都会漏报泛音丰富的打鼾。

#### Bug C — `snoringScoreColor` 与 `snoringScore` 逻辑不一致（UI 误导）
**文件**: `SleepModels.swift`

`snoringScore` 取百分比和每小时频次两项的较差等级，但 `snoringScoreColor` 只看百分比，导致颜色显示绿色而文字标签却是"较差"。

修复：将 `pctLevel()` / `cphLevel()` 提为私有方法，两个属性共用同一逻辑。

> **规则**：`snoringScoreColor` 与 `snoringScore` 的等级逻辑必须保持一致，任何一处阈值改动要同步修改另一处。

---

## iOS Compatibility (iOS 15+)
All iOS 17/16-only APIs have been replaced:
- `AVAudioApplication` → `AVAudioSession` (iOS 15 compatible)
- `.onChange(of:) { _, _ in }` → single-param `{ _ in }` (iOS 17 two-param removed)
- `.scrollContentBackground(.hidden)` → `UITableView.appearance().backgroundColor = .clear`
- `.symbolEffect(.pulse)` → `opacity + scaleEffect` animation
- `.contentTransition(.numericText())` → removed

## Build Instructions
```bash
# Requires xcodegen
brew install xcodegen

# Regenerate Xcode project
cd SnoreTracker
xcodegen generate

open SnoreTracker.xcodeproj
```
Select your device → Cmd+R.

**If white screen after scheme edits:**
```bash
rm -rf SnoreTracker.xcodeproj/xcshareddata && xcodegen generate
```

**Bundle ID**: `com.eddiechan.snoretracker.ec2024` (Personal Team, 7-day provisioning)
- `com.eddiechan.snoretracker` 和 `com.eddiechan.snoretracker.dev` 均已被他人占用，无法注册

## Common Pitfalls
- `Color(hex:)` is defined in `HomeView.swift` — available globally across the module
- FFT uses nested `withUnsafeMutableBufferPointer` closures to stabilize `DSPSplitComplex` pointer — do not flatten to single-level
- `vDSP_sve` uses direct pointer offset (`buf.baseAddress! + lo`) — no Array copy per band
- Theme colors: always `themeManager.current.xxx`, never hardcoded
- `SleepStore` created once in `SnoreTrackerApp.init()`, passed to `SleepSessionManager`
- `UITableView.appearance().backgroundColor = .clear` set in `ReportsView.onAppear` for iOS 15 compat
- List swipe state resets on tab switch via `listID = UUID()` in `ReportsView.onAppear`
