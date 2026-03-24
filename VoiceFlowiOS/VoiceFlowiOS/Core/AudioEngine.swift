/**
 * [INPUT]: 依赖 AVFoundation 的 AVAudioEngine/AVAudioConverter/AVAudioSession
 * [OUTPUT]: 对外提供 AudioEngine 类，音频采集 + 格式转换 + 音量级别回调
 * [POS]: VoiceFlowiOS/Core 的音频层，被 RecordingCoordinator 消费
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 *
 * 架构说明：
 *   AVAudioEngine 实例在整个 App 生命周期内复用，避免每次录音创建/销毁
 *   导致的音频硬件冲突（OSStatus 560557684）。
 *   stopRecording 只移除 tap 和停止引擎，不销毁实例。
 *   startRecording 调用 reset() 后重新 install tap 和 start。
 */

import Foundation
@preconcurrency import AVFoundation

// ========================================
// MARK: - Audio Engine (iOS)
// ========================================

/// iOS 音频采集引擎（复用模式）
/// 职责：AVAudioSession 配置 → 麦克风采集 → 格式转换 → PCM 数据回调
/// 输入：系统默认采样率
/// 输出：16kHz / 16-bit / Mono PCM，每 100ms 回调一次
final class AudioEngine: @unchecked Sendable {

    // ----------------------------------------
    // MARK: - Configuration
    // ----------------------------------------

    static let targetFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    static let callbackInterval: TimeInterval = 0.1

    // ----------------------------------------
    // MARK: - Properties
    // ----------------------------------------

    /// AVAudioEngine 实例（优先复用，启动失败时自愈重建）
    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?

    var onAudioData: ((Data) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    private(set) var isRecording = false
    private(set) var currentLevel: Float = 0.0

    // ----------------------------------------
    // MARK: - Buffer Management
    // ----------------------------------------

    private var accumulatedBuffer: Data = Data()
    private let bufferLock = NSLock()
    // 16kHz * 16bit(2bytes) * mono * 0.1s = 3200 bytes
    private let targetBytesPerCallback = Int(16000 * 2 * 1 * 0.1)

    // ----------------------------------------
    // MARK: - Lifecycle
    // ----------------------------------------

    init() {}

    deinit { stopRecording() }

    // ----------------------------------------
    // MARK: - Recording Control
    // ----------------------------------------

    func startRecording() throws {
        guard !isRecording else { return }

        // 如果引擎还在运行，说明是连续录音模式（避免 2003329396 后台启动报错）
        if engine.isRunning {
            print("[AudioEngine] Engine is already running (continuous mode). Resuming logical capture.")
            self.isRecording = true
            return
        }
        
        // 仅在引擎彻底停止时才重新初始化
        engine = AVAudioEngine()

        // AVAudioSession category 已在 VoiceFlowiOSApp.init() 中预配置，
        // 此处不再重复 setCategory — 避免与 KeepAlive 冲突导致 '!int' (560557684)。
        // 但必须调用 setActive(true) — iOS 后台可能挂起 session，
        // 不重新激活则 engine.start() 会报 'what' (2003329396)。
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            print("[AudioEngine] AVAudioSession re-activated")
        } catch {
            print("[AudioEngine] AVAudioSession re-activate failed: \(error)")
            // Do not throw immediately, allow fallback rebuilding.
        }

        bufferLock.lock()
        accumulatedBuffer.removeAll()
        bufferLock.unlock()

        // 尝试配置并启动引擎
        do {
            try configureAndStartEngine()
        } catch {
            print("[AudioEngine] First start failed (\(error)), waiting 100ms and recreating engine...")
            // Fallback: asynchronous 100ms cool-down buffer if hardware is stuck
            Thread.sleep(forTimeInterval: 0.1)
            engine = AVAudioEngine()
            try configureAndStartEngine()
        }

        self.isRecording = true
    }

    // ----------------------------------------
    // MARK: - Engine Setup (可重试)
    // ----------------------------------------

    /// 重置引擎 → 获取硬件格式 → 安装 tap → 启动
    private func configureAndStartEngine() throws {
        engine.reset()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = Self.targetFormat

        print("[AudioEngine] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("[AudioEngine] ❌ Invalid input format: \(inputFormat)")
            throw AudioError.invalidFormat
        }

        guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("[AudioEngine] Failed to create audio converter")
            throw AudioError.invalidFormat
        }
        newConverter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Normal
        newConverter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
        self.converter = newConverter

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            // MUTE LOGIC: If we are not logically recording, we just drop the buffer to keep the hardware alive!
            guard self.isRecording else { return }
            self.processBuffer(buffer, converter: converter)
        }

        do {
            try engine.start()
            print("[AudioEngine] Engine started successfully")
        } catch {
            inputNode.removeTap(onBus: 0)
            print("[AudioEngine] Engine start error: \(error)")
            throw AudioError.engineStartFailed
        }

        print("[AudioEngine] Recording started - \(inputFormat.sampleRate)Hz → 16kHz/16bit/mono")
    }

    func stopRecording() {
        guard isRecording else { return }

        // DO NOT stop the engine or remove the tap!
        // We must keep the hardware actively running 24/7 to maintain background mic privileges 
        // given by iOS when the app was previously in the foreground!
        // We only mute it logically.
        
        self.isRecording = false

        flushBuffer()
        print("[AudioEngine] Recording logically stopped (engine hardware KEPT RUNNING to retain privileges)")
    }

    // ----------------------------------------
    // MARK: - Audio Processing
    // ----------------------------------------

    private func processBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        let targetFormat = Self.targetFormat
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: targetFrameCount
        ) else { return }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if buffer.frameLength == 0 {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("[AudioEngine] Conversion error: \(error)")
            return
        }

        guard let channelData = outputBuffer.int16ChannelData else { return }
        let frameCount = Int(outputBuffer.frameLength)
        let byteCount = frameCount * 2

        // 计算 RMS 音量
        var sumSquares: Float = 0
        for i in 0..<frameCount {
            let sample = Float(channelData[0][i])
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(max(1, frameCount)))
        let normalizedLevel = min(1.0, rms / 32768.0)
        currentLevel = normalizedLevel
        onAudioLevel?(normalizedLevel)

        let data = Data(bytes: channelData[0], count: byteCount)
        appendToBuffer(data)
    }

    // ----------------------------------------
    // MARK: - Buffer Accumulation
    // ----------------------------------------

    private func appendToBuffer(_ data: Data) {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        accumulatedBuffer.append(data)
        while accumulatedBuffer.count >= targetBytesPerCallback {
            let chunk = accumulatedBuffer.prefix(targetBytesPerCallback)
            accumulatedBuffer = accumulatedBuffer.dropFirst(targetBytesPerCallback)
            onAudioData?(Data(chunk))
        }
    }

    private func flushBuffer() {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        if !accumulatedBuffer.isEmpty {
            onAudioData?(accumulatedBuffer)
            accumulatedBuffer.removeAll()
        }
    }
}

// ========================================
// MARK: - Error Types
// ========================================

enum AudioError: LocalizedError {
    case invalidFormat
    case engineStartFailed
    case permissionDenied
    case audioSessionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:      
            return "音频格式配置无效"
        case .engineStartFailed:  
            return "录音引擎启动失败"
        case .permissionDenied:   
            return "麦克风权限被拒绝"
        case .audioSessionFailed(let error):
            return "音频会话配置失败: \(error.localizedDescription)"
        }
    }
}
