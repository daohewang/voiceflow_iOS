/**
 * [INPUT]: 依赖 Speech 框架
 * [OUTPUT]: 对外提供 KeyboardViewModel，极简录音方案
 * [POS]: VoiceFlowKeyboard Extension 的状态层
 * [PROTOCOL]: 使用最简单的 SFSpeechRecognizer 录音方案
 */

import Foundation
import Speech
import AVFoundation
import UIKit

// ========================================
// MARK: - Keyboard View Model (简化版)
// ========================================

@MainActor
@Observable
final class KeyboardViewModel {

    weak var inputVC: UIInputViewController?

    // ----------------------------------------
    // MARK: - State
    // ----------------------------------------

    enum RecordState: Equatable { case idle, recording, processing }

    var recordState: RecordState = .idle
    var displayText: String = ""
    var audioLevel: Float = 0.0
    var errorMsg: String? = nil

    // ----------------------------------------
    // MARK: - Private
    // ----------------------------------------

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var levelTimer: Timer?

    // ----------------------------------------
    // MARK: - Init
    // ----------------------------------------

    init(inputVC: UIInputViewController) {
        self.inputVC = inputVC
    }

    // ----------------------------------------
    // MARK: - Public Actions
    // ----------------------------------------

    func toggleRecording() {
        switch recordState {
        case .idle:       Task { await startRecording() }
        case .recording:  Task { await stopAndProcess() }
        case .processing: break
        }
    }

    func switchKeyboard() { inputVC?.advanceToNextInputMode() }
    func deleteBackward() { inputVC?.textDocumentProxy.deleteBackward() }
    func insertNewline()  { inputVC?.textDocumentProxy.insertText("\n") }

    // ----------------------------------------
    // MARK: - Start Recording
    // ----------------------------------------

