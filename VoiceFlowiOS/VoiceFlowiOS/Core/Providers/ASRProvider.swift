/**
 * [INPUT]: 依赖 Foundation 框架、KeychainManager
 * [OUTPUT]: 对外提供 ASRProvider 协议、ASRProviderType 枚举
 * [POS]: VoiceFlowiOS 的 ASR 提供商抽象层，支持多提供商切换
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - ASR Provider Types
// ========================================

enum ASRProviderType: String, Codable, CaseIterable, Identifiable {
    case elevenLabs = "ElevenLabs"
    case deepSeek   = "DeepSeek"
    case openAI     = "OpenAI"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var apiKeyName: String {
        switch self {
        case .elevenLabs: return "ElevenLabs API Key"
        case .deepSeek:   return "DeepSeek API Key"
        case .openAI:     return "OpenAI API Key"
        }
    }

    var keychainKey: KeychainManager.Key {
        switch self {
        case .elevenLabs: return .elevenLabs
        case .deepSeek:   return .deepSeek
        case .openAI:     return .openAI
        }
    }
}

// ========================================
// MARK: - ASR Provider Protocol
// ========================================

protocol ASRProvider: Sendable {
    var type: ASRProviderType { get }
    var name: String { get }
    var isConnected: Bool { get }

    func connect(apiKey: String) async throws
    func sendAudioData(_ data: Data)
    func commit()
    func disconnect()
}

// ========================================
// MARK: - ASR Provider Delegate
// ========================================

protocol ASRProviderDelegate: AnyObject {
    func asrProvider(_ provider: ASRProvider, didReceivePartialTranscript text: String)
    func asrProvider(_ provider: ASRProvider, didReceiveFinalTranscript text: String)
    func asrProvider(_ provider: ASRProvider, didFailWithError error: Error)
    func asrProvider(_ provider: ASRProvider, didChangeConnectionState isConnected: Bool)
}

// ========================================
// MARK: - ASR Provider Error
// ========================================

enum ASRProviderError: LocalizedError {
    case missingAPIKey
    case connectionFailed(String)
    case disconnected
    case audioEncodingFailed
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:            return "未配置 API Key"
        case .connectionFailed(let r):  return "连接失败: \(r)"
        case .disconnected:             return "未连接"
        case .audioEncodingFailed:      return "音频编码失败"
        case .apiError(let msg):        return "API 错误: \(msg)"
        }
    }
}
