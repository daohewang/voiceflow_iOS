/**
 * [INPUT]: 依赖 Foundation URLSessionWebSocketTask，依赖 AudioEngine
 * [OUTPUT]: 对外提供 ASRClient 类，WebSocket 连接管理 + 实时转录回调
 * [POS]: VoiceFlowiOS/Core 的语音识别层，消费 AudioEngine 数据，被 RecordingCoordinator 调用
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - ASR Client
// ========================================

/// ElevenLabs Scribe v2 WebSocket ASR 客户端
final class ASRClient: @unchecked Sendable {

    // ----------------------------------------
    // MARK: - Configuration
    // ----------------------------------------

    private let apiKey: String
    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0
    private var retryCount = 0
    private var isManuallyDisconnected = false

    // ----------------------------------------
    // MARK: - WebSocket
    // ----------------------------------------

    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession

    // ----------------------------------------
    // MARK: - State
    // ----------------------------------------

    private(set) var isConnected = false
    private var isReconnecting = false

    // ----------------------------------------
    // MARK: - Callbacks
    // ----------------------------------------

    var onTranscription: ((String, Bool) -> Void)?
    var onConnectionStateChange: ((Bool) -> Void)?
    var onError: ((Error) -> Void)?

    // ----------------------------------------
    // MARK: - Lifecycle
    // ----------------------------------------

    init(apiKey: String) {
        self.apiKey = apiKey
        self.session = URLSession.shared
    }

    deinit { disconnect() }

    // ----------------------------------------
    // MARK: - Connection Management
    // ----------------------------------------

    func connect() async throws {
        guard !isConnected else { return }

        isManuallyDisconnected = false
        let url = URL(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime?model_id=scribe_v2_realtime")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        try await Task.sleep(nanoseconds: 100_000_000) // 100ms 等待连接

        isConnected = true
        retryCount = 0
        onConnectionStateChange?(true)
        listenForMessages()

        print("[ASRClient] Connected to ElevenLabs Scribe v2")
    }

    func disconnect() {
        isManuallyDisconnected = true
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        onConnectionStateChange?(false)
        print("[ASRClient] Disconnected")
    }

    // ----------------------------------------
    // MARK: - Reconnection
    // ----------------------------------------

    private func reconnect() async {
        guard !isManuallyDisconnected && !isReconnecting && retryCount < maxRetries else {
            if !isManuallyDisconnected { onError?(ASRError.maxRetriesExceeded) }
            return
        }

        isReconnecting = true
        defer { isReconnecting = false }

        let delay = baseDelay * pow(2.0, Double(retryCount))
        retryCount += 1

        print("[ASRClient] Reconnecting in \(delay)s (attempt \(retryCount)/\(maxRetries))")
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        do {
            try await connect()
        } catch {
            print("[ASRClient] Reconnection failed: \(error)")
            await reconnect()
        }
    }

    // ----------------------------------------
    // MARK: - Audio Streaming
    // ----------------------------------------

    /// 发送音频数据（binary PCM 帧）
    /// ElevenLabs STT Realtime API 接收 raw PCM binary frames（16kHz/16bit/mono）
    /// 不接受 base64 JSON，服务端收到 JSON text frame 会立即关闭连接（Code=57）
    func sendAudioData(_ data: Data) {
        guard isConnected, let task = webSocketTask else { return }
        task.send(.data(data)) { error in
            if let error = error { print("[ASRClient] Send error: \(error)") }
        }
    }

    /// 发送 commit 信号，强制服务器输出最后一段
    func commit() {
        guard isConnected, let task = webSocketTask else { return }
        task.send(.string("{\"commit\":true}")) { error in
            if let error = error {
                print("[ASRClient] Commit error: \(error)")
            } else {
                print("[ASRClient] Commit signal sent")
            }
        }
    }

    // ----------------------------------------
    // MARK: - Message Handling
    // ----------------------------------------

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.listenForMessages()
            case .failure(let error):
                print("[ASRClient] Receive error: \(error)")
                self.isConnected = false
                self.onConnectionStateChange?(false)
                Task { await self.reconnect() }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):   parseTranscriptionResponse(data)
        case .string(let text):
            guard let data = text.data(using: .utf8) else { return }
            parseTranscriptionResponse(data)
        @unknown default: break
        }
    }

    private func parseTranscriptionResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageType = json["message_type"] as? String else { return }

        switch messageType {
        case "partial_transcript":
            guard let text = json["text"] as? String else { return }
            onTranscription?(text, false)

        case "committed_transcript":
            guard let text = json["text"] as? String else { return }
            onTranscription?(text, true)

        case "session_started":
            print("[ASRClient] Session started: \(json["session_id"] ?? "unknown")")

        case "auth_error":
            print("[ASRClient] Auth error - check API key and Realtime STT subscription")
            isManuallyDisconnected = true
            onError?(ASRError.unauthorized)
            disconnect()

        default:
            print("[ASRClient] Unknown message_type: \(messageType)")
        }
    }
}

// ========================================
// MARK: - Error Types
// ========================================

enum ASRError: LocalizedError {
    case connectionFailed
    case maxRetriesExceeded
    case invalidResponse
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .connectionFailed:    return "Failed to connect to ASR service"
        case .maxRetriesExceeded:  return "Max reconnection attempts exceeded"
        case .invalidResponse:     return "Invalid response from ASR service"
        case .unauthorized:        return "Invalid API key"
        }
    }
}
