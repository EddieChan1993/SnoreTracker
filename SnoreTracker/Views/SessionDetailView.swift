import SwiftUI
import AVFoundation

struct SessionDetailView: View {
    let session: SleepSession
    @EnvironmentObject var store: SleepStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color(hex: "0A0F1E").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text(session.startTime.formatted(.dateTime.month().day().weekday()))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text(timeRange)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    // Balance
                    Color.clear.frame(width: 28, height: 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard
                        timelineCard
                        if !session.snoringEvents.isEmpty {
                            recordingsCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(spacing: 18) {
            // Score
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("睡眠评分")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(session.snoringScore)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor)
                    }
                }
                Spacer()
                // Donut-style percentage
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(session.snoringPercentage / 100))
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(String(format: "%.0f%%", session.snoringPercentage))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 64, height: 64)
            }

            Divider().background(Color.white.opacity(0.1))

            HStack(spacing: 0) {
                summaryItem("moon.fill", value: formatDuration(session.duration), label: "睡眠时长", color: Color(hex: "6B9FFF"))
                summaryItem("waveform.badge.mic", value: "\(session.snoringEvents.count)", label: "呼噜次数", color: .orange)
                summaryItem("clock.fill", value: formatDuration(session.totalSnoringTime), label: "呼噜时长", color: Color(hex: "A8C8FF"))
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func summaryItem(_ icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Timeline

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundColor(Color(hex: "6B9FFF"))
                    .font(.system(size: 14))
                Text("呼噜时间线")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
            }

            if session.snoringEvents.isEmpty {
                HStack {
                    Spacer()
                    Text("本次睡眠未检测到呼噜 🎉")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.45))
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                SnoringBarChart(session: session)
                    .frame(height: 130)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Recordings

    private var recordingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "mic.circle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text("呼噜录音")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
            }

            VStack(spacing: 10) {
                ForEach(Array(session.snoringEvents.reversed().enumerated()), id: \.element.id) { idx, event in
                    SnoringEventRow(event: event, index: session.snoringEvents.count - idx)
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Helpers

    private var scoreColor: Color {
        switch session.snoringScore {
        case "优秀": return .green
        case "良好": return Color(hex: "6B9FFF")
        case "一般": return .orange
        default:     return .red
        }
    }

    private var timeRange: String {
        let s = session.startTime.formatted(date: .omitted, time: .shortened)
        if let e = session.endTime {
            return "\(s) – \(e.formatted(date: .omitted, time: .shortened))"
        }
        return "开始于 \(s)"
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = (Int(t) % 3600) / 60
        if t < 60 { return "\(Int(t))秒" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)分钟"
    }
}

// MARK: - Snoring Bar Chart

struct SnoringBarChart: View {
    let session: SleepSession

    private var events: [SnoringEvent] { session.snoringEvents }

    // 最长呼噜时长（柱高归一化）
    private var maxSnoreDuration: TimeInterval {
        events.map { $0.duration }.max() ?? 1
    }

    // ── X 轴范围：只聚焦事件区间，与 session 时长无关 ──
    // 第一个事件开始时间
    private var firstEventTime: Date {
        events.first?.startTime ?? session.startTime
    }
    // 最后一个事件结束时间（或开始 + 10s 估算）
    private var lastEventEndTime: Date {
        guard let last = events.last else { return session.endTime ?? Date() }
        return last.endTime ?? last.startTime.addingTimeInterval(10)
    }
    // 事件跨度（第一个开始 → 最后一个结束）
    private var eventsSpan: TimeInterval {
        max(5, lastEventEndTime.timeIntervalSince(firstEventTime))
    }
    // X 轴起点：第一个事件前留 20% 或至少 10s
    private var axisStart: Date {
        let pad = max(10, eventsSpan * 0.20)
        return firstEventTime.addingTimeInterval(-pad)
    }
    // X 轴终点：最后一个事件后留 20% 或至少 10s（不受 session.endTime 限制）
    private var axisEnd: Date {
        let pad = max(10, eventsSpan * 0.20)
        return lastEventEndTime.addingTimeInterval(pad)
    }
    private var axisDuration: TimeInterval { max(1, axisEnd.timeIntervalSince(axisStart)) }

    // X 轴时间格式：跨度 < 5 分钟显示秒，否则只显示时:分
    private var timeFormat: Date.FormatStyle {
        axisDuration < 300
            ? .dateTime.hour().minute().second()
            : .dateTime.hour().minute()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Y 轴标注
            HStack {
                Text("持续时长 ↑")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                HStack(spacing: 3) {
                    Text("最长")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                    Text("\(Int(maxSnoreDuration))秒")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange.opacity(0.7))
                }
            }

            // Canvas 柱状图
            GeometryReader { geo in
                let w    = geo.size.width
                let h    = geo.size.height
                // 柱宽自适应：事件越多越细，但不超 30pt / 不低于 8pt
                let rawW = events.count > 0 ? w / CGFloat(events.count) * 0.50 : w
                let barW = min(max(rawW, 8), 30)
                // 计算防重叠位置
                let xs   = adjustedXPositions(width: w, barW: barW)

                Canvas { context, size in
                    // 参考横线
                    for ratio in [0.25, 0.5, 0.75, 1.0] as [CGFloat] {
                        var p = Path()
                        let y = size.height * (1 - ratio)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p,
                            with: .color(.white.opacity(ratio == 1 ? 0.18 : 0.05)),
                            lineWidth: 1)
                    }

                    // 柱子（使用防重叠位置）
                    for (i, event) in events.enumerated() {
                        guard i < xs.count else { continue }
                        let x      = xs[i]
                        let hRatio = CGFloat(event.duration / maxSnoreDuration)
                        let barH   = max(6, hRatio * (size.height - 2))
                        let y      = size.height - barH
                        let rect   = CGRect(x: x, y: y, width: barW, height: barH)
                        let path   = Path(roundedRect: rect, cornerRadius: min(barW / 2, 5))
                        context.fill(path,
                            with: .color(Color.orange.opacity(0.45 + 0.55 * Double(hRatio))))
                    }
                }
                .frame(width: w, height: h)
            }
            .frame(height: 88)

            // X 轴标签
            HStack(alignment: .top) {
                Text(axisStart.formatted(timeFormat))
                Spacer()
                if let mid = midLabel {
                    Text(mid.formatted(timeFormat))
                    Spacer()
                }
                Text(axisEnd.formatted(timeFormat))
            }
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.28))
        }
    }

    // ── 防重叠位置算法 ──
    // 1. 按比例计算自然位置
    // 2. 前向推：若与前柱重叠则向右推开
    // 3. 后向拉：若最后一柱超出右边界则从右往左拉回
    private func adjustedXPositions(width: CGFloat, barW: CGFloat) -> [CGFloat] {
        guard !events.isEmpty else { return [] }
        let minStep = barW + 4   // 相邻柱起点最小距离

        // 自然位置（柱心对齐时间点）
        var xs = events.map { event in
            CGFloat(event.startTime.timeIntervalSince(axisStart) / axisDuration) * width - barW / 2
        }

        // 前向推开（保证不重叠）
        for i in 1..<xs.count {
            if xs[i] < xs[i-1] + minStep {
                xs[i] = xs[i-1] + minStep
            }
        }

        // 后向回拉（最后一柱不超出右边界）
        let maxX = width - barW
        if xs[xs.count - 1] > maxX {
            xs[xs.count - 1] = maxX
            for i in stride(from: xs.count - 2, through: 0, by: -1) {
                let allowed = xs[i + 1] - minStep
                if xs[i] > allowed { xs[i] = allowed }
            }
        }

        // 第一柱不超出左边界
        return xs.map { max(0, $0) }
    }

    private var midLabel: Date? {
        guard axisDuration > 60 else { return nil }
        return Date(timeIntervalSince1970: axisStart.timeIntervalSince1970 + axisDuration / 2)
    }
}

// MARK: - Snoring Event Row

struct SnoringEventRow: View {
    let event: SnoringEvent
    let index: Int

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 12) {
            // Index badge
            Text("#\(index)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.orange.opacity(0.7))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                // 时长高亮，时间灰度
                Text(formatDuration(event.duration))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                if isPlaying || progress > 0 {
                    ProgressView(value: progress)
                        .tint(.orange)
                        .frame(width: 120)
                        .transition(.opacity)
                } else {
                    Text(event.startTime.formatted(
                            .dateTime.hour().minute().second()
                        ))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Spacer()

            Button { toggle() } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .red.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    )
            }
            .buttonStyle(.plain)
            .disabled(event.recordingURL == nil)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onDisappear { stop() }
    }

    private func toggle() { isPlaying ? stop() : play() }

    private func play() {
        guard let url = event.recordingURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let p = player else { return }
            progress = p.currentTime / max(p.duration, 0.01)
            if !p.isPlaying { stop() }
        }
    }

    private func stop() {
        player?.stop(); player = nil
        timer?.invalidate(); timer = nil
        isPlaying = false; progress = 0
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        return m > 0 ? "\(m)分\(s)秒" : "\(s)秒"
    }
}
