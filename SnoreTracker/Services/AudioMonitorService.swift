import AVFoundation
import Accelerate
import Combine
import UIKit

// MARK: - SnoringDetector

/// FFT 呼噜频率分析器。所有缓冲区 init 时预分配，Hann 窗预计算，零运行时 malloc。
final class SnoringDetector {

    private let fftSize  = 4096
    private let log2n:   vDSP_Length
    private var fftSetup: FFTSetup?

    private var samples: [Float]
    private var window:  [Float]
    private var realp:   [Float]
    private var imagp:   [Float]
    private var mags:    [Float]

    private let snoreLo: Int
    private let snoreHi: Int
    private let highHi:  Int

    init(sampleRate: Float) {
        let size = 4096
        log2n    = vDSP_Length(log2f(Float(size)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        let half = size / 2
        samples  = [Float](repeating: 0, count: size)
        window   = [Float](repeating: 0, count: size)
        realp    = [Float](repeating: 0, count: half)
        imagp    = [Float](repeating: 0, count: half)
        mags     = [Float](repeating: 0, count: half)

        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))

        let binW = sampleRate / Float(size)
        snoreLo  = max(1,    Int(80   / binW))
        snoreHi  = min(half, Int(800  / binW))
        highHi   = min(half, Int(6000 / binW))
    }

    deinit { if let s = fftSetup { vDSP_destroy_fftsetup(s) } }

    func score(buffer: AVAudioPCMBuffer, rms: Float, minimumRMS: Float) -> Float {
        guard rms >= minimumRMS,
              let setup = fftSetup,
              let raw   = buffer.floatChannelData?[0] else { return 0 }

        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }

        let stride  = max(1, n / fftSize)
        let copyLen = min(n / stride, fftSize)

