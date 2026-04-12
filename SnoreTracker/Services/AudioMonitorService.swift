import AVFoundation
import Accelerate
import Combine

// MARK: - SnoringDetector（FFT 频率分析）

/// 综合 RMS 振幅 + 低频能量占比判断呼噜声。
/// 性能优化：所有 FFT 缓冲区在 init 时预分配，Hann 窗预计算，避免每帧 malloc。
final class SnoringDetector {

    private let fftSize  = 4096
    private let log2n:   vDSP_Length
    private var fftSetup: FFTSetup?

    // ── 预分配缓冲区（避免每帧 ~80 KB malloc） ──
    private var samples: [Float]
    private var window:  [Float]   // Hann 窗，init 时计算一次
    private var realp:   [Float]
    private var imagp:   [Float]
    private var mags:    [Float]

    // ── 预计算频段 bin 下标（采样率固定，无需每帧重算） ──
    private let snoreLo: Int   // 80 Hz
    private let snoreHi: Int   // 500 Hz
    private let highLo:  Int   // 1000 Hz
    private let highHi:  Int   // 6000 Hz

    init(sampleRate: Float) {
        let half = fftSize / 2
        log2n   = vDSP_Length(log2f(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        samples = [Float](repeating: 0, count: fftSize)
        window  = [Float](repeating: 0, count: fftSize)
        realp   = [Float](repeating: 0, count: half)
        imagp   = [Float](repeating: 0, count: half)
        mags    = [Float](repeating: 0, count: half)

        // Hann 窗只算一次
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        // 固定频段 bin
        let binW  = sampleRate / Float(fftSize)
        snoreLo   = max(1,    Int(80   / binW))
        snoreHi   = min(half, Int(500  / binW))
        highLo    = min(half, Int(1000 / binW))
        highHi    = min(half, Int(6000 / binW))
    }

    deinit {
        if let s = fftSetup { vDSP_destroy_fftsetup(s) }
    }

    /// 返回 0~1 呼噜得分（在 audio 线程调用，无内存分配）
    func score(buffer: AVAudioPCMBuffer, minimumRMS: Float) -> Float {
        guard let setup = fftSetup,
              let raw   = buffer.floatChannelData?[0] else { return 0 }

        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }

        // 1. RMS 门槛（最廉价，优先排除静音帧）
        var rms: Float = 0
        vDSP_rmsqv(raw, 1, &rms, vDSP_Length(n))
        guard rms >= minimumRMS else { return 0 }

        // 2. 拷贝到预分配缓冲区（无新 malloc）
        let copyLen = min(n, fftSize)
        samples.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.update(from: raw, count: copyLen)
            if copyLen < fftSize {
                (buf.baseAddress! + copyLen).initialize(repeating: 0, count: fftSize - copyLen)
            }
        }

        // 3. 加窗（预计算 Hann 窗）
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))

        // 4. 实数 FFT（预分配 split-complex 缓冲区）
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

        // 5. 频段能量（直接指针偏移，避免 Array 切片副本）
        func bandSum(_ lo: Int, _ hi: Int) -> Float {
            guard hi > lo else { return 0 }
            var s: Float = 0
            mags.withUnsafeBufferPointer { buf in
                vDSP_sve(buf.baseAddress! + lo, 1, &s, vDSP_Length(hi - lo))
            }
            return s
        }

        let snoreEnergy = bandSum(snoreLo, snoreHi)
        let highEnergy  = bandSum(highLo,  highHi)
        let totalEnergy = bandSum(1,       highHi)
        guard totalEnergy > 0 else { return 0 }

        let snoreRatio = snoreEnergy / totalEnergy
        let highRatio  = highEnergy  / totalEnergy
        return snoreRatio * max(0, 1 - highRatio * 1.5)
    }
}

// MARK: - AudioMonitorService

class AudioMonitorService: ObservableObject {

    // MARK: Published
    @Published var isMonitoring   = false
    @Published var isSnoring      = false
    @Published var currentLevel:  Float = 0
    @Published var permissionGranted = false

    // MARK: Callbacks
    var onSnoringStarted: ((String) -> Void)?
    var onSnoringStopped: (() -> Void)?
    var onError: ((String) -> Void)?

    // MARK: Config（启动时从 UserDefaults 恢复）
    var minimumRMS:          Float        = 0.02
    var snoreScoreThreshold: Float        = 0.40
    var confirmDelay:        TimeInterval = 1.0
    var silenceDelay:        TimeInterval = 5.0

