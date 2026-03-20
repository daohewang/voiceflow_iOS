/**
 * [INPUT]: 依赖 AudioEngine, LLMClient, AppState, KeychainManager, SharedFile
 * [OUTPUT]: 对外提供 RecordingCoordinator，编排完整的录音→转录→润色→剪贴板流程
 * [POS]: VoiceFlowiOS 的数据流中枢，被 AppState 持有并调用
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 *
 * 架构说明：
 *   录音在后台运行（UIBackgroundModes: audio），但 iOS 会杀死后台网络连接。
 *   因此采用"本地缓存 + 停止后转录"策略：
 *     1. 录音期间：AudioEngine 采集音频，PCM 数据缓存在内存
 *     2. 停止录音后：将缓存的 PCM 打包为 WAV，POST 到 ElevenLabs REST API
 *     3. 获取转录文本 → LLM 润色 → 写入共享文件通知键盘
 */

import Foundation
import UIKit

// ========================================
// MARK: - Recording Coordinator
// ========================================

@MainActor
@Observable
final class RecordingCoordinator {

    // ----------------------------------------
    // MARK: - Components
    // ----------------------------------------

    private var audioEngine: AudioEngine?

    // ----------------------------------------
    // MARK: - State
    // ----------------------------------------

    private(set) var isRecording: Bool = false
    private var currentSessionId: UUID = UUID()
    private var recordingStartTime: Date?
    private var lastAudioLevelShareTime: Date = .distantPast

    /// 音频 PCM 数据缓冲区（16kHz/16bit/mono）
    private var audioDataBuffer: [Data] = []

    // ----------------------------------------
    // MARK: - Init
    // ----------------------------------------

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // ----------------------------------------
    // MARK: - 开始录音
    // ----------------------------------------

