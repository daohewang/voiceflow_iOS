/**
 * [INPUT]: 依赖 Foundation 框架
 * [OUTPUT]: 对外提供 ProviderFactory 和 LLMProvider 协议
 * [POS]: VoiceFlowiOS/Core 的 LLM 提供商工厂
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - LLM Provider Protocol
// ========================================

protocol LLMProvider {
    func polishText(_ text: String, systemPrompt: String, apiKey: String) async throws -> String
}

// ========================================
// MARK: - Provider Factory
// ========================================

enum ProviderFactory {
    
    static func createLLMProvider(type: LLMProviderType) -> LLMProvider {
        switch type {
        case .openRouter:
            return OpenRouterProvider()
        case .deepSeek:
            return DeepSeekProvider()
        }
    }
}

// ========================================
// MARK: - OpenRouter Provider
// ========================================

private struct OpenRouterProvider: LLMProvider {
    
    func polishText(_ text: String, systemPrompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        
        let body: [String: Any] = [
            "model": "anthropic/claude-haiku-4-5-20251001",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 1024,
            "stream": false
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw LLMError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 30
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw LLMError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// ========================================
// MARK: - DeepSeek Provider
// ========================================

private struct DeepSeekProvider: LLMProvider {
    
    func polishText(_ text: String, systemPrompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.deepseek.com/v1/chat/completions")!
        
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 1024,
            "stream": false
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw LLMError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 30
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw LLMError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