    private func startRecording() async {
        displayText = ""
        errorMsg = nil

        print("[KeyboardVM] ========== 开始录音 ==========")
        
        // 检查完全访问权限
        guard inputVC?.hasFullAccess == true else {
            errorMsg = "请在「设置→通用→键盘→VoiceFlow」中开启「允许完全访问」"
            print("[KeyboardVM] ❌ 缺少完全访问权限")
            return
        }
        print("[KeyboardVM] ✅ 完全访问权限: 已开启")

        // 检查语音识别权限
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        print("[KeyboardVM] 语音识别权限状态: \(authStatus.rawValue)")
        
        if authStatus != .authorized {
            // 尝试请求权限
            let newStatus = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
            print("[KeyboardVM] 请求后权限状态: \(newStatus.rawValue)")
            
            guard newStatus == .authorized else {
                errorMsg = "需要语音识别权限\n请到主 App 的设置页面查看权限状态"
                print("[KeyboardVM] ❌ 语音识别权限被拒绝")
                return
            }
        }
        print("[KeyboardVM] ✅ 语音识别权限: 已授权")

        // 初始化识别器
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else {
            errorMsg = "语音识别服务不可用\n请检查网络连接"
            print("[KeyboardVM] ❌ 语音识别服务不可用")
            return
        }
        self.speechRecognizer = recognizer
        print("[KeyboardVM] ✅ 语音识别器初始化成功")

        // 创建识别请求
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request
        print("[KeyboardVM] ✅ 识别请求创建成功")

        // 创建音频引擎
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        print("[KeyboardVM] 音频格式: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")

        // 安装音频 tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            // 简单的音量计算
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<min(frames, 100) {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(min(frames, 100)))
                
                DispatchQueue.main.async {
                    self?.audioLevel = min(1.0, rms * 15)
                }
            }
        }
        print("[KeyboardVM] ✅ 音频 tap 安装成功")

        // 启动音频引擎
        do {
            try engine.start()
            print("[KeyboardVM] ✅ 音频引擎启动成功")
        } catch {
            inputNode.removeTap(onBus: 0)
            errorMsg = "无法启动录音\n\(error.localizedDescription)"
            print("[KeyboardVM] ❌ 音频引擎启动失败: \(error)")
            return
        }

        self.audioEngine = engine
        recordState = .recording

        // 启动识别任务
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            
            if let error = error {
                print("[KeyboardVM] 识别错误: \(error)")
                DispatchQueue.main.async {
                    if self.recordState == .recording {
                        self.errorMsg = "识别出错"
                    }
                }
                return
            }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.displayText = text
                }
                
                if result.isFinal {
                    print("[KeyboardVM] 识别完成: \(text)")
                }
            }
        }
        
        print("[KeyboardVM] ✅ 识别任务启动成功")
        print("[KeyboardVM] 🎤 正在录音...")
    }

    // ----------------------------------------
    // MARK: - Stop + Process
    // ----------------------------------------

    private func stopAndProcess() async {
        print("[KeyboardVM] ========== 停止录音 ==========")
        
        audioLevel = 0
        levelTimer?.invalidate()
        levelTimer = nil

        // 停止音频引擎
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        print("[KeyboardVM] ✅ 音频引擎已停止")

        // 结束识别请求
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // 等待最终结果
        try? await Task.sleep(nanoseconds: 500_000_000)

        // 清理识别任务
        recognitionTask?.cancel()
        recognitionTask = nil
        speechRecognizer = nil

        recordState = .processing

        let text = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[KeyboardVM] 最终文本: \(text)")
        
        guard !text.isEmpty else {
            recordState = .idle
            errorMsg = "未识别到语音，请重试"
            print("[KeyboardVM] ⚠️ 没有识别到内容")
            return
        }

        // 检查是否需要 LLM 润色
        if let llmKey = activeLLMKey(), let provider = activeLLMProvider(), !llmKey.isEmpty {
            print("[KeyboardVM] 开始 LLM 润色...")
            await polishAndInsert(text: text, apiKey: llmKey, providerType: provider)
        } else {
            print("[KeyboardVM] 直接插入文本（无 LLM）")
            finalInsert(text)
        }
    }

    // ----------------------------------------
    // MARK: - LLM Polish
    // ----------------------------------------

    private func polishAndInsert(text: String, apiKey: String, providerType: String) async {
        let (url, model): (URL, String) = providerType == "DeepSeek"
            ? (URL(string: "https://api.deepseek.com/v1/chat/completions")!, "deepseek-chat")
            : (URL(string: "https://openrouter.ai/api/v1/chat/completions")!, "anthropic/claude-3-5-haiku-20241022")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你是一个文字润色助手。将口语化的语音识别文字转换为书面、流畅的文字，保持原意，直接输出结果，不要解释。"],
                ["role": "user", "content": text]
            ],
            "max_tokens": 1024,
            "stream": false
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            finalInsert(text)
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData
        req.timeoutInterval = 20

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String, !content.isEmpty {
                print("[KeyboardVM] LLM 润色完成")
                finalInsert(content.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                print("[KeyboardVM] LLM 响应格式错误，使用原文")
                finalInsert(text)
            }
        } catch {
            print("[KeyboardVM] LLM 请求失败: \(error)")
            finalInsert(text)
        }
    }

    private func finalInsert(_ text: String) {
        inputVC?.textDocumentProxy.insertText(text)
        displayText = text
        recordState = .idle
        print("[KeyboardVM] ✅ 文本已插入")
        print("[KeyboardVM] ========== 录音流程结束 ==========\n")
    }

    // ----------------------------------------
    // MARK: - App Group Storage
    // ----------------------------------------

    private func sharedKey(_ key: String) -> String? {
        let v = UserDefaults(suiteName: "group.com.swordsmanye.voiceflow.ios")?.string(forKey: key)
        return v?.isEmpty == false ? v : nil
    }

    private func activeLLMProvider() -> String? {
        sharedKey("llmProvider")
    }

    private func activeLLMKey() -> String? {
        let provider = activeLLMProvider() ?? "OpenRouter"
        if provider == "DeepSeek" {
            return sharedKey("com.voiceflow.api.deepseek")
        }
        return sharedKey("com.voiceflow.api.openrouter")
    }
}
