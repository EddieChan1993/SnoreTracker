# SnoreTracker

> 手动开启后台监测，自动检测呼噜声，帮你了解每晚睡眠质量。

![Platform](https://img.shields.io/badge/platform-iOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## 功能特性

- **手动开启/关闭监测** — 每次开启创建一条独立报告，按监测时间段区分
- **FFT 频率分析检测** — 基于 80–500 Hz 低频能量占比，精准区分呼噜声与口哨、说话声
- **自动录音** — 检测到呼噜立即录音，静音超过设定秒数自动停止
- **实时仪表盘** — 状态环动态指示音量、实时呼噜计时、今晚统计
- **睡眠报告** — 每段监测独立存档，含评分、呼噜次数、累计时长、时间线
- **双指标评分** — 综合呼噜时间占比 + 每小时频次（参考医学 AHI 标准），取较差值
- **录音回放** — 在详情页点击播放，回听每次呼噜录音
- **主题切换** — 深色 / 水果果冻两套主题，设置页一键切换
- **隐私优先** — 所有录音和数据仅保存在本地设备，不上传任何服务器

## 技术栈

| 技术 | 用途 |
|------|------|
| SwiftUI | 全部 UI（iOS 15 兼容） |
| AVAudioEngine | 后台麦克风采集 |
| Accelerate / vDSP | 2048 点 FFT 频率分析（硬件加速） |
| AVAudioFile | 实时录音写文件 |
| Combine | 状态响应 |
| AVAudioSession | 低采样率请求（16 kHz）+ 测量模式省电 |

## 构建方法

### 前置要求

- Xcode 15+
- iOS 15+ 真机（模拟器无麦克风）
- [xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
```

### 步骤

```bash
git clone https://github.com/EddieChan1993/SnoreTracker.git
cd SnoreTracker
xcodegen generate
open SnoreTracker.xcodeproj
```

在 Xcode 中：
1. Signing & Capabilities → 选择你自己的 Team
2. 选择真机设备 → **Cmd+R** 运行
3. 首次运行需在手机信任开发者证书（设置 → 通用 → VPN 与设备管理）

> **注意**：Personal Team 签名有效期 7 天，到期后需重新编译安装。

## 项目结构

```
SnoreTracker/
├── project.yml                         # xcodegen 配置（deploymentTarget: 15.0）
├── CLAUDE.md                           # AI 辅助开发详细说明
└── SnoreTracker/
    ├── Models/
    │   └── SleepModels.swift           # SnoringEvent, SleepSession（含双指标评分）
    ├── Services/
    │   ├── AudioMonitorService.swift   # 音频采集 + FFT 检测 + 录音 + 性能优化
    │   ├── SleepSessionManager.swift   # 状态管理、Session 生命周期、孤儿恢复
    │   └── SleepStore.swift            # JSON 持久化
    ├── Theme/
    │   ├── AppTheme.swift              # 主题色彩 token
    │   └── ThemeManager.swift          # 主题持久化（@AppStorage）
    └── Views/
        ├── ContentView.swift           # TabView 根视图
        ├── HomeView.swift              # 监测主界面（手动开启/停止）
        ├── ReportsView.swift           # 睡眠报告列表
        ├── SessionDetailView.swift     # 详情 + 水平时间线 + 录音回放
        └── SettingsView.swift          # 灵敏度调节 + 主题切换
```

## 检测原理

1. `AVAudioEngine` 安装 tap，请求 16 kHz 采样率、200ms 缓冲（~5 次/秒唤醒）
2. 计算 RMS 振幅；低于阈值（默认 0.02）直接跳过；连续静音 8+ 帧则完全跳过 FFT
3. 对音频帧做 **2048 点实数 FFT**（Hann 窗加权，Accelerate 硬件加速）
4. 计算 80–500 Hz 能量占比（snoreRatio）
5. 计算 1000–6000 Hz 高频惩罚项（highRatio）
6. 综合得分 = `snoreRatio × max(0, 1 − highRatio × 1.5)`
7. 持续超过阈值（默认 0.40）1 秒后，确认为呼噜并开始录音

## 评分标准

| 等级 | 每小时呼噜次数 | 时间占比 |
|------|--------------|---------|
| 优秀 | < 5 次/h | < 5% |
| 良好 | < 15 次/h | < 15% |
| 一般 | < 30 次/h | < 30% |
| 较差 | ≥ 30 次/h | ≥ 30% |

两项指标各自评级，取较差的一项作为最终评分。

## 权限说明

| 权限 | 用途 |
|------|------|
| 麦克风 | 检测和录制呼噜声 |
| 后台音频 | 锁屏后继续监测（UIBackgroundModes: audio） |

## License

MIT
