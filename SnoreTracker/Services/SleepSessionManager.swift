import Foundation
import Combine

/// 全局单例式管理器：App 启动即监测，按日期自动管理 Session。
class SleepSessionManager: ObservableObject {

    // MARK: - Published（UI 直接绑定这些）
    @Published var isMonitoring = false
    @Published var isSnoring = false
    @Published var currentLevel: Float = 0
    @Published var snoringCount: Int = 0          // 今晚已完成的呼噜次数
    @Published var totalSnoringSeconds: Double = 0 // 今晚累计呼噜秒数（历史）
    @Published var liveSnoreDuration: Double = 0   // 当前这轮呼噜实时秒数（呼噜中才 > 0）
    @Published var todaySession: SleepSession?
    @Published var permissionGranted = false

    let audioService = AudioMonitorService()
    let store: SleepStore

    private var cancellables = Set<AnyCancellable>()
    private var currentEventID: UUID?
    private var currentEventStart: Date?
    private var liveTimer: Timer?          // 驱动 liveSnoreDuration 每 0.1s 更新

    init(store: SleepStore) {
        self.store = store
        setupBindings()
        // App 启动时检查权限，有权限直接开始监测
        audioService.checkPermission()
        permissionGranted = audioService.permissionGranted
        if permissionGranted {
            loadOrCreateTodaySession()
            audioService.startMonitoring()
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
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentLevel)

        audioService.$permissionGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                self?.permissionGranted = granted
            }
            .store(in: &cancellables)

        // 呼噜开始
        audioService.onSnoringStarted = { [weak self] filename in
            DispatchQueue.main.async { self?.handleSnoringStarted(filename: filename) }
        }

        // 呼噜结束
        audioService.onSnoringStopped = { [weak self] in
            DispatchQueue.main.async { self?.handleSnoringStopped() }
        }
    }

    // MARK: - 权限申请（首次）

    func requestPermissionAndStart(completion: @escaping (Bool) -> Void) {
        audioService.requestPermission { [weak self] granted in
            if granted {
                self?.loadOrCreateTodaySession()
                self?.audioService.startMonitoring()
            }
            completion(granted)
        }
    }

    // MARK: - 今日 Session 管理

    /// 查找今天已有的 session 或新建一个
    func loadOrCreateTodaySession() {
        let existing = store.sessions.first {
            Calendar.current.isDateInToday($0.startTime)
        }
        if let existing {
            todaySession = existing
            // 恢复计数
            snoringCount = existing.snoringEvents.filter { $0.endTime != nil }.count
            totalSnoringSeconds = existing.totalSnoringTime
        } else {
            let session = SleepSession(id: UUID(), startTime: Date(), endTime: nil, snoringEvents: [])
            todaySession = session
            store.addSession(session)
        }
    }

    // MARK: - Snoring Events

    private func handleSnoringStarted(filename: String) {
        if todaySession == nil { loadOrCreateTodaySession() }
        guard var session = todaySession else { return }

        let now = Date()
        let event = SnoringEvent(id: UUID(), startTime: now, endTime: nil, recordingFilename: filename)
        currentEventID = event.id
        currentEventStart = now
        session.snoringEvents.append(event)
        snoringCount = session.snoringEvents.count
        todaySession = session
        store.updateSession(session)

        // 启动实时计时器
        liveSnoreDuration = 0
        liveTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.currentEventStart else { return }
            self.liveSnoreDuration = Date().timeIntervalSince(start)
        }
    }

    private func handleSnoringStopped() {
        guard var session = todaySession,
              let id = currentEventID,
              let idx = session.snoringEvents.firstIndex(where: { $0.id == id }) else { return }

        // 停止实时计时器
        liveTimer?.invalidate(); liveTimer = nil

        let endTime = Date()
        session.snoringEvents[idx].endTime = endTime
        totalSnoringSeconds += endTime.timeIntervalSince(currentEventStart ?? endTime)
        liveSnoreDuration = 0

        currentEventID = nil
        currentEventStart = nil
        snoringCount = session.snoringEvents.filter { $0.endTime != nil }.count
        todaySession = session
        store.updateSession(session)
    }

    // MARK: - Data Management

    /// 清除所有数据并重置首页计数
    func clearAllData() {
        liveTimer?.invalidate(); liveTimer = nil
        store.sessions.forEach { store.deleteSession($0) }
        todaySession = nil
        snoringCount = 0
        totalSnoringSeconds = 0
        liveSnoreDuration = 0
        currentEventID = nil
        currentEventStart = nil
    }

    /// 删除单条 session，若删的是今天的则清空状态（不立即重建，等下次呼噜时懒创建）
    func deleteSession(_ session: SleepSession) {
        let isToday = todaySession?.id == session.id
        store.deleteSession(session)
        if isToday {
            liveTimer?.invalidate(); liveTimer = nil
            todaySession = nil
            snoringCount = 0
            totalSnoringSeconds = 0
            liveSnoreDuration = 0
            currentEventID = nil
            currentEventStart = nil
            // 不立即 loadOrCreateTodaySession()，否则会马上塞入新空 session 导致删除无效
        }
    }
}