        samples.withUnsafeMutableBufferPointer { buf in
            for i in 0..<copyLen { buf[i] = raw[i * stride] }
            if copyLen < fftSize {
                (buf.baseAddress! + copyLen).initialize(repeating: 0, count: fftSize - copyLen)
            }
        }

        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))

        realp.withUnsafeMutableBufferPointer { rBuf in
            imagp.withUnsafeMutableBufferPointer { iBuf in
                var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                samples.withUnsafeBytes { rawBytes in
                    rawBytes.withMemoryRebound(to: DSPComplex.self) { cBuf in
                        vDSP_ctoz(cBuf.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                mags.withUnsafeMutableBufferPointer { mBuf in
                    vDSP_zvmags(&split, 1, mBuf.baseAddress!, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        func bandSum(_ lo: Int, _ hi: Int) -> Float {
            guard hi > lo else { return 0 }
            var s: Float = 0
            mags.withUnsafeBufferPointer { buf in
                vDSP_sve(buf.baseAddress! + lo, 1, &s, vDSP_Length(hi - lo))
            }
            return s
        }

        let snoreE = bandSum(snoreLo, snoreHi)
        let totalE = bandSum(snoreLo, highHi)
        guard totalE > 0 else { return 0 }
        return snoreE / totalE
    }
}

// MARK: - AudioMonitorService

class AudioMonitorService: ObservableObject {

    @Published var isMonitoring      = false
    @Published var isSnoring         = false
    @Published var currentLevel:     Float = 0
    @Published var permissionGranted = false

    var onSnoringStarted: ((String) -> Void)?
    var onSnoringStopped: (() -> Void)?
    var onError:          ((String) -> Void)?

    var minimumRMS:          Float        = 0.015
    var snoreScoreThreshold: Float        = 0.25
    var confirmDelay:        TimeInterval = 1.0
    var silenceDelay:        TimeInterval = 5.0

    private var audioEngine   = AVAudioEngine()
    private var recordingFile: AVAudioFile?
    private var isRecording   = false
    private var detector:     SnoringDetector?
    private var confirmTimer: Timer?
    private var silenceTimer: Timer?

    // FFT 每隔一帧做一次（~200ms/次），检测延迟远小于 confirmDelay（≥1s）
    // 注意：不用 stableFrames 类"按状态跳过"——会在呼噜刚开始时漏检（见 CLAUDE.md §1）
    private var bufferCount = 0
    private let fftEvery    = 2

    private var lastIsLoud:  Bool  = false
    private var smoothLevel: Float = 0

    private let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    // ── 后台保活 ─────────────────────────────────────────────────────────────
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        if d.object(forKey: "minimumRMS")          != nil { minimumRMS          = Float(d.double(forKey: "minimumRMS")) }
        if d.object(forKey: "snoreScoreThreshold") != nil { snoreScoreThreshold = Float(d.double(forKey: "snoreScoreThreshold")) }
        if d.object(forKey: "confirmDelay")        != nil { confirmDelay        = d.double(forKey: "confirmDelay") }
        if d.object(forKey: "silenceDelay")        != nil { silenceDelay        = d.double(forKey: "silenceDelay") }
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Permission

    func checkPermission() {
        permissionGranted = AVAudioSession.sharedInstance().recordPermission == .granted
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { self.permissionGranted = granted; completion(granted) }
        }
    }

    // MARK: - Start / Stop

    func startMonitoring() {
        guard permissionGranted, !isMonitoring else { return }
        setupNotificationObservers()
        activateAndStartEngine()
        requestBackgroundTask()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        teardown()
        removeNotificationObservers()
        endBackgroundTask()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async {
            self.isMonitoring = false
            self.isSnoring    = false
            self.currentLevel = 0
        }
    }

    // MARK: - Engine Lifecycle

    @discardableResult
    private func activateAndStartEngine() -> Bool {
        // session 用 .default 保留 AGC；见 CLAUDE.md §3（禁止改 .measurement）
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.allowBluetoothHFP, .mixWithOthers])
            // bufferSize=2048 + IOBufferDuration=0.1 = 10Hz 是经过验证的稳定值：
            // 更快 → iOS 后台杀进程；更慢 → 电平环卡顿（见 CLAUDE.md §1 踩坑记录）
            try s.setPreferredSampleRate(16000)
            try s.setPreferredIOBufferDuration(0.1)
            try s.setActive(true)
        } catch {
            onError?("音频会话失败: \(error.localizedDescription)")
            return false
        }

        audioEngine  = AVAudioEngine()
        let input    = audioEngine.inputNode
        let format   = input.outputFormat(forBus: 0)
        detector     = SnoringDetector(sampleRate: Float(format.sampleRate))
        lastIsLoud   = false
        smoothLevel  = 0
        bufferCount  = 0

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buf, _ in
            self?.process(buffer: buf)
        }

        do {
            try audioEngine.start()
            DispatchQueue.main.async { self.isMonitoring = true }
            return true
        } catch {
            onError?("引擎启动失败: \(error.localizedDescription)")
            return false
        }
    }

    private func teardown() {
        confirmTimer?.invalidate(); silenceTimer?.invalidate()
        confirmTimer = nil;         silenceTimer = nil
        finishRecording()
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }

    // MARK: - Audio Processing（audio 线程，禁止访问 UI）

    private func process(buffer: AVAudioPCMBuffer) {
        if isRecording, let file = recordingFile {
            try? file.write(from: buffer)
        }

        var rms: Float = 0
        if let data = buffer.floatChannelData?[0] {
            vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        }

        // 静音快速短路：RMS 低于阈值，直接标记非呼噜，跳过 FFT
        var isLoud = lastIsLoud
        if rms < minimumRMS {
            isLoud = false
        } else {
            bufferCount += 1
            if bufferCount % fftEvery == 0 {
                let sc = detector?.score(buffer: buffer, rms: rms, minimumRMS: minimumRMS) ?? 0
                isLoud = sc >= snoreScoreThreshold
            }
            // 非 FFT 帧：保持上次判断（等下一帧）
        }

        let changed = isLoud != lastIsLoud
        lastIsLoud  = isLoud

        // 平滑：上升跟紧，下降缓衰
        smoothLevel = rms > smoothLevel ? rms : 0.2 * rms + 0.8 * smoothLevel
        let level   = smoothLevel

        // 每次回调直接 dispatch，零轮询延迟，保证检测环即时响应
        DispatchQueue.main.async { [weak self, level, isLoud, changed] in
            guard let self else { return }
            self.currentLevel = level
            if changed { isLoud ? self.onLoud() : self.onSilent() }
        }
    }

    // MARK: - State Machine（主线程，由 displayTimer 驱动）

    private func onLoud() {
        silenceTimer?.invalidate(); silenceTimer = nil
        if !isSnoring && confirmTimer == nil {
            confirmTimer = Timer.scheduledTimer(withTimeInterval: confirmDelay, repeats: false) { [weak self] _ in
                self?.confirmTimer = nil; self?.beginSnoring()
            }
        }
    }

    private func onSilent() {
        confirmTimer?.invalidate(); confirmTimer = nil
        if isSnoring && silenceTimer == nil {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDelay, repeats: false) { [weak self] _ in
                self?.silenceTimer = nil; self?.endSnoring()
            }
        }
    }

    private func beginSnoring() {
        guard !isSnoring else { return }
        isSnoring = true
        if let filename = startRecording() { onSnoringStarted?(filename) }
    }

    private func endSnoring() {
        guard isSnoring else { return }
        isSnoring = false
        finishRecording()
        onSnoringStopped?()
    }

    // MARK: - Recording

    @discardableResult
    private func startRecording() -> String? {
        let filename = "snore_\(Int(Date().timeIntervalSince1970)).caf"
        let url = docsURL.appendingPathComponent(filename)
        let fmt = audioEngine.inputNode.outputFormat(forBus: 0)
        do {
            recordingFile = try AVAudioFile(forWriting: url, settings: fmt.settings,
                                            commonFormat: fmt.commonFormat,
                                            interleaved: fmt.isInterleaved)
            isRecording = true
            return filename
        } catch { print("录音启动失败: \(error)"); return nil }
    }

    private func finishRecording() {
        isRecording = false; recordingFile = nil
    }

    // MARK: - 后台任务（双重保险）

    private func requestBackgroundTask() {
        endBackgroundTask()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "SnoreMonitor") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    // MARK: - 系统通知（保活关键）

    private func setupNotificationObservers() {
        removeNotificationObservers()
        let s = AVAudioSession.sharedInstance()
        let nc = NotificationCenter.default

        // ① 中断（来电、闹钟、Siri）——最常见的 4 小时被杀原因：
        //    中断后 session 失活，audio 后台模式失效，数分钟后 iOS 杀进程
        notificationObservers.append(
            nc.addObserver(forName: AVAudioSession.interruptionNotification,
                           object: s, queue: .main) { [weak self] n in
                self?.handleInterruption(n)
            }
        )

        // ② 媒体服务重置（系统崩溃或硬件异常导致 AVAudioSession 整体失效）
        notificationObservers.append(
            nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                           object: nil, queue: .main) { [weak self] _ in
                self?.handleMediaServicesReset()
            }
        )

        // ③ 路由变更（蓝牙断开等）——只记日志，不重启 engine
        //    原因：AVAudioEngineConfigurationChange 在正常运行时也可能触发，
        //    重启会重置 lastIsLoud 但不重置 isSnoring，导致状态机死锁（见 CLAUDE.md §1）
        notificationObservers.append(
            nc.addObserver(forName: AVAudioSession.routeChangeNotification,
                           object: s, queue: .main) { n in
                if let r = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt {
                    print("[Audio] 路由变更 reason=\(r)")
                }
            }
        )
    }

    private func removeNotificationObservers() {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
    }

    // MARK: - 中断处理

    private func handleInterruption(_ note: Notification) {
        guard let info  = note.userInfo,
              let typeV = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type  = AVAudioSession.InterruptionType(rawValue: typeV) else { return }

        switch type {
        case .began:
            print("[Audio] 中断开始（来电/闹钟等）")
            // engine 已被系统停止，音频回调自然停止，无需额外处理

        case .ended:
            print("[Audio] 中断结束，尝试恢复")
            // 无论系统是否标记 shouldResume，都主动重激活：
            // 不重启则 session 保持失活 → audio 后台模式失效 → 被杀进程
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.isMonitoring else { return }
                self.safeRestartEngine()
            }

        @unknown default:
            break
        }
    }

    // MARK: - 媒体服务重置

    private func handleMediaServicesReset() {
        guard isMonitoring else { return }
        print("[Audio] 媒体服务重置，完全重建")
        // 强制重置所有状态（session 已失效，不能复用）
        teardown()
        isSnoring = false   // 重置状态机，防止死锁
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.isMonitoring else { return }
            self.activateAndStartEngine()
        }
    }

    // MARK: - 安全重启（仅用于中断恢复，不用于路由变更）

    /// 重新激活 session 并重启 engine，对用户透明（isMonitoring 保持 true）。
    /// 若当前正在打呼噜，先结束录音事件，重启后重新检测，避免状态机死锁。
    private func safeRestartEngine() {
        // 若正在打呼噜则先正常结束，防止重置 lastIsLoud 后 isSnoring 卡死
        if isSnoring { endSnoring() }

        confirmTimer?.invalidate(); silenceTimer?.invalidate()
        confirmTimer = nil;         silenceTimer = nil

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isMonitoring else { return }
            self.activateAndStartEngine()
        }
    }
}
