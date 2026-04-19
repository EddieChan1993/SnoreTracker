import AVFoundation
import Accelerate
import Combine

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

    // 预计算频段 bin（采样率固定后不变）
    // snore band 扩展至 800 Hz：打鼾泛音可延伸至 600–800 Hz，500 Hz 上限会漏掉这部分能量
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

        // 若采样率被降至 16000 Hz，bin 宽 = 16000/4096 ≈ 3.9 Hz（分辨率更高）
        // 若仍为 44100 Hz，bin 宽 = 44100/4096 ≈ 10.8 Hz（同原始设计）
        let binW = sampleRate / Float(size)
        snoreLo  = max(1,    Int(80   / binW))
        snoreHi  = min(half, Int(800  / binW))
        highHi   = min(half, Int(6000 / binW))
    }

    deinit { if let s = fftSetup { vDSP_destroy_fftsetup(s) } }

    /// 呼噜得分（0~1）。
    /// - 接受预算好的 rms，避免重复计算
    /// - 用等间隔采样覆盖完整缓冲区，避免大 buffer 时只分析前段
    func score(buffer: AVAudioPCMBuffer, rms: Float, minimumRMS: Float) -> Float {
        guard rms >= minimumRMS,
              let setup = fftSetup,
              let raw   = buffer.floatChannelData?[0] else { return 0 }

        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }

        // 等间隔采样：stride > 1 时覆盖完整缓冲区
        // 例如 buffer=8192, fftSize=4096 → stride=2, 覆盖全部样本（等效 22050 Hz）
        // 例如 buffer=4096, fftSize=4096 → stride=1, 直接使用（44100 Hz）
        let stride   = max(1, n / fftSize)
        let copyLen  = min(n / stride, fftSize)

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
        // Start from snoreLo instead of bin 1: exclude sub-bass (0–80 Hz) which captures
        // HVAC/road rumble and would otherwise inflate totalE and suppress the snore score.
        let totalE = bandSum(snoreLo, highHi)
        guard totalE > 0 else { return 0 }

        // 去掉高频惩罚：打鼾本身泛音延伸至 1 kHz+，惩罚项会系统性压低真实打鼾得分
        // 用纯比值：80–800 Hz 能量占 80–6000 Hz 总能量的比例
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

    var minimumRMS:          Float        = 0.003
    var snoreScoreThreshold: Float        = 0.12
    var confirmDelay:        TimeInterval = 1.0
    var silenceDelay:        TimeInterval = 5.0

    private var audioEngine   = AVAudioEngine()
    private var recordingFile: AVAudioFile?
    private var isRecording   = false
    private var detector:     SnoringDetector?
    private var confirmTimer: Timer?
    private var silenceTimer: Timer?

    private let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    // audio 线程私有
    private var lastIsLoud:   Bool  = false
    private var smoothLevel:  Float = 0
    private var recordBuffer: AVAudioPCMBuffer?

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
            // .measurement 关闭 AGC：静默时 RMS 真的降到 0，onSilent() 能正确触发。
            // .default 开启 AGC：静默时系统拉高环境噪音增益，RMS 始终偏高，停鼾检测失效。
            // 录音音量小的问题由 writeAmplified() 在写文件时放大解决，不依赖 AGC。
            try s.setCategory(.playAndRecord, mode: .measurement,
                              options: [.allowBluetoothHFP, .mixWithOthers])
            // 请求 16000 Hz：呼噜检测关注 80–6000 Hz，16000 Hz Nyquist 足够
            // 若硬件不支持则系统自动回退，不影响检测正确性
            try s.setPreferredSampleRate(16000)
            // 100ms IO 缓冲：~10 次/秒唤醒，UI 流畅且后台 CPU 压力低
            try s.setPreferredIOBufferDuration(0.1)
            try s.setActive(true)
        } catch {
            onError?("音频会话失败: \(error.localizedDescription)"); return
        }

        audioEngine = AVAudioEngine()
        let input   = audioEngine.inputNode
        let format  = input.outputFormat(forBus: 0)
        detector     = SnoringDetector(sampleRate: Float(format.sampleRate))
        lastIsLoud   = false
        smoothLevel  = 0
        recordBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)

        // bufferSize 2048：~100ms/次（16kHz），与 preferredIOBufferDuration 匹配
        // score() 内部用等间隔采样覆盖完整缓冲区，大小变化不影响检测精度
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buf, _ in
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
            writeAmplified(buffer: buffer, to: file)
        }

        // RMS 计算一次，同时用于 FFT 门控和 UI 平滑
        var rms: Float = 0
        if let data = buffer.floatChannelData?[0] {
            vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        }

        let score   = detector?.score(buffer: buffer, rms: rms, minimumRMS: minimumRMS) ?? 0
        let isLoud  = score >= snoreScoreThreshold
        let changed = isLoud != lastIsLoud
        lastIsLoud  = isLoud

        // 上升：直接取 rms，环立即跟上声音
        // 下降：α=0.2 缓慢衰减，视觉余韵自然
        smoothLevel = rms > smoothLevel ? rms : 0.2 * rms + 0.8 * smoothLevel
        let level   = smoothLevel

        DispatchQueue.main.async { [weak self, isLoud, changed, level] in
            guard let self else { return }
            self.currentLevel = level
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
        print("[SM] onLoud — isSnoring=\(isSnoring) confirmTimer=\(confirmTimer != nil)")
    }

    private func onSilent() {
        confirmTimer?.invalidate(); confirmTimer = nil
        if isSnoring && silenceTimer == nil {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDelay, repeats: false) { [weak self] _ in
                self?.silenceTimer = nil; self?.endSnoring()
            }
        }
        print("[SM] onSilent — isSnoring=\(isSnoring) silenceTimer=\(silenceTimer != nil)")
    }

    private func beginSnoring() {
        print("[SM] beginSnoring — isSnoring=\(isSnoring)")
        guard !isSnoring else { return }
        isSnoring = true
        if let filename = startRecording() { onSnoringStarted?(filename) }
    }

    private func endSnoring() {
        print("[SM] endSnoring — isSnoring=\(isSnoring)")
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

    // .measurement 模式无 AGC，原始信号弱，写文件前放大供回放使用；检测路径不受影响
    private func writeAmplified(buffer: AVAudioPCMBuffer, to file: AVAudioFile) {
        guard let src = buffer.floatChannelData?[0],
              let rec = recordBuffer,
              let dst = rec.floatChannelData?[0] else {
            try? file.write(from: buffer); return
        }
        let n = vDSP_Length(buffer.frameLength)
        rec.frameLength = buffer.frameLength
        var gain: Float = 12.0
        vDSP_vsmul(src, 1, &gain, dst, 1, n)
        var lo: Float = -1.0, hi: Float = 1.0
        vDSP_vclip(dst, 1, &lo, &hi, dst, 1, n)
        try? file.write(from: rec)
    }
}
