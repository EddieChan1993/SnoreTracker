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

    // MARK: - Init（不自动开始监测）
    init(store: SleepStore) {
        self.store = store
        setupBindings()
        audioService.checkPermission()
        permissionGranted = audioService.permissionGranted
        // 不自动开始，等用户手动点击开启
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
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentLevel)

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
        todaySession       = session
        snoringCount       = 0
        totalSnoringSeconds = 0
        liveSnoreDuration  = 0
        currentEventID     = nil
        currentEventStart  = nil
        store.addSession(session)
    }

    /// 停止监测时，将结束时间写入当前 Session
    private func closeCurrentSession() {
        guard var session = todaySession else { return }
        session.endTime = Date()
        todaySession    = session
        store.updateSession(session)
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
