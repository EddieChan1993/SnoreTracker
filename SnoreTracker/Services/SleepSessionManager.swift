import Foundation
import Combine

/// 睡眠监测管理器：手动开启/关闭，每次开启创建一条新的睡眠报告。
class SleepSessionManager: ObservableObject {

    // MARK: - Published
    @Published var isMonitoring       = false
    @Published var isSnoring          = false
    @Published var currentLevel:      Float  = 0
    @Published var snoringCount:      Int    = 0
    @Published var totalSnoringSeconds: Double = 0
    @Published var liveSnoreDuration: Double = 0
    @Published var todaySession:      SleepSession?
    @Published var permissionGranted  = false

    let audioService = AudioMonitorService()
    let store: SleepStore

    private var cancellables    = Set<AnyCancellable>()
    private var currentEventID:    UUID?
    private var currentEventStart: Date?
    private var liveTimer:         Timer?
    private var heartbeatTimer:    Timer?   // 每 60s 写入最后活跃时间，用于崩溃恢复

    private static let heartbeatKey  = "monitoringHeartbeat"
    private static let minSessionDuration: TimeInterval = 5 * 60  // 少于 5 分钟的空 session 视为无效

    // MARK: - Init（不自动开始监测）
    init(store: SleepStore) {
        self.store = store
        setupBindings()
        recoverOrphanedSessions()   // 修复上次异常退出留下的未关闭 Session
        audioService.checkPermission()
        permissionGranted = audioService.permissionGranted
        // 不自动开始，等用户手动点击开启
    }

    /// 处理上次 App 被强杀 / 崩溃导致 endTime 未写入的 Session：
    /// - 用心跳时间戳估算实际结束时间（比 Date() 准确）
    /// - 有呼噜事件 → 保留并写入 endTime
    /// - 无呼噜事件但监测超过 5 分钟 → 保留（用户想看到"监测了但没打呼噜"）
    /// - 无呼噜事件且监测不足 5 分钟 → 删除（刚开就崩，无意义）
    private func recoverOrphanedSessions() {
        // 取心跳时间戳作为估算的结束时间；若无心跳则用当前时间
        let heartbeat = UserDefaults.standard.object(forKey: Self.heartbeatKey) as? Date
        UserDefaults.standard.removeObject(forKey: Self.heartbeatKey)

        let orphans = store.sessions.filter { $0.endTime == nil }
        for var session in orphans {
            let estimatedEnd = heartbeat ?? Date()
            let duration     = estimatedEnd.timeIntervalSince(session.startTime)

            if session.snoringEvents.isEmpty && duration < Self.minSessionDuration {
                // 太短且无数据，删除
                store.deleteSession(session)
            } else {
                // 保留：用心跳时间作为结束时间
                session.endTime = estimatedEnd
                store.updateSession(session)
            }
        }
    }

    // MARK: - Bindings

    private func setupBindings() {
        audioService.$isMonitoring
            .receive(on: DispatchQueue.main)
            .assign(to: &$isMonitoring)

        audioService.$isSnoring
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSnoring)

        audioService.$currentLevel
            .assign(to: &$currentLevel)   // displayTimer 已在主线程，无需 receive(on:)

        audioService.$permissionGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in self?.permissionGranted = granted }
            .store(in: &cancellables)

        audioService.onSnoringStarted = { [weak self] filename in
            DispatchQueue.main.async { self?.handleSnoringStarted(filename: filename) }
        }
        audioService.onSnoringStopped = { [weak self] in
            DispatchQueue.main.async { self?.handleSnoringStopped() }
        }
    }

    // MARK: - 监测开关

    /// 手动开启：每次都新建一条报告；手动关闭：写入结束时间
    func toggleMonitoring() {
        if isMonitoring {
            audioService.stopMonitoring()
            closeCurrentSession()
        } else {
            guard permissionGranted else { return }
            startNewSession()
            audioService.startMonitoring()
        }
    }

    // MARK: - 权限申请（首次）

    func requestPermissionAndStart(completion: @escaping (Bool) -> Void) {
        audioService.requestPermission { [weak self] granted in
            if granted {
                self?.startNewSession()
                self?.audioService.startMonitoring()
            }
            completion(granted)
        }
    }

    // MARK: - Session 管理

    /// 每次开启监测都新建一条 Session（按开启时间区分报告）
    private func startNewSession() {
        let session = SleepSession(id: UUID(), startTime: Date(), endTime: nil, snoringEvents: [])
        todaySession        = session
        snoringCount        = 0
        totalSnoringSeconds = 0
        liveSnoreDuration   = 0
        currentEventID      = nil
        currentEventStart   = nil
        store.addSession(session)
        startHeartbeat()
    }

    /// 停止监测时，将结束时间写入当前 Session
    private func closeCurrentSession() {
        stopHeartbeat()
        guard var session = todaySession else { return }
        session.endTime = Date()
        todaySession    = session
        store.updateSession(session)
    }

    // MARK: - 心跳（每 60s 写入最后活跃时间，App 被强杀后用于估算结束时间）

    private func startHeartbeat() {
        UserDefaults.standard.set(Date(), forKey: Self.heartbeatKey)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            UserDefaults.standard.set(Date(), forKey: Self.heartbeatKey)
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        UserDefaults.standard.removeObject(forKey: Self.heartbeatKey)
    }

    // MARK: - Snoring Events

    private func handleSnoringStarted(filename: String) {
        guard var session = todaySession else { return }

        let now   = Date()
        let event = SnoringEvent(id: UUID(), startTime: now, endTime: nil, recordingFilename: filename)
        currentEventID    = event.id
        currentEventStart = now
        session.snoringEvents.append(event)
        snoringCount  = session.snoringEvents.count
        todaySession  = session
        store.updateSession(session)

        liveSnoreDuration = 0
        liveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let start = self.currentEventStart else { return }
            self.liveSnoreDuration = Date().timeIntervalSince(start)
        }
    }

    private func handleSnoringStopped() {
        guard var session = todaySession,
              let id  = currentEventID,
              let idx = session.snoringEvents.firstIndex(where: { $0.id == id }) else { return }

        liveTimer?.invalidate(); liveTimer = nil

        let endTime = Date()
        session.snoringEvents[idx].endTime = endTime
        totalSnoringSeconds += endTime.timeIntervalSince(currentEventStart ?? endTime)
        liveSnoreDuration = 0

        currentEventID    = nil
        currentEventStart = nil
        snoringCount      = session.snoringEvents.filter { $0.endTime != nil }.count
        todaySession      = session
        store.updateSession(session)
    }

    // MARK: - Data Management

    func clearAllData() {
        liveTimer?.invalidate(); liveTimer = nil
        stopHeartbeat()
        store.sessions.forEach { store.deleteSession($0) }
        todaySession        = nil
        snoringCount        = 0
        totalSnoringSeconds = 0
        liveSnoreDuration   = 0
        currentEventID      = nil
        currentEventStart   = nil
    }

    func deleteSession(_ session: SleepSession) {
        let isCurrent = todaySession?.id == session.id
        store.deleteSession(session)
        if isCurrent {
            liveTimer?.invalidate(); liveTimer = nil
            todaySession        = nil
            snoringCount        = 0
            totalSnoringSeconds = 0
            liveSnoreDuration   = 0
            currentEventID      = nil
            currentEventStart   = nil
        }
    }
}
