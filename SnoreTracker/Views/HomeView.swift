import SwiftUI

struct HomeView: View {
    @EnvironmentObject var sessionManager: SleepSessionManager
    @State private var showPermissionAlert = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()

                // 根据权限 & 监测状态展示不同内容
                if !sessionManager.permissionGranted {
                    permissionView
                } else if sessionManager.isMonitoring {
                    monitoringView
                } else {
                    startingView
                }

                Spacer()
                bottomInfo
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            // 有权限就直接开始，没权限弹引导
            if !sessionManager.permissionGranted {
                sessionManager.requestPermissionAndStart { granted in
                    if !granted { showPermissionAlert = true }
                }
            }
        }
        .alert("需要麦克风权限", isPresented: $showPermissionAlert) {
            Button("去设置") {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在设置 → 隐私 → 麦克风 中允许 SnoreTracker 访问麦克风。")
        }
    }

    // MARK: - Background

    private var backgroundGradient: LinearGradient {
        sessionManager.isSnoring
            ? LinearGradient(colors: [Color(hex: "1A0D00"), Color(hex: "2A1500"), Color(hex: "1A0D00")],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(hex: "0A0F1E"), Color(hex: "111827"), Color(hex: "0A0F1E")],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("SnoreTracker")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(todayDateString)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
            // 常驻监测状态指示器
            if sessionManager.isMonitoring {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: "4CAF50"))
                        .frame(width: 7, height: 7)
                        .opacity(pulse ? 1 : 0.3)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1).repeatForever()) { pulse = true }
                        }
                    Text("后台监测中")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - 权限未授予

    private var permissionView: some View {
        VStack(spacing: 28) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.4))

            VStack(spacing: 10) {
                Text("需要麦克风权限")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("SnoreTracker 需要在后台持续监听\n麦克风以检测呼噜声")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Button {
                sessionManager.requestPermissionAndStart { granted in
                    if !granted { showPermissionAlert = true }
                }
            } label: {
                Label("授权并开始", systemImage: "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(LinearGradient(colors: [Color(hex: "3A6FD8"), Color(hex: "1A3FAA")],
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Color(hex: "3A6FD8").opacity(0.4), radius: 12, y: 6)
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - 启动中

    private var startingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            Text("正在启动监测...")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - 监测中主界面

    private var monitoringView: some View {
        VStack(spacing: 32) {

            // 主状态环
            ZStack {
                // 背景光晕
                Circle()
                    .fill(RadialGradient(
                        colors: sessionManager.isSnoring
                            ? [Color.orange.opacity(0.3), Color.clear]
                            : [Color(hex: "3A6FD8").opacity(0.12), Color.clear],
                        center: .center, startRadius: 60, endRadius: 140))
                    .frame(width: 280, height: 280)

                // 轨道
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 10)
                    .frame(width: 190, height: 190)

                // 动态弧
                Circle()
                    .trim(from: 0, to: CGFloat(min(sessionManager.currentLevel * 6, 1)))
                    .stroke(
                        sessionManager.isSnoring
                            ? LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color(hex: "6B9FFF"), Color(hex: "A8C8FF")], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 190, height: 190)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.15), value: sessionManager.currentLevel)

                // 中心图标
                VStack(spacing: 8) {
                    Image(systemName: sessionManager.isSnoring ? "waveform.badge.mic" : "moon.zzz.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            sessionManager.isSnoring
                                ? LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [Color(hex: "A8C8FF"), Color(hex: "6B9FFF")], startPoint: .top, endPoint: .bottom))
                        .symbolEffect(.pulse, isActive: sessionManager.isSnoring)

                    Text(sessionManager.isSnoring ? "正在录音..." : "静默监测中")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(sessionManager.isSnoring ? 0.9 : 0.5))
                }
            }

            // 波形
            LiveWaveform(level: sessionManager.currentLevel, isSnoring: sessionManager.isSnoring)
                .frame(height: 40)
                .padding(.horizontal, 40)

            // 今晚统计卡
            nightStatsCard
        }
    }

    // MARK: - 今晚统计

    private var nightStatsCard: some View {
        HStack(spacing: 0) {
            nightStat(
                icon: "waveform.badge.mic",
                value: "\(sessionManager.snoringCount)",
                label: "次呼噜",
                color: .orange
            )
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1, height: 40)
            nightStat(
                icon: "clock.fill",
                value: sessionManager.isSnoring
                    ? formatSeconds(sessionManager.liveSnoreDuration)   // 实时计数
                    : formatSeconds(sessionManager.totalSnoringSeconds), // 累计
                label: sessionManager.isSnoring ? "正在呼噜" : "呼噜时长",
                color: sessionManager.isSnoring ? .orange : Color(hex: "6B9FFF")
            )
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1, height: 40)
            nightStat(
                icon: "moon.fill",
                value: sessionDuration,
                label: "监测时长",
                color: Color(hex: "A8C8FF")
            )
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 24)
    }

    private func nightStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.4), value: sessionManager.snoringCount)
    }

    // MARK: - 底部提示

    private var bottomInfo: some View {
        VStack(spacing: 6) {
            if sessionManager.isMonitoring {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                    Text("锁屏后仍在后台监测 · 检测到呼噜自动录音 · 5秒无声停止")
                        .font(.system(size: 11))
                }
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Helpers

    private var todayDateString: String {
        Date().formatted(.dateTime.month().day().weekday())
    }

    private var sessionDuration: String {
        guard let s = sessionManager.todaySession else { return "0m" }
        let t = Int(Date().timeIntervalSince(s.startTime))
        let h = t / 3600
        let m = (t % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }

    private func formatSeconds(_ s: Double) -> String {
        let t = Int(s)
        let m = t / 60; let sec = t % 60
        if m > 0 { return "\(m)m\(sec)s" }
        return "\(sec)s"
    }
}

// MARK: - Live Waveform

struct LiveWaveform: View {
    let level: Float
    let isSnoring: Bool
    private let count = 30

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSnoring ? Color.orange.opacity(0.8) : Color(hex: "6B9FFF").opacity(0.7))
                    .frame(width: 3, height: barHeight(i))
                    .animation(.easeInOut(duration: 0.1), value: level)
            }
        }
    }

    private func barHeight(_ i: Int) -> CGFloat {
        guard level > 0.01 else { return 4 }
        let noise = abs(sin(Float(i) * 0.8 + level * 12))
        return max(4, CGFloat(level * noise) * 38)
    }
}

// MARK: - Hex Color

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
