/**
 * [INPUT]: 依赖 AVFoundation 的 AVAudioEngine/AVAudioConverter/AVAudioSession
 * [OUTPUT]: 对外提供 AudioEngine 类，音频采集 + 格式转换 + 音量级别回调
 * [POS]: VoiceFlowiOS/Core 的音频层，被 RecordingCoordinator 消费
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation
@preconcurrency import AVFoundation

// ========================================
// MARK: - Audio Engine (iOS)
// ========================================

/// iOS 音频采集引擎
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

    private var engine: AVAudioEngine?
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

        // iOS 必须配置 AVAudioSession
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // 先停用旧的 session（如果有）
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            
            // 配置音频会话
            try audioSession.setCategory(
                .playAndRecord,  // 改为 playAndRecord 以支持更多场景
                mode: .default,   // 使用默认模式而非 measurement
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            
            // 激活音频会话
            try audioSession.setActive(true, options: [])
            
            print("[AudioEngine] AVAudioSession configured successfully")
        } catch {
            print("[AudioEngine] AVAudioSession error: \(error)")
            throw AudioError.audioSessionFailed(error)
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = Self.targetFormat
        
        print("[AudioEngine] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("[AudioEngine] Failed to create audio converter")
            throw AudioError.invalidFormat
        }
        newConverter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Normal
        newConverter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
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

        self.engine = engine
        self.converter = newConverter
        self.isRecording = true

        print("[AudioEngine] Recording started - Input: \(inputFormat.sampleRate)Hz → 16kHz/16bit/mono")
    }

    func stopRecording() {
        guard isRecording, let engine = engine else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // 释放 AVAudioSession
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        self.engine = nil
        self.converter = nil
        self.isRecording = false

        flushBuffer()
        print("[AudioEngine] Recording stopped")
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
