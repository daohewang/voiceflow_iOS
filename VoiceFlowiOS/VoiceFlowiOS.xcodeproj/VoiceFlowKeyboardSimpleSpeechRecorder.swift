/**
 * [INPUT]: 依赖 Speech 框架
 * [OUTPUT]: 对外提供 SimpleSpeechRecorder，使用 SFSpeechRecognizer 设备录音
 * [POS]: VoiceFlowKeyboard Extension 的简化录音方案
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 *
 * 说明：
 *   使用 SFSpeechRecognizer 的设备识别模式
 *   系统自动处理麦克风访问，避免 AVAudioSession 权限问题
 *   适用于键盘扩展等受限环境
 */

import Foundation
import Speech
import AVFoundation

// ========================================
// MARK: - Simple Speech Recorder
// ========================================

@MainActor
final class SimpleSpeechRecorder {
    
    // ----------------------------------------
    // MARK: - Callbacks
    // ----------------------------------------
    
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    
    // ----------------------------------------
    // MARK: - State
    // ----------------------------------------
    
    private(set) var isRecording = false
    
    // ----------------------------------------
    // MARK: - Private Components
    // ----------------------------------------
    
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    
    // ----------------------------------------
    // MARK: - Public API
    // ----------------------------------------
    
    /// 开始录音并识别
    func startRecording(locale: Locale = Locale(identifier: "zh-CN")) async throws {
        guard !isRecording else { return }
        
        // 检查权限
        let authStatus = await requestAuthorization()
        guard authStatus == .authorized else {
            throw RecorderError.authorizationDenied
        }
        
        // 初始化识别器
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw RecorderError.recognizerUnavailable
        }
        self.recognizer = recognizer
        
        // 创建识别请求
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        self.recognitionRequest = request
        
        // 创建音频引擎
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // 安装音频采样
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            // 计算音量
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frames {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(frames))
                Task { @MainActor [weak self] in
                    self?.onAudioLevel?(min(1.0, rms * 10))
                }
            }
        }
        
        // 启动引擎
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecorderError.engineStartFailed(error)
        }
        
        self.audioEngine = engine
        self.isRecording = true
        
        // 启动识别任务
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            
            if let error = error {
                Task { @MainActor in
                    self.onError?(error)
                }
                return
            }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    if result.isFinal {
                        self.onFinalResult?(text)
                    } else {
                        self.onPartialResult?(text)
                    }
                }
            }
        }
    }
    
    /// 停止录音
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognizer = nil
        isRecording = false
    }
    
    // ----------------------------------------
    // MARK: - Authorization
    // ----------------------------------------
    
    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        
        if currentStatus == .notDetermined {
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
        
        return currentStatus
    }
}

// ========================================
// MARK: - Recorder Error
// ========================================

enum RecorderError: LocalizedError {
    case authorizationDenied
    case recognizerUnavailable
    case engineStartFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "需要语音识别权限"
        case .recognizerUnavailable:
            return "语音识别服务不可用"
        case .engineStartFailed(let error):
            return "录音启动失败: \(error.localizedDescription)"
        }
    }
}
