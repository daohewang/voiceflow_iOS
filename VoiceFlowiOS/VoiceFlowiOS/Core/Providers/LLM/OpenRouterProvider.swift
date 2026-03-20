/**
 * [INPUT]: 依赖 Foundation (URLSession)、LLMProvider 协议
 * [OUTPUT]: 对外提供 OpenRouterProvider 实现
 * [POS]: VoiceFlowiOS 的 OpenRouter LLM 提供商实现
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - OpenRouter Provider
// ========================================

struct OpenRouterProvider: LLMProvider {

    let type: LLMProviderType = .openRouter
    let name = "OpenRouter"

    private let apiBaseURL = "https://openrouter.ai/api/v1/chat/completions"
    private let model = "openai/gpt-4o"

    func polishText(
        _ text: String,
        systemPrompt: String,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMProviderError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: apiBaseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/voiceflow", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("VoiceFlow", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": text]
            ],
            "stream": false,
            "temperature": 0.7,
            "max_tokens": 2000
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw LLMProviderError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMProviderError.decodingError
        }

        return content
    }
}
