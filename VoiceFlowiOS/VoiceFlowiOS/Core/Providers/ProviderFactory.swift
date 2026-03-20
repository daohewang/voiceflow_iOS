/**
 * [INPUT]: 依赖 LLMProvider、ASRProvider 协议及其实现
 * [OUTPUT]: 对外提供 ProviderFactory，创建提供商实例
 * [POS]: VoiceFlowiOS 的提供商工厂，支持运行时切换
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - Provider Factory
// ========================================

@MainActor
struct ProviderFactory {

    static func createLLMProvider(type: LLMProviderType) -> LLMProvider {
        switch type {
        case .openRouter: return OpenRouterProvider()
        case .deepSeek:   return DeepSeekProvider()
        case .miniMax:    return OpenRouterProvider() // Fallback
        case .zhiPu:      return OpenRouterProvider() // Fallback
        case .kimi:       return OpenRouterProvider() // Fallback
        }
    }
}

// ========================================
// MARK: - Provider Config
// ========================================

struct ProviderConfig: Codable {
    var llmProvider: LLMProviderType = .openRouter
    var asrProvider: ASRProviderType = .elevenLabs

    static let `default` = ProviderConfig()
}
