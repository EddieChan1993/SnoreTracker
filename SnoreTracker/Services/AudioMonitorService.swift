import AVFoundation
import Accelerate
import Combine

// MARK: - Snoring Detector（FFT 频率分析）

/// 综合 RMS 振幅 + 低频能量占比来判断是否像呼噜声。
/// 呼噜声：80~500 Hz 能量集中，振幅适中
/// 口哨/说话：高频能量占主导，自动排除
final class SnoringDetector {

    private let sampleRate: Float
    private let fftSize = 4096
    private var fftSetup: FFTSetup?
    private let log2n: vDSP_Length

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        log2n = vDSP_Length(log2f(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let s = fftSetup { vDSP_destroy_fftsetup(s) }
    }

    /// 返回 0~1 的呼噜得分（振幅 + 低频占比综合评分）
    func score(buffer: AVAudioPCMBuffer, minimumRMS: Float) -> Float {
        guard let setup = fftSetup,
              let raw = buffer.floatChannelData?[0] else { return 0 }

        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }

        // 1. RMS 静音门槛
        var rms: Float = 0
        vDSP_rmsqv(raw, 1, &rms, vDSP_Length(n))
        guard rms >= minimumRMS else { return 0 }

        // 2. 拷贝并补零到 fftSize（直接下标赋值，避免 cblas）
        let copyLen = min(n, fftSize)
        var samples = [Float](repeating: 0, count: fftSize)
        for i in 0..<copyLen { samples[i] = raw[i] }

        // 3. Hann 窗
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))

        // 4. 实数 FFT（使用 withUnsafeMutableBufferPointer 固定地址）
        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)
        var mags  = [Float](repeating: 0, count: fftSize / 2)

        realp.withUnsafeMutableBufferPointer { rBuf in
            imagp.withUnsafeMutableBufferPointer { iBuf in
                var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)

                // 交织 → 分离
                samples.withUnsafeBytes { rawBytes in
                    rawBytes.withMemoryRebound(to: DSPComplex.self) { cBuf in
                        vDSP_ctoz(cBuf.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }

                // 前向 FFT
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                // 取幅度平方
                mags.withUnsafeMutableBufferPointer { mBuf in
                    vDSP_zvmags(&split, 1, mBuf.baseAddress!, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        // 5. 频段能量（用数组切片，避免指针偏移）
        let binWidth = sampleRate / Float(fftSize)
        let half     = fftSize / 2

        let snoreLo  = max(1,    Int(80   / binWidth))
        let snoreHi  = min(half, Int(500  / binWidth))
        let highLo   = min(half, Int(1000 / binWidth))
        let highHi   = min(half, Int(6000 / binWidth))
        let totalHi  = highHi

        func bandSum(_ lo: Int, _ hi: Int) -> Float {
            guard hi > lo else { return 0 }
            var s: Float = 0
            let slice = Array(mags[lo..<hi])
            vDSP_sve(slice, 1, &s, vDSP_Length(slice.count))
            return s
        }

        let snoreEnergy = bandSum(snoreLo, snoreHi)
        let highEnergy  = bandSum(highLo,  highHi)
        let totalEnergy = bandSum(1,       totalHi)
        guard totalEnergy > 0 else { return 0 }

        // 6. 呼噜得分：低频占比高 × (1 - 高频占比惩罚)
        let snoreRatio = snoreEnergy / totalEnergy   // 呼噜 ≈ 0.5+，口哨 ≈ 0.1
        let highRatio  = highEnergy  / totalEnergy   // 呼噜 ≈ 0.1~0.3，口哨 ≈ 0.7+
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

    // MARK: Config（可在设置页调整，启动时从 UserDefaults 恢复）
    var minimumRMS:          Float        = 0.02
    var snoreScoreThreshold: Float        = 0.40
    var confirmDelay:        TimeInterval = 1.0
    var silenceDelay:        TimeInterval = 5.0

    // MARK: Private
    private var audioEngine   = AVAudioEngine()

    // MARK: - Init（恢复用户保存的设置）
    init() {
        let d = UserDefaults.standard
        if d.object(forKey: "minimumRMS")          != nil { minimumRMS          = Float(d.double(forKey: "minimumRMS")) }
        if d.object(forKey: "snoreScoreThreshold") != nil { snoreScoreThreshold = Float(d.double(forKey: "snoreScoreThreshold")) }
        if d.object(forKey: "confirmDelay")        != nil { confirmDelay        = d.double(forKey: "confirmDelay") }
        if d.object(forKey: "silenceDelay")        != nil { silenceDelay        = d.double(forKey: "silenceDelay") }
    }
    private var recordingFile: AVAudioFile?
    private var isRecording   = false
    private var detector:     SnoringDetector?

    private var confirmTimer: Timer?
    private var silenceTimer: Timer?

    private let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

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
        let input  = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        detector   = SnoringDetector(sampleRate: Float(format.sampleRate))

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

    // MARK: - Audio Processing (audio thread)

    private func process(buffer: AVAudioPCMBuffer) {
        // 录音写文件（在 audio 线程直接写，安全高效）
        if isRecording, let file = recordingFile {
            try? file.write(from: buffer)
        }

        // 计算 RMS 用于 UI 波形显示
        var rms: Float = 0
        if let data = buffer.floatChannelData?[0] {
            vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        }

        // 频率得分（计算略重，但 vDSP 硬件加速，耗时 < 1ms）
        let snoreScore = detector?.score(buffer: buffer, minimumRMS: minimumRMS) ?? 0

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentLevel = 0.7 * self.currentLevel + 0.3 * rms
            if snoreScore >= self.snoreScoreThreshold {
                self.onLoud()
            } else {
                self.onSilent()
            }
        }
    }

    // MARK: - State Machine (main thread)

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
