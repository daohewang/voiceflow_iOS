/**
 * [INPUT]: 无外部依赖
 * [OUTPUT]: 对外提供 LLMProviderType、ASRProviderType 枚举
 * [POS]: VoiceFlowiOS/Models 的服务商类型定义
 * [PROTOCOL]: 变更时更新此头部,然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - LLM Provider Type
// ========================================

enum LLMProviderType: String, Codable, CaseIterable {
    case openRouter = "OpenRouter"
    case deepSeek = "DeepSeek"
    
    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .deepSeek: return "DeepSeek"
        }
    }
    
    var keychainKey: KeychainManager.Key {
        switch self {
        case .openRouter: return .openRouter
        case .deepSeek: return .deepSeek
        }
    }
}

// ========================================
// MARK: - ASR Provider Type
// ========================================

enum ASRProviderType: String, Codable, CaseIterable {
    case elevenLabs = "ElevenLabs"
    
    var displayName: String {
        switch self {
        case .elevenLabs: return "ElevenLabs"
        }
    }
    
    var keychainKey: KeychainManager.Key {
        switch self {
        case .elevenLabs: return .elevenLabs
        }
    }
}
