import SwiftUI

struct ReportsView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var sessionManager: SleepSessionManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var selectedSession: SleepSession?

    private var theme: AppTheme { themeManager.current }

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.bgColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("睡眠报告")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(store.sessions.count) 条记录")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                if store.sessions.isEmpty {
                    Spacer(); emptyState; Spacer()
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            SessionRowView(session: session, theme: theme)
                                .onTapGesture { selectedSession = session }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        sessionManager.deleteSession(session)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
                .environmentObject(store)
                .environmentObject(themeManager)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 56))
                .foregroundColor(theme.accent.opacity(0.6))
            Text("还没有睡眠记录")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("开始监测后，报告会出现在这里")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.35))
        }
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: SleepSession
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.startTime.formatted(.dateTime.month().day().weekday()))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(timeRange)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Text(session.snoringScore)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(scoreColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(scoreColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack(spacing: 0) {
                miniStat(icon: "moon.fill",
                         value: formatDuration(session.duration),
                         label: "睡眠",
                         color: theme.accent)
                miniStat(icon: "waveform",
                         value: "\(session.snoringEvents.count)次",
                         label: "呼噜",
                         color: theme.snoringAccent)
                miniStat(icon: "percent",
                         value: String(format: "%.0f%%", session.snoringPercentage),
                         label: "占比",
                         color: theme.accentLight)
            }
        }
        .padding(18)
        .background(Color.white.opacity(theme.cardOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func miniStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(value).font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

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
        let h = Int(t) / 3600; let m = (Int(t) % 3600) / 60
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }
}
