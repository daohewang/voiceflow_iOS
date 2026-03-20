/**
 * [INPUT]: 依赖 Foundation 框架、KeychainManager
 * [OUTPUT]: 对外提供 LLMProvider 协议、LLMProviderType 枚举
 * [POS]: VoiceFlowiOS 的 LLM 提供商抽象层，支持多提供商切换
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - LLM Provider Types
// ========================================

enum LLMProviderType: String, Codable, CaseIterable, Identifiable {
    case openRouter = "OpenRouter"
    case deepSeek   = "DeepSeek"
    case miniMax    = "MiniMax"
    case zhiPu      = "智谱"
    case kimi       = "Kimi"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var apiKeyName: String {
        switch self {
        case .openRouter: return "OpenRouter API Key"
        case .deepSeek:   return "DeepSeek API Key"
        case .miniMax:    return "MiniMax API Key"
        case .zhiPu:      return "智谱 API Key"
        case .kimi:       return "Kimi API Key"
        }
    }

    var keychainKey: KeychainManager.Key {
        switch self {
        case .openRouter: return .openRouter
        case .deepSeek:   return .deepSeek
        case .miniMax:    return .miniMax
        case .zhiPu:      return .zhiPu
        case .kimi:       return .kimi
        }
    }
}

// ========================================
// MARK: - LLM Provider Protocol
// ========================================

protocol LLMProvider: Sendable {
    var type: LLMProviderType { get }
    var name: String { get }

    func polishText(
        _ text: String,
        systemPrompt: String,
        apiKey: String
    ) async throws -> String
}

// ========================================
// MARK: - LLM Provider Error
// ========================================

enum LLMProviderError: LocalizedError {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case noData
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:          return "未配置 API Key"
        case .networkError(let e):    return "网络错误: \(e.localizedDescription)"
        case .invalidResponse:        return "无效的响应"
        case .apiError(let msg):      return "API 错误: \(msg)"
        case .noData:                 return "无返回数据"
        case .decodingError:          return "数据解析失败"
        }
    }
}
