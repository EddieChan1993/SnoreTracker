# SnoreTracker

[中文](#中文) · [English](#english)

---

## 中文

> 手动开启后台监测，自动检测呼噜声，帮你了解每晚睡眠质量。

![Platform](https://img.shields.io/badge/platform-iOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

### 功能特性

- **手动开启/关闭监测** — 每次开启创建一条独立报告，按监测时间段区分
- **FFT 频率分析检测** — 基于 80–500 Hz 低频能量占比，精准区分呼噜声与口哨、说话声
- **自动录音** — 检测到呼噜立即录音，静音超过设定秒数自动停止
- **实时仪表盘** — 状态环动态指示音量、实时呼噜计时、今晚统计
- **睡眠报告** — 每段监测独立存档，含评分、呼噜次数、累计时长、时间线
- **双指标评分** — 综合呼噜时间占比 + 每小时频次（参考医学 AHI 标准），取较差值
- **录音回放** — 在详情页点击播放，回听每次呼噜录音
- **主题切换** — 深色 / 水果果冻两套主题，设置页一键切换
- **隐私优先** — 所有录音和数据仅保存在本地设备，不上传任何服务器

### 技术栈

| 技术 | 用途 |
|------|------|
| SwiftUI | 全部 UI（iOS 15 兼容） |
| AVAudioEngine | 后台麦克风采集 |
| Accelerate / vDSP | 2048 点 FFT 频率分析（硬件加速） |
| AVAudioFile | 实时录音写文件 |
| Combine | 状态响应 |
| AVAudioSession | 低采样率请求（16 kHz）+ 测量模式省电 |

### 构建方法

**前置要求**：Xcode 15+、iOS 15+ 真机、[xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
git clone https://github.com/EddieChan1993/SnoreTracker.git
cd SnoreTracker
xcodegen generate
open SnoreTracker.xcodeproj
```

在 Xcode 中选择 Team 和真机，**Cmd+R** 运行。首次运行需在手机信任开发者证书（设置 → 通用 → VPN 与设备管理）。

> Personal Team 签名有效期 7 天，到期后需重新编译安装。

### 检测原理

1. `AVAudioEngine` 安装 tap，请求 16 kHz 采样率、200ms 缓冲（~5 次/秒唤醒）
2. 计算 RMS 振幅；低于阈值直接跳过；连续静音 8+ 帧完全跳过 FFT
3. 对音频帧做 **2048 点实数 FFT**（Hann 窗加权）
4. 综合得分 = `snoreRatio × max(0, 1 − highRatio × 1.5)`
5. 持续超过阈值 1 秒后确认为呼噜，开始录音

### 评分标准

| 等级 | 每小时次数 | 时间占比 |
|------|-----------|---------|
| 优秀 | < 5 次/h | < 5% |
| 良好 | < 15 次/h | < 15% |
| 一般 | < 30 次/h | < 30% |
| 较差 | ≥ 30 次/h | ≥ 30% |

两项各自评级，取较差的一项为最终评分。

---

## English

> Manually trigger background monitoring to detect snoring and understand your nightly sleep quality.

![Platform](https://img.shields.io/badge/platform-iOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

### Features

- **Manual start / stop** — each session creates an independent report timestamped to that monitoring period
- **FFT-based detection** — analyzes 80–500 Hz low-frequency energy to distinguish snoring from whistling or speech
- **Auto recording** — starts recording when snoring is detected; stops after a configurable silence delay
- **Live dashboard** — animated level ring, real-time snoring timer, tonight's stats
- **Sleep reports** — each session stored separately with score, event count, total duration, and timeline
- **Dual-metric scoring** — combines snoring-time percentage and events-per-hour (ref: medical AHI); worst grade wins
- **Recording playback** — tap any event in the detail view to replay the audio
- **Theme switching** — Dark and Fruit Jelly themes, switchable in Settings
- **Privacy first** — all recordings and data stored locally on-device only; nothing uploaded

### Tech Stack

| Technology | Purpose |
|------------|---------|
| SwiftUI | All UI (iOS 15 compatible) |
| AVAudioEngine | Background microphone capture |
| Accelerate / vDSP | 2048-point FFT analysis (hardware accelerated) |
| AVAudioFile | Real-time audio file writing |
| Combine | Reactive state |
| AVAudioSession | 16 kHz preferred sample rate + measurement mode |

### Build

**Requirements**: Xcode 15+, iOS 15+ device (simulator has no mic), [xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
git clone https://github.com/EddieChan1993/SnoreTracker.git
cd SnoreTracker
xcodegen generate
open SnoreTracker.xcodeproj
```

Select your Team and device in Xcode, then press **Cmd+R**. On first install, trust the developer certificate on device (Settings → General → VPN & Device Management).

> Personal Team provisioning profiles expire after 7 days and require a re-install.

### How Detection Works

1. `AVAudioEngine` tap requests 16 kHz sample rate and 200ms IO buffer (~5 wake-ups/sec)
2. RMS amplitude gate — frames below threshold are skipped; 8+ consecutive quiet frames skip FFT entirely
3. **2048-point real FFT** with Hann window (Accelerate vDSP, hardware accelerated)
4. Score = `snoreRatio × max(0, 1 − highRatio × 1.5)`
5. Score above threshold for 1 s confirms snoring → recording begins

### Scoring

| Grade | Events / hour | Time percentage |
|-------|--------------|-----------------|
| Excellent | < 5 /h | < 5% |
| Good | < 15 /h | < 15% |
| Fair | < 30 /h | < 30% |
| Poor | ≥ 30 /h | ≥ 30% |

Both metrics are graded independently; the worse grade is the final score.

### Permissions

| Permission | Purpose |
|------------|---------|
| Microphone | Detect and record snoring |
| Background Audio | Continue monitoring when screen is locked (`UIBackgroundModes: audio`) |

## License

MIT
