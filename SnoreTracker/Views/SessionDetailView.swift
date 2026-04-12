import SwiftUI
import AVFoundation

struct SessionDetailView: View {
    let session: SleepSession
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    private var theme: AppTheme { themeManager.current }

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.bgColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

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
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        Text(timeRange)
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Color.clear.frame(width: 28, height: 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard
                        timelineCard
                        if !session.snoringEvents.isEmpty { recordingsCard }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("睡眠评分")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                    Text(session.snoringScore)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(session.snoringPercentage / 100))
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(String(format: "%.0f%%", session.snoringPercentage))
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                }
                .frame(width: 64, height: 64)
            }

            Divider().background(Color.white.opacity(0.1))

            HStack(spacing: 0) {
                summaryItem("moon.fill",           value: formatDuration(session.duration),         label: "睡眠时长", color: theme.accent)
                summaryItem("waveform.badge.mic",  value: "\(session.snoringEvents.count)",         label: "呼噜次数", color: theme.snoringAccent)
                summaryItem("clock.fill",          value: formatDuration(session.totalSnoringTime), label: "呼噜时长", color: theme.accentLight)
            }
        }
        .padding(20)
        .background(Color.white.opacity(theme.cardOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func summaryItem(_ icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text(label).font(.system(size: 11)).foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Timeline Card

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundColor(theme.accent).font(.system(size: 14))
                Text("呼噜时间线")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
            }

            if session.snoringEvents.isEmpty {
                HStack {
                    Spacer()
                    Text("本次睡眠未检测到呼噜 🎉")
                        .font(.system(size: 14)).foregroundColor(.white.opacity(0.45))
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                // ── 新横向时间轴 ──
                SnoringTimeline(session: session, theme: theme)
                // ── 旧竖向柱状图（保留注释，勿删）──
                // SnoringBarChart(session: session, theme: theme).frame(height: 130)
            }
        }
        .padding(20)
        .background(Color.white.opacity(theme.cardOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Recordings Card

    private var recordingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "mic.circle.fill")
                    .foregroundColor(theme.snoringAccent).font(.system(size: 14))
                Text("呼噜录音")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
            }
            VStack(spacing: 10) {
                ForEach(Array(session.snoringEvents.reversed().enumerated()), id: \.element.id) { idx, event in
                    SnoringEventRow(event: event, index: session.snoringEvents.count - idx, theme: theme)
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(theme.cardOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Helpers

    private var scoreColor: Color {
        switch session.snoringScore {
        case "优秀": return .green
        case "良好": return theme.accent
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
        if t < 60 { return "\(Int(t))秒" }
        let h = Int(t) / 3600; let m = (Int(t) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)分钟"
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: - NEW: Snoring Timeline（横向水平时间轴）
//   • X 轴 = session 全程（startTime → endTime），空白 = 未打呼噜
//   • 块 X 位置 = 按时间比例（空隙真实反映未打呼噜时段）
//   • 块宽度   = 相对最长事件归一化（直观体现各次长短差异）
//   • 标签     = 轴起止 HH:mm + 事件开始 HH:mm（重叠时跳过）
// ══════════════════════════════════════════════════════════════
struct SnoringTimeline: View {
    let session: SleepSession
    let theme: AppTheme

    private var events: [SnoringEvent] {
        session.snoringEvents.sorted { $0.startTime < $1.startTime }
    }

    private var axisStart: Date {
        let earliest = events.map { $0.startTime }.min() ?? session.startTime
        return min(session.startTime, earliest)
    }
    private var axisEnd: Date {
        let latest = events.compactMap { $0.endTime }.max()
            ?? events.last?.startTime
            ?? session.startTime
        return max(session.endTime ?? Date(), latest)
    }
    private var axisDuration: TimeInterval { max(1, axisEnd.timeIntervalSince(axisStart)) }
    private var maxEventDuration: TimeInterval { events.map { $0.duration }.max() ?? 1 }

    private let trackH:    CGFloat = 44
    private let minBlockW: CGFloat = 6
    private let maxBlockW: CGFloat = 72  // 最长事件对应的最大块宽

    private func blockColor(_ idx: Int) -> Color {
        let p: [Color] = [theme.liveIndicator, theme.accent, theme.snoringAccent, theme.accentLight]
        return p[idx % p.count]
    }

    /// 块宽 = 相对最长事件归一化，最小 minBlockW
    /// 块 X  = 按时间在 session 中的比例（空白 = 未打呼噜）
    /// 若相邻块因宽度膨胀产生重叠，前推后拉修正
    private func layout(W: CGFloat) -> (xs: [CGFloat], ws: [CGFloat]) {
        guard !events.isEmpty else { return ([], []) }
        let ws: [CGFloat] = events.map { e in
            max(minBlockW, CGFloat(e.duration / maxEventDuration) * maxBlockW)
        }
        var xs: [CGFloat] = events.map { e in
            max(0, CGFloat(e.startTime.timeIntervalSince(axisStart) / axisDuration) * W)
        }
        for i in 1..<xs.count {
            if xs[i] < xs[i-1] + ws[i-1] { xs[i] = xs[i-1] + ws[i-1] }
        }
        let last = xs.count - 1
        if xs[last] + ws[last] > W {
            xs[last] = W - ws[last]
            for i in stride(from: last - 1, through: 0, by: -1) {
                if xs[i] > xs[i+1] - ws[i] { xs[i] = xs[i+1] - ws[i] }
            }
        }
        return (xs.map { max(0, $0) }, ws)
    }

    var body: some View {
        Canvas { ctx, size in
            let W = size.width
            let labelY = trackH + 6
            let (xs, ws) = layout(W: W)
            let inset: CGFloat = 6  // 块上下留白，产生浮动胶囊感

            // 轨道背景（灰色底，代表整段睡眠时长，空白 = 未打呼噜）
            let trackPath = Path(roundedRect: CGRect(x: 0, y: 0, width: W, height: trackH),
                                 cornerRadius: 10)
            ctx.fill(trackPath, with: .color(.white.opacity(0.09)))
            ctx.stroke(trackPath, with: .color(.white.opacity(0.14)), lineWidth: 1)

            // 事件块：独立圆角胶囊，宽度反映持续时长，位置反映发生时间
            for (idx, _) in events.enumerated() {
                guard idx < xs.count else { continue }
                let blockRect = CGRect(x: xs[idx], y: inset,
                                      width: ws[idx], height: trackH - inset * 2)
                ctx.fill(Path(roundedRect: blockRect, cornerRadius: 7),
                         with: .color(blockColor(idx).opacity(0.88)))
            }

            // 标签：HH:mm，位于对应块的中心正下方，重叠时跳过
            let fmt = Date.FormatStyle.dateTime.hour().minute()
            let lc  = Color.white.opacity(0.45)
            let labelHalfW: CGFloat = 20
            let edgeW:      CGFloat = 22
            let gap:        CGFloat = 4

            ctx.draw(Text(axisStart.formatted(fmt)).font(.system(size: 10)).foregroundColor(lc),
                     at: CGPoint(x: 0, y: labelY), anchor: .topLeading)
            ctx.draw(Text(axisEnd.formatted(fmt)).font(.system(size: 10)).foregroundColor(lc),
                     at: CGPoint(x: W, y: labelY), anchor: .topTrailing)

            var prevRight: CGFloat = edgeW + gap
            let rightBound: CGFloat = W - edgeW - gap

            for (idx, event) in events.enumerated() {
                guard idx < xs.count else { continue }
                let cx = xs[idx] + ws[idx] / 2   // 标签跟着块走（非自然时间位置）
                guard cx - labelHalfW >= prevRight && cx + labelHalfW <= rightBound else { continue }
                ctx.draw(Text(event.startTime.formatted(fmt)).font(.system(size: 10)).foregroundColor(lc),
                         at: CGPoint(x: cx, y: labelY), anchor: .top)
                prevRight = cx + labelHalfW + gap
            }
        }
        .frame(height: trackH + 26)
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: - OLD: Snoring Bar Chart（竖向柱状图，已停用，保留备查）
// ══════════════════════════════════════════════════════════════
/*
struct SnoringBarChart: View {
    let session: SleepSession
    let theme: AppTheme

    private var events: [SnoringEvent] { session.snoringEvents }
    private var maxSnoreDuration: TimeInterval { events.map { $0.duration }.max() ?? 1 }

    private var firstEventTime: Date  { events.first?.startTime ?? session.startTime }
    private var lastEventEndTime: Date {
        guard let last = events.last else { return session.endTime ?? Date() }
        return last.endTime ?? last.startTime.addingTimeInterval(10)
    }
    private var eventsSpan: TimeInterval { max(5, lastEventEndTime.timeIntervalSince(firstEventTime)) }
    private var axisStart: Date { firstEventTime.addingTimeInterval(-max(10, eventsSpan * 0.20)) }
    private var axisEnd:   Date { lastEventEndTime.addingTimeInterval(max(10, eventsSpan * 0.20)) }
    private var axisDuration: TimeInterval { max(1, axisEnd.timeIntervalSince(axisStart)) }
    private var timeFormat: Date.FormatStyle {
        axisDuration < 300 ? .dateTime.hour().minute().second() : .dateTime.hour().minute()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("持续时长 ↑").font(.system(size: 10)).foregroundColor(.white.opacity(0.25))
                Spacer()
                HStack(spacing: 3) {
                    Text("最长").font(.system(size: 10)).foregroundColor(.white.opacity(0.25))
                    Text("\(Int(maxSnoreDuration))秒")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.snoringAccent.opacity(0.7))
                }
            }
            GeometryReader { geo in
                let w    = geo.size.width
                let h    = geo.size.height
                let rawW = events.count > 0 ? w / CGFloat(events.count) * 0.50 : w
                let barW = min(max(rawW, 8), 30)
                let xs   = adjustedXPositions(width: w, barW: barW)
                Canvas { context, size in
                    for ratio in [0.25, 0.5, 0.75, 1.0] as [CGFloat] {
                        var p = Path()
                        let y = size.height * (1 - ratio)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(.white.opacity(ratio == 1 ? 0.18 : 0.05)), lineWidth: 1)
                    }
                    for (i, event) in events.enumerated() {
                        guard i < xs.count else { continue }
                        let x      = xs[i]
                        let hRatio = CGFloat(event.duration / maxSnoreDuration)
                        let barH   = max(6, hRatio * (size.height - 2))
                        let rect   = CGRect(x: x, y: size.height - barH, width: barW, height: barH)
                        let path   = Path(roundedRect: rect, cornerRadius: min(barW / 2, 5))
                        context.fill(path, with: .color(theme.snoringAccent.opacity(0.45 + 0.55 * Double(hRatio))))
                    }
                }
                .frame(width: w, height: h)
            }
            .frame(height: 88)
            HStack(alignment: .top) {
                Text(axisStart.formatted(timeFormat))
                Spacer()
                if let mid = midLabel { Text(mid.formatted(timeFormat)); Spacer() }
                Text(axisEnd.formatted(timeFormat))
            }
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.28))
        }
    }

    private func adjustedXPositions(width: CGFloat, barW: CGFloat) -> [CGFloat] {
        guard !events.isEmpty else { return [] }
        let minStep = barW + 4
        var xs = events.map { event in
            CGFloat(event.startTime.timeIntervalSince(axisStart) / axisDuration) * width - barW / 2
        }
        for i in 1..<xs.count {
            if xs[i] < xs[i-1] + minStep { xs[i] = xs[i-1] + minStep }
        }
        let maxX = width - barW
        if xs[xs.count - 1] > maxX {
            xs[xs.count - 1] = maxX
            for i in stride(from: xs.count - 2, through: 0, by: -1) {
                let allowed = xs[i + 1] - minStep
                if xs[i] > allowed { xs[i] = allowed }
            }
        }
        return xs.map { max(0, $0) }
    }

    private var midLabel: Date? {
        guard axisDuration > 60 else { return nil }
        return Date(timeIntervalSince1970: axisStart.timeIntervalSince1970 + axisDuration / 2)
    }
}
*/

// MARK: - Snoring Event Row

struct SnoringEventRow: View {
    let event: SnoringEvent
    let index: Int
    let theme: AppTheme

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(index)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(theme.snoringAccent.opacity(0.7))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(formatDuration(event.duration))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(theme.snoringAccent)
                if isPlaying || progress > 0 {
                    ProgressView(value: progress)
                        .tint(theme.snoringAccent)
                        .frame(width: 120)
                        .transition(.opacity)
                } else {
                    Text(event.startTime.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Spacer()

            Button { toggle() } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(colors: [theme.snoringAccent, theme.snoringAccent.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom))
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
        player?.play(); isPlaying = true
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