    // MARK: Private
    private var audioEngine   = AVAudioEngine()
    private var recordingFile: AVAudioFile?
    private var isRecording   = false
    private var detector:     SnoringDetector?

    private var confirmTimer: Timer?
    private var silenceTimer: Timer?

    private let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    // ── 节流控制（audio 线程私有，无需加锁） ──
    private var lastIsLoud:   Bool   = false
    private var frameCount:   UInt8  = 0       // 溢出自动归零，无需 % 保护
    private var smoothLevel:  Float  = 0       // 平滑在 audio 线程做，减少主线程计算

    // MARK: - Init
    init() {
        let d = UserDefaults.standard
        if d.object(forKey: "minimumRMS")          != nil { minimumRMS          = Float(d.double(forKey: "minimumRMS")) }
        if d.object(forKey: "snoreScoreThreshold") != nil { snoreScoreThreshold = Float(d.double(forKey: "snoreScoreThreshold")) }
        if d.object(forKey: "confirmDelay")        != nil { confirmDelay        = d.double(forKey: "confirmDelay") }
        if d.object(forKey: "silenceDelay")        != nil { silenceDelay        = d.double(forKey: "silenceDelay") }
    }

    // MARK: - Permission

    func checkPermission() {
        permissionGranted = AVAudioApplication.shared.recordPermission == .granted
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { self.permissionGranted = granted; completion(granted) }
        }
    }

    // MARK: - Start / Stop

    func startMonitoring() {
        guard permissionGranted, !isMonitoring else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try s.setActive(true)
        } catch {
            onError?("音频会话失败: \(error.localizedDescription)"); return
        }

        audioEngine = AVAudioEngine()
        let input   = audioEngine.inputNode
        let format  = input.outputFormat(forBus: 0)
        detector    = SnoringDetector(sampleRate: Float(format.sampleRate))
        lastIsLoud  = false
        frameCount  = 0
        smoothLevel = 0

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buf, _ in
            self?.process(buffer: buf)
        }

        do {
            try audioEngine.start()
            DispatchQueue.main.async { self.isMonitoring = true }
        } catch {
            onError?("引擎启动失败: \(error.localizedDescription)")
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        confirmTimer?.invalidate(); silenceTimer?.invalidate()
        confirmTimer = nil; silenceTimer = nil
        finishRecording()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        DispatchQueue.main.async {
            self.isMonitoring = false; self.isSnoring = false; self.currentLevel = 0
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio Processing（audio 线程）

    private func process(buffer: AVAudioPCMBuffer) {
        // 录音写文件（必须每帧处理）
        if isRecording, let file = recordingFile {
            try? file.write(from: buffer)
        }

        // 呼噜得分
        let score   = detector?.score(buffer: buffer, minimumRMS: minimumRMS) ?? 0
        let isLoud  = score >= snoreScoreThreshold
        let changed = isLoud != lastIsLoud
        lastIsLoud  = isLoud

        // UI 波形节流：每 3 帧更新一次（~3.5 Hz），状态变化立即派发
        frameCount  &+= 1
        let sendUI  = frameCount % 3 == 0

        guard changed || sendUI else { return }

        // RMS + 平滑（在 audio 线程计算，减少主线程负担）
        var rms: Float = 0
        if let data = buffer.floatChannelData?[0] {
            vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        }
        smoothLevel = 0.7 * smoothLevel + 0.3 * rms
        let level   = smoothLevel

        DispatchQueue.main.async { [weak self, isLoud, changed, level, sendUI] in
            guard let self else { return }
            if sendUI  { self.currentLevel = level }
            if changed { isLoud ? self.onLoud() : self.onSilent() }
        }
    }

    // MARK: - State Machine（主线程）

    private func onLoud() {
        silenceTimer?.invalidate(); silenceTimer = nil
        if !isSnoring && confirmTimer == nil {
            confirmTimer = Timer.scheduledTimer(withTimeInterval: confirmDelay, repeats: false) { [weak self] _ in
                self?.confirmTimer = nil
                self?.beginSnoring()
            }
        }
    }

    private func onSilent() {
        confirmTimer?.invalidate(); confirmTimer = nil
        if isSnoring && silenceTimer == nil {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDelay, repeats: false) { [weak self] _ in
                self?.silenceTimer = nil
                self?.endSnoring()
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
        let filename = "snore_\(Int(Date().timeIntervalSince1970)).m4a"
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
}
