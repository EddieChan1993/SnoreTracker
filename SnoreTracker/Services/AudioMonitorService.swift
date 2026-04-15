import AVFoundation
import Accelerate
import Combine

// MARK: - SnoringDetector

/// FFT 呼噜频率分析器。所有缓冲区 init 时预分配，Hann 窗预计算，零运行时 malloc。
final class SnoringDetector {

    private let fftSize:  Int
    private let log2n:    vDSP_Length
    private var fftSetup: FFTSetup?

    private var samples: [Float]
    private var window:  [Float]
    private var realp:   [Float]
    private var imagp:   [Float]
    private var mags:    [Float]

    private let snoreLo: Int
    private let snoreHi: Int
    private let highLo:  Int
    private let highHi:  Int

    init(sampleRate: Float) {
        // 呼噜最高关注频率 6000 Hz → Nyquist 12000 Hz → 16000 Hz 采样率足够
        // 实际采样率由硬件决定，2048 point FFT 已足够分辨率
        let size  = 2048
        fftSize   = size
        log2n     = vDSP_Length(log2f(Float(size)))
        fftSetup  = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        let half  = size / 2
        samples   = [Float](repeating: 0, count: size)
        window    = [Float](repeating: 0, count: size)
        realp     = [Float](repeating: 0, count: half)
        imagp     = [Float](repeating: 0, count: half)
        mags      = [Float](repeating: 0, count: half)

        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))

        let binW  = sampleRate / Float(size)
        snoreLo   = max(1,    Int(80   / binW))
        snoreHi   = min(half, Int(500  / binW))
        highLo    = min(half, Int(1000 / binW))
        highHi    = min(half, Int(6000 / binW))
    }

    deinit { if let s = fftSetup { vDSP_destroy_fftsetup(s) } }

    /// 呼噜得分（0~1）。接受外部预算好的 rms，避免在 process() 里重复计算。
    func score(buffer: AVAudioPCMBuffer, rms: Float, minimumRMS: Float) -> Float {
        guard rms >= minimumRMS,
              let setup = fftSetup,
              let raw   = buffer.floatChannelData?[0] else { return 0 }

        let n       = Int(buffer.frameLength)
        let copyLen = min(n, fftSize)

        samples.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.update(from: raw, count: copyLen)
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
        let highE  = bandSum(highLo,  highHi)
        let totalE = bandSum(1,       highHi)
        guard totalE > 0 else { return 0 }

        return (snoreE / totalE) * max(0, 1 - (highE / totalE) * 1.5)
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

    var minimumRMS:          Float        = 0.02
    var snoreScoreThreshold: Float        = 0.40
    var confirmDelay:        TimeInterval = 1.0
    var silenceDelay:        TimeInterval = 5.0

    private var audioEngine   = AVAudioEngine()
    private var recordingFile: AVAudioFile?
    private var isRecording   = false
    private var detector:     SnoringDetector?
    private var confirmTimer: Timer?
    private var silenceTimer: Timer?

    private let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    // audio 线程私有，无需加锁
    private var lastIsLoud:   Bool   = false
    private var frameCount:   UInt8  = 0
    private var smoothLevel:  Float  = 0
    private var stableFrames: UInt8  = 0   // 连续同状态帧数，用于跳过 FFT

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
        do {
            let s = AVAudioSession.sharedInstance()
            // .measurement 模式：专为音频采集设计，比 .default 更省电
            try s.setCategory(.playAndRecord, mode: .measurement,
                              options: [.allowBluetoothHFP, .mixWithOthers])
            // 请求 16000 Hz：呼噜检测最高关注 6000 Hz，16000 Hz Nyquist 足够
            // 减少 DSP 管线数据量约 64%（若硬件支持）
            try s.setPreferredSampleRate(16000)
            // 请求 200ms IO 缓冲：减少 CPU 唤醒次数至 ~5 次/秒（原 ~10 次/秒）
            try s.setPreferredIOBufferDuration(0.2)
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
        stableFrames = 0

        // bufferSize 8192：进一步降低回调频率，每次回调处理更多帧
        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buf, _ in
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
        if isRecording, let file = recordingFile {
            try? file.write(from: buffer)
        }

        // RMS 计算一次，同时用于：① FFT 门控 ② UI 平滑 ③ 静默跳过判断
        var rms: Float = 0
        if let data = buffer.floatChannelData?[0] {
            vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        }

        // 连续静音优化：静音且状态稳定超过 8 帧时跳过整个 FFT 调用
        // 典型睡眠场景：大部分时间安静 → 节省绝大多数夜晚的 FFT 开销
        let clearlyQuiet = rms < minimumRMS * 0.5
        if clearlyQuiet && !lastIsLoud && stableFrames > 8 {
            frameCount &+= 1
            if frameCount % 5 == 0 {
                smoothLevel = 0.7 * smoothLevel + 0.3 * rms
                let level = smoothLevel
                DispatchQueue.main.async { [weak self, level] in self?.currentLevel = level }
            }
            return
        }

        // FFT 分析
        let score   = detector?.score(buffer: buffer, rms: rms, minimumRMS: minimumRMS) ?? 0
        let isLoud  = score >= snoreScoreThreshold
        let changed = isLoud != lastIsLoud

        stableFrames = changed ? 0 : min(255, stableFrames &+ 1)
        lastIsLoud   = isLoud

        frameCount  &+= 1
        let sendUI  = frameCount % 3 == 0

        guard changed || sendUI else { return }

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
