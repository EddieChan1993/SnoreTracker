import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sessionManager: SleepSessionManager
    @EnvironmentObject var store: SleepStore

    @AppStorage("minimumRMS") private var minimumRMS: Double = 0.02
    @AppStorage("snoreScoreThreshold") private var snoreScore: Double = 0.40
    @AppStorage("confirmDelay") private var confirmDelay: Double = 1.0
    @AppStorage("silenceDelay") private var silenceDelay: Double = 5.0
    @State private var showClearConfirm = false

    var body: some View {
        ZStack {
            Color(hex: "0A0F1E").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("设置")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // Detection settings
                    settingCard(title: "检测灵敏度", icon: "ear.fill") {
                        VStack(spacing: 16) {
                            sliderRow(
                                label: "音量灵敏度",
                                value: $minimumRMS,
                                range: 0.01...0.10,
                                leftLabel: "高",
                                rightLabel: "低",
                                display: sensitivityLabel,
                                hint: "手机离头部越远，调越高（默认：中）"
                            ) { sessionManager.audioService.minimumRMS = Float(minimumRMS) }

                            Divider().background(Color.white.opacity(0.1))

                            sliderRow(
                                label: "频率匹配度",
                                value: $snoreScore,
                                range: 0.20...0.70,
                                leftLabel: "宽松",
                                rightLabel: "严格",
                                display: String(format: "%.0f%%", snoreScore * 100),
                                hint: "越严格越不容易误触发，但可能漏检"
                            ) { sessionManager.audioService.snoreScoreThreshold = Float(snoreScore) }

                            Divider().background(Color.white.opacity(0.1))

                            sliderRow(
                                label: "确认延迟",
                                value: $confirmDelay,
                                range: 0.3...3.0,
                                leftLabel: "快",
                                rightLabel: "慢",
                                display: String(format: "%.1fs", confirmDelay),
                                hint: "持续多少秒才算一次呼噜"
                            ) { sessionManager.audioService.confirmDelay = confirmDelay }

                            Divider().background(Color.white.opacity(0.1))

                            sliderRow(
                                label: "停止延迟",
                                value: $silenceDelay,
                                range: 2.0...15.0,
                                leftLabel: "短",
                                rightLabel: "长",
                                display: String(format: "%.0fs", silenceDelay),
                                hint: "安静多少秒后停止录音"
                            ) { sessionManager.audioService.silenceDelay = silenceDelay }
                        }
                    }

                    // Data
                    settingCard(title: "数据管理", icon: "internaldrive.fill") {
                        VStack(spacing: 12) {
                            dataRow(label: "已保存录音", value: "\(totalRecordingCount) 个")
                            Divider().background(Color.white.opacity(0.1))
                            dataRow(label: "存储占用", value: totalStorageSize)
                            Divider().background(Color.white.opacity(0.1))
                            Button {
                                showClearConfirm = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash.fill").foregroundColor(.red)
                                    Text("清除所有数据").foregroundColor(.red)
                                    Spacer()
                                }
                                .font(.system(size: 15))
                            }
                        }
                    }

                    // About
                    settingCard(title: "关于", icon: "info.circle.fill") {
                        VStack(spacing: 12) {
                            dataRow(label: "版本", value: "1.0.0")
                            Divider().background(Color.white.opacity(0.1))
                            dataRow(label: "检测算法", value: "RMS 振幅分析")
                            Divider().background(Color.white.opacity(0.1))
                            HStack {
                                Text("录音仅保存本地，不上传任何服务器")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.35))
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .confirmationDialog("确认清除", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除所有数据", role: .destructive) {
                sessionManager.clearAllData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有睡眠记录和录音文件，不可恢复")
        }
    }

    // MARK: - Components

    private func settingCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "6B9FFF"))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
            }
            content()
        }
        .padding(18)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>,
                           leftLabel: String, rightLabel: String, display: String,
                           hint: String = "", onChange: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.system(size: 15)).foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(display).font(.system(size: 14, weight: .semibold)).foregroundColor(Color(hex: "6B9FFF"))
            }
            HStack(spacing: 8) {
                Text(leftLabel).font(.system(size: 11)).foregroundColor(.white.opacity(0.35))
                Slider(value: value, in: range)
                    .tint(Color(hex: "6B9FFF"))
                    .onChange(of: value.wrappedValue) { _, _ in onChange() }
                Text(rightLabel).font(.system(size: 11)).foregroundColor(.white.opacity(0.35))
            }
            if !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    private func dataRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value).font(.system(size: 15)).foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - Computed

    private var sensitivityLabel: String {
        switch minimumRMS {
        case 0..<0.025: return "极高"
        case 0.025..<0.04: return "高"
        case 0.04..<0.06: return "中"
        case 0.06..<0.08: return "低"
        default: return "极低"
        }
    }

    private var totalRecordingCount: Int {
        store.sessions.reduce(0) { $0 + $1.snoringEvents.count }
    }

    private var totalStorageSize: String {
        var total: Int64 = 0
        store.sessions.flatMap { $0.snoringEvents }.compactMap { $0.recordingURL }.forEach { url in
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 { total += size }
        }
        let mb = Double(total) / 1_048_576
        return mb < 1 ? String(format: "%.0f KB", mb * 1024) : String(format: "%.1f MB", mb)
    }
}
