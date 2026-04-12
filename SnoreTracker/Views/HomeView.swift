import SwiftUI

struct HomeView: View {
    @EnvironmentObject var sessionManager: SleepSessionManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showPermissionAlert = false
    @State private var pulse = false
    // 直接读 AppStorage，启动时即显示正确值，设置页修改后自动更新
    @AppStorage("silenceDelay") private var silenceDelay: Double = 5.0

    private var theme: AppTheme { themeManager.current }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()

                if !sessionManager.permissionGranted {
                    permissionView
                } else if sessionManager.isMonitoring {
                    monitoringView
                } else {
                    stoppedView
                }

                Spacer()
                bottomInfo
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
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
            ? LinearGradient(colors: theme.bgSnoringColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: theme.bgColors,        startPoint: .topLeading, endPoint: .bottomTrailing)
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
            if sessionManager.isMonitoring {
                HStack(spacing: 5) {
                    Circle()
                        .fill(theme.liveIndicator)
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
                    .background(
                        LinearGradient(colors: [theme.accent, theme.accent.opacity(0.6)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: theme.accent.opacity(0.4), radius: 12, y: 6)
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - 已暂停（有权限但未监测）

    private var stoppedView: some View {
        VStack(spacing: 28) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(colors: [theme.accentLight.opacity(0.5), theme.accent.opacity(0.3)],
                                   startPoint: .top, endPoint: .bottom))

            VStack(spacing: 8) {
                Text("监测已暂停")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Text("开启后将在后台自动检测呼噜声")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
            }

            Button {
                sessionManager.toggleMonitoring()
            } label: {
                Label("开始监测", systemImage: "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(colors: [theme.accent, theme.accent.opacity(0.7)],
                                       startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: theme.accent.opacity(0.4), radius: 12, y: 6)
            }
            .padding(.horizontal, 32)
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
                            ? [theme.snoringAccent.opacity(0.3), Color.clear]
                            : [theme.accent.opacity(0.12), Color.clear],
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
                            ? LinearGradient(colors: [theme.snoringAccent, theme.snoringAccent.opacity(0.6)],
                                             startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [theme.accent, theme.accentLight],
                                             startPoint: .leading, endPoint: .trailing),
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
                                ? LinearGradient(colors: [theme.snoringAccent, theme.snoringAccent.opacity(0.7)],
                                                 startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [theme.accentLight, theme.accent],
                                                 startPoint: .top, endPoint: .bottom))
                        .symbolEffect(.pulse, isActive: sessionManager.isSnoring)

                    Text(sessionManager.isSnoring ? "正在录音..." : "静默监测中")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(sessionManager.isSnoring ? 0.9 : 0.5))
                }
            }

            // 波形
            LiveWaveform(level: sessionManager.currentLevel,
                         isSnoring: sessionManager.isSnoring,
                         accent: theme.accent,
                         snoringAccent: theme.snoringAccent)
                .frame(height: 40)
                .padding(.horizontal, 40)

            // 今晚统计卡
            nightStatsCard

            // 暂停监测按钮
            Button {
                sessionManager.toggleMonitoring()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 15))
                    Text("暂停监测")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - 今晚统计

    private var nightStatsCard: some View {
        HStack(spacing: 0) {
            nightStat(icon: "waveform.badge.mic",
                      value: "\(sessionManager.snoringCount)",
                      label: "次呼噜",
                      color: theme.snoringAccent)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 40)
            nightStat(icon: "clock.fill",
                      value: sessionManager.isSnoring
                          ? formatSeconds(sessionManager.liveSnoreDuration)
                          : formatSeconds(sessionManager.totalSnoringSeconds),
                      label: sessionManager.isSnoring ? "正在呼噜" : "呼噜时长",
                      color: sessionManager.isSnoring ? theme.snoringAccent : theme.accent)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 40)
            nightStat(icon: "moon.fill",
                      value: sessionDuration,
                      label: "监测时长",
                      color: theme.accentLight)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(theme.cardOpacity))
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

    // MARK: - 底部提示（5s 动态读取）

    private var bottomInfo: some View {
        VStack(spacing: 6) {
            if sessionManager.isMonitoring {
                let silenceSec = Int(silenceDelay)
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 12))
                    Text("锁屏后仍在后台监测 · 检测到呼噜自动录音 · \(silenceSec)秒无声停止")
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
        let h = t / 3600; let m = (t % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }

    private func formatSeconds(_ s: Double) -> String {
        let t = Int(s); let m = t / 60; let sec = t % 60
        if m > 0 { return "\(m)m\(sec)s" }
        return "\(sec)s"
    }
}

// MARK: - Live Waveform

struct LiveWaveform: View {
    let level: Float
    let isSnoring: Bool
    let accent: Color
    let snoringAccent: Color
    private let count = 30

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSnoring ? snoringAccent.opacity(0.8) : accent.opacity(0.7))
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
