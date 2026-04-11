# SnoreTracker

> 自动监测你的呼噜声，帮助你了解睡眠质量。

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## 功能特性

- **全自动后台监测** — 无需手动启动，App 打开后持续在后台静默监听
- **FFT 频率分析检测** — 基于 80–500 Hz 低频能量占比，精准区分呼噜声与口哨、说话声
- **自动录音** — 检测到呼噜立即录音，5 秒无声自动停止
- **实时仪表盘** — 动态波形、状态环、实时呼噜计时
- **睡眠报告** — 每晚睡眠评分、呼噜次数、累计时长、柱状时间线
- **录音回放** — 在报告页点击播放，回听每次呼噜录音
- **隐私优先** — 所有录音和数据仅保存在本地设备，不上传任何服务器

## 截图

| 监测中 | 睡眠报告 | 详情页 |
|--------|----------|--------|
| 动态波形 + 状态环 | 历史记录列表 | 时间线 + 录音回放 |

## 技术栈

| 技术 | 用途 |
|------|------|
| SwiftUI | 全部 UI |
| AVAudioEngine | 后台麦克风采集 |
| Accelerate / vDSP | FFT 频率分析（硬件加速） |
| AVAudioFile | 实时录音写文件 |
| Combine | 状态响应 |

## 构建方法

### 前置要求

- Xcode 15+
- iOS 17+ 设备（模拟器无麦克风）
- [xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
```

### 步骤

```bash
git clone https://github.com/<your-username>/SnoreTracker.git
cd SnoreTracker
xcodegen generate
open SnoreTracker.xcodeproj
```

在 Xcode 中选择你的真机设备，按 **Cmd+R** 运行。

> **注意**：首次运行需要在手机上信任开发者证书（设置 → 通用 → VPN 与设备管理）。

## 项目结构

```
SnoreTracker/
├── project.yml                    # xcodegen 配置
├── CLAUDE.md                      # AI 辅助开发说明
└── SnoreTracker/
    ├── Models/
    │   └── SleepModels.swift      # 数据模型（SnoringEvent, SleepSession）
    ├── Services/
    │   ├── AudioMonitorService.swift   # 音频采集 + FFT 检测 + 录音
    │   └── SleepSessionManager.swift  # 状态管理桥接层
    └── Views/
        ├── HomeView.swift         # 主监测界面
        ├── ReportsView.swift      # 睡眠报告列表
        ├── SessionDetailView.swift # 详情 + 时间线 + 录音
        └── SettingsView.swift     # 灵敏度设置
```

## 检测原理

1. `AVAudioEngine` 安装 tap，每 ~93ms 获取一帧音频（4096 samples）
2. 计算 RMS 振幅，低于阈值（默认 0.02）直接跳过
3. 对音频帧做 **4096 点实数 FFT**（Hann 窗加权）
4. 计算 80–500 Hz 能量占总能量比值（snoreRatio）
5. 计算 1000–6000 Hz 高频惩罚项（highRatio）
6. 综合得分 = `snoreRatio × max(0, 1 − highRatio × 1.5)`
7. 持续超过阈值（默认 0.40）1 秒后，确认为呼噜并开始录音

## 权限说明

| 权限 | 用途 |
|------|------|
| 麦克风 | 检测和录制呼噜声 |
| 后台音频 | 锁屏后继续监测（UIBackgroundModes: audio） |

## License

MIT