    func startRecording() async {
        print("[RC] startRecording() called, isRecording=\(isRecording)")
        guard !isRecording else {
            print("[RC] ⚠️ Already recording, ignoring")
            return
        }

        // 验证麦克风权限
        let permManager = PermissionManager.shared
        permManager.checkMicrophoneStatus()
        print("[RC] Mic status: \(permManager.microphoneStatus)")
        if permManager.microphoneStatus != .granted {
            let granted = await permManager.requestMicrophone()
            guard granted else {
                print("[RC] ❌ Mic permission denied")
                appState.recordingStatus = .error("请在系统设置中开启麦克风权限")
                return
            }
        }

        // 验证 ElevenLabs API Key
        guard let _ = getAPIKey(.elevenLabs) else {
            print("[RC] ❌ No ElevenLabs API Key!")
            appState.recordingStatus = .error("请先在设置中配置 ElevenLabs API Key")
            return
        }
        print("[RC] ElevenLabs key found")

        let sessionId = UUID()
        currentSessionId = sessionId
        isRecording = true
        audioDataBuffer = []
        recordingStartTime = Date()
        appState.asrText = ""
        appState.llmText = ""
        appState.recordingStatus = .recording
        SharedStore.write("recordingState", "recording")

        print("[RC] Starting recording session: \(sessionId)")

        // 创建音频引擎
        let engine = AudioEngine()
        self.audioEngine = engine

        // 音频数据 → 本地缓存（不走网络，后台安全）
        engine.onAudioData = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.audioDataBuffer.append(data)
            }
        }

        // 音量回调 → 驱动 UI 波形 + 共享给键盘
        engine.onAudioLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appState.audioLevel = level
                self.shareAudioLevelThrottled(level)
            }
        }

        // 启动音频引擎
        do {
            try engine.startRecording()
            print("[RC] ✅ AudioEngine started")
        } catch {
            print("[RC] ❌ AudioEngine failed: \(error)")
            appState.recordingStatus = .error("录音启动失败: \(error.localizedDescription)")
            isRecording = false
            SharedStore.write("recordingState", "idle")
            cleanup()
        }
    }

    // ----------------------------------------
    // MARK: - 停止录音
    // ----------------------------------------

    func stopRecording() async {
        print("[RC] stopRecording called, isRecording=\(isRecording)")
        guard isRecording else {
            print("[RC] ⚠️ Not recording, ignoring stop")
            return
        }

        let sessionId = currentSessionId
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil

        // 停止音频采集
        audioEngine?.stopRecording()
        isRecording = false
        appState.recordingStatus = .processing
        SharedStore.write("recordingState", "processing")
        print("[RC] Audio stopped, buffered \(audioDataBuffer.count) chunks")

        // 合并 PCM 数据
        let pcmData = audioDataBuffer.reduce(Data()) { $0 + $1 }
        audioDataBuffer = []
        cleanup()

        guard !pcmData.isEmpty else {
            print("[RC] ❌ No audio data captured")
            appState.recordingStatus = .idle
            SharedStore.write("recordingState", "idle")
            return
        }

        print("[RC] PCM data: \(pcmData.count) bytes (\(String(format: "%.1f", Double(pcmData.count) / 32000))s)")

        // ElevenLabs REST API 转录
        guard let apiKey = getAPIKey(.elevenLabs) else {
            print("[RC] ❌ ElevenLabs key lost")
            appState.recordingStatus = .error("ElevenLabs API Key 丢失")
            SharedStore.write("recordingState", "idle")
            return
        }

        let wavData = createWAVData(from: pcmData)
        print("[RC] WAV created: \(wavData.count) bytes, sending to ElevenLabs REST API...")

        let asrText: String
        do {
            asrText = try await transcribeAudio(wavData, apiKey: apiKey)
            print("[RC] ✅ ASR result: '\(asrText.prefix(80))'")
        } catch {
            print("[RC] ❌ ASR failed: \(error.localizedDescription)")
            appState.recordingStatus = .error("语音识别失败: \(error.localizedDescription)")
            SharedStore.write("recordingState", "idle")
            return
        }

        let finalText = asrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else {
            print("[RC] No text recognized")
            appState.recordingStatus = .idle
            SharedStore.write("recordingState", "idle")
            return
        }

        appState.asrText = finalText

        guard currentSessionId == sessionId else {
            print("[RC] Session invalidated")
            return
        }

        let durationSecs = Int(duration)

        // LLM 润色
        let llmProviderType = appState.llmProviderType
        let llmKey = getAPIKey(llmProviderType.keychainKey)

        guard let llmApiKey = llmKey, !llmApiKey.isEmpty else {
            print("[RC] No LLM key, using raw ASR text")
            injectText(finalText, asrText: finalText, sessionId: sessionId, durationSeconds: durationSecs)
            return
        }

        print("[RC] LLM key found (\(llmProviderType.displayName)), polishing...")
        let llmClient = LLMClient.shared
        let styleId = appState.selectedStyleId

        llmClient.onTextUpdate = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, self.currentSessionId == sessionId else { return }
                self.appState.llmText = text
            }
        }

        llmClient.onComplete = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, self.currentSessionId == sessionId else { return }
                print("[RC] ✅ LLM complete: '\(text.prefix(80))'")
                self.injectText(text, asrText: finalText, sessionId: sessionId, durationSeconds: durationSecs)
            }
        }

        llmClient.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.currentSessionId == sessionId else { return }
                print("[RC] ⚠️ LLM error: \(error.localizedDescription), using raw text")
                self.injectText(finalText, asrText: finalText, sessionId: sessionId, durationSeconds: durationSecs)
            }
        }

        llmClient.polishText(finalText, style: styleId, apiKey: llmApiKey, providerType: llmProviderType)

        // 35 秒超时保护
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 35_000_000_000)
            guard let self, self.currentSessionId == sessionId else { return }
            if case .processing = self.appState.recordingStatus {
                print("[RC] ⚠️ LLM timeout, using raw text")
                llmClient.cancel()
                self.injectText(finalText, asrText: finalText, sessionId: sessionId, durationSeconds: durationSecs)
            }
        }
    }

    /// 取消录音
    func cancelRecording() {
        audioEngine?.stopRecording()
        LLMClient.shared.cancel()
        isRecording = false
        audioDataBuffer = []
        appState.recordingStatus = .idle
        appState.asrText = ""
        appState.llmText = ""
        SharedStore.write("recordingState", "idle")
        cleanup()
    }

    // ----------------------------------------
    // MARK: - ElevenLabs REST API 转录
    // ----------------------------------------

    /// POST 音频文件到 ElevenLabs REST API，返回转录文本
    private func transcribeAudio(_ wavData: Data, apiKey: String) async throws -> String {
        let boundary = UUID().uuidString
        let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        // 构建 multipart body
        var body = Data()

        // file 字段
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        body.append("\r\n")

        // model_id 字段
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n")
        body.append("scribe_v2\r\n")

        // 结束边界
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        print("[RC] POST \(url.absoluteString) (\(body.count) bytes)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ASRError.invalidResponse
        }

        print("[RC] ASR response: HTTP \(http.statusCode), \(data.count) bytes")

        guard http.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            print("[RC] ❌ ASR API error: \(errorBody)")
            throw ASRError.connectionFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            let body = String(data: data, encoding: .utf8) ?? "unparseable"
            print("[RC] ❌ ASR parse error: \(body)")
            throw ASRError.invalidResponse
        }

        return text
    }

    // ----------------------------------------
    // MARK: - WAV 文件创建
    // ----------------------------------------

    /// 将 16kHz/16bit/mono PCM 数据打包为 WAV 格式
    private func createWAVData(from pcmData: Data) -> Data {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)

        var header = Data(capacity: 44)
        header.append("RIFF")
        header.appendLE(36 + dataSize)
        header.append("WAVE")
        header.append("fmt ")
        header.appendLE(UInt32(16))     // fmt chunk size
        header.appendLE(UInt16(1))      // PCM format
        header.appendLE(channels)
        header.appendLE(sampleRate)
        header.appendLE(byteRate)
        header.appendLE(blockAlign)
        header.appendLE(bitsPerSample)
        header.append("data")
        header.appendLE(dataSize)

        return header + pcmData
    }

    // ----------------------------------------
    // MARK: - 文本注入（剪贴板 + 历史记录）
    // ----------------------------------------

    private func injectText(_ text: String, asrText: String, sessionId: UUID, durationSeconds: Int) {
        guard currentSessionId == sessionId else {
            print("[RC] ⚠️ Session invalidated, skipping inject")
            return
        }

        print("[RC] ✅ injectText: '\(text.prefix(80))'")

        // 键盘录音流程在后台运行，剪贴板不可用 → 跳过
        // 主 App 前台录音才复制到剪贴板
        if !appState.isKeyboardRecording {
            UIPasteboard.general.string = text
        }
        UsageStats.shared.recordSession(durationSeconds: max(1, durationSeconds), characterCount: text.count)
        appState.addHistoryEntry(asrText: asrText, finalText: text, durationSeconds: durationSeconds)

        appState.recordingStatus = .done
        appState.llmText = text
        appState.clipboardCopied = true
        SharedStore.write("recordingState", "done")

        // 3 秒后回到 idle
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.currentSessionId == sessionId else { return }
            self.appState.recordingStatus = .idle
            self.appState.clipboardCopied = false
        }

        cleanup()
    }

    // ----------------------------------------
    // MARK: - Helpers
    // ----------------------------------------

    private func getAPIKey(_ key: KeychainManager.Key) -> String? {
        guard let value = try? KeychainManager.shared.get(key), !value.isEmpty else { return nil }
        return value
    }

    /// 节流写入音量到共享文件（~150ms 间隔），供键盘波形动画消费
    private func shareAudioLevelThrottled(_ level: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastAudioLevelShareTime) >= 0.15 else { return }
        lastAudioLevelShareTime = now

        SharedStore.write("audioLevel", String(format: "%.3f", level))

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.swordsmanye.voiceflow.audioLevel" as CFString),
            nil, nil, true
        )
    }

    private func cleanup() {
        audioEngine = nil
    }
}

// ========================================
// MARK: - Data Extensions (WAV 构建辅助)
// ========================================

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
    mutating func appendLE(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
