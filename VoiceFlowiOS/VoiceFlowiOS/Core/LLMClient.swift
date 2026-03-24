/**
 * [INPUT]: 依赖 Foundation (URLSession)、ProviderFactory、StyleTemplateStore
 * [OUTPUT]: 对外提供 LLMClient 单例，支持文本润色操作
 * [POS]: VoiceFlowiOS 的 LLM 中枢，被 RecordingCoordinator 调用进行文本润色
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - LLM Client
// ========================================

@MainActor
@Observable
final class LLMClient {

    static let shared = LLMClient()

    // ----------------------------------------
    // MARK: - State
    // ----------------------------------------

    private(set) var isStreaming: Bool = false

    /// 当前润色任务（用于真正取消网络请求）
    private var currentTask: Task<Void, Never>?

    // ----------------------------------------
    // MARK: - Callbacks
    // ----------------------------------------

    var onTextUpdate: ((String) -> Void)?
    var onComplete: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private init() {}

    // ----------------------------------------
    // MARK: - Public API
    // ----------------------------------------

    /// 润色文本（使用提供商系统）
    func polishText(_ text: String, style: String, apiKey: String, providerType: LLMProviderType = .openRouter) {
        guard !isStreaming else {
            print("[LLM] ⚠️ Already streaming, ignoring polishText call")
            return
        }
        guard !apiKey.isEmpty else {
            onError?(LLMError.missingAPIKey)
            return
        }

        isStreaming = true

        let systemPrompt = buildSystemPrompt(for: style)
        let logMsg = """
        ========== LLM Request ==========
        [Provider]: \(providerType.displayName)
        [Template ID]: \(style)
        [User Text]: \(text)
        =================================

        """
        Logger.shared.log(logMsg)

        let provider = ProviderFactory.createLLMProvider(type: providerType)
        print("[LLM] Sending request to \(providerType.displayName), text='\(text.prefix(50))...'")

        currentTask = Task { @MainActor [weak self] in
            do {
                let result = try await provider.polishText(text, systemPrompt: systemPrompt, apiKey: apiKey)
                guard !Task.isCancelled else { return }
                print("[LLM] ✅ Got result: '\(result.prefix(80))...'")
                self?.onComplete?(result)
                self?.isStreaming = false
            } catch {
                guard !Task.isCancelled else { return }
                print("[LLM] ❌ Error: \(error.localizedDescription)")
                self?.onError?(error)
                self?.isStreaming = false
            }
        }
    }

    /// 取消当前请求（真正终止飞行中的网络任务）
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isStreaming = false
        print("[LLM] 🛑 Stream cancelled")
    }

    // ----------------------------------------
    // MARK: - Private Helpers
    // ----------------------------------------

    private func buildSystemPrompt(for templateId: String) -> String {
        if let template = StyleTemplateStore.shared.template(byId: templateId) {
            return template.systemPrompt
        }
        return StyleTemplate.predefinedTemplates
            .first { $0.id == "default" }?
            .systemPrompt
            ?? "你是一个专业的文字润色助手。请将用户输入的口语化文本改写为更加流畅、专业的书面语，保持原意不变。输出只包含润色后的文本，不要有任何解释。"
    }
}

// ========================================
// MARK: - LLM Error
// ========================================

enum LLMError: LocalizedError {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case noData
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:         return "未配置 OpenRouter API Key"
        case .networkError(let e):   return "网络错误: \(e.localizedDescription)"
        case .invalidResponse:       return "无效的响应"
        case .apiError(let msg):     return "API 错误: \(msg)"
        case .noData:                return "无返回数据"
        case .decodingError:         return "数据解析失败"
        }
    }
}
