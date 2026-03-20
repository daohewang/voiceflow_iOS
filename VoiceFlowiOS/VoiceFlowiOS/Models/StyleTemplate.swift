/**
 * [INPUT]: 依赖 Foundation 框架
 * [OUTPUT]: 对外提供 StyleTemplate 模型、预定义模板、StyleTemplateStore
 * [POS]: VoiceFlowiOS 的风格模板系统，被 DictionaryView 和 AppState 消费
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - Style Template Model
// ========================================

struct StyleTemplate: Identifiable, Codable, Equatable {

    let id: String
    var name: String
    var systemPrompt: String
    var temperature: Double
    var maxTokens: Int
    let isPredefined: Bool
    let createdAt: Date
    var updatedAt: Date

    mutating func touch() { updatedAt = Date() }

    init(
        id: String = UUID().uuidString,
        name: String,
        systemPrompt: String,
        temperature: Double = 0.7,
        maxTokens: Int = 500,
        isPredefined: Bool = false
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.isPredefined = isPredefined
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// ========================================
// MARK: - Predefined Templates
// ========================================

extension StyleTemplate {

    static var predefinedTemplates: [StyleTemplate] {
        [
            StyleTemplate(
                id: "default",
                name: "默认润色",
                systemPrompt: "你是一个专业的文字润色助手。请将用户输入的口语化文本改写为更加流畅、专业的书面语，保持原意不变。输出只包含润色后的文本，不要有任何解释。",
                temperature: 0.7, maxTokens: 500, isPredefined: true
            ),
            StyleTemplate(
                id: "formal",
                name: "正式商务",
                systemPrompt: "你是一个商务写作专家。请将用户输入的文本改写为正式的商务语言，适合用于邮件、报告或官方文档。保持原意，使用得体的敬语和专业术语。输出只包含改写后的文本。",
                temperature: 0.5, maxTokens: 500, isPredefined: true
            ),
            StyleTemplate(
                id: "casual",
                name: "轻松日常",
                systemPrompt: "你是一个日常对话润色助手。请将用户输入的文本改写为更加自然、亲切的日常用语，适合社交媒体或朋友间的交流。保持轻松的语气。输出只包含改写后的文本。",
                temperature: 0.8, maxTokens: 500, isPredefined: true
            ),
            StyleTemplate(
                id: "concise",
                name: "简洁精炼",
                systemPrompt: "你是一个文字精简专家。请将用户输入的文本压缩为最简洁的表达，去除冗余，保留核心信息。输出只包含精简后的文本。",
                temperature: 0.6, maxTokens: 300, isPredefined: true
            ),
            StyleTemplate(
                id: "expand",
                name: "详细展开",
                systemPrompt: "你是一个内容扩展专家。请将用户输入的简短文本展开为更详细、更丰富的表达，添加必要的背景和细节。输出只包含展开后的文本。",
                temperature: 0.7, maxTokens: 800, isPredefined: true
            ),
            StyleTemplate(
                id: "translate-en",
                name: "翻译为英文",
                systemPrompt: "你是一个专业的中英翻译。请将用户输入的中文文本翻译为自然流畅的英文。输出只包含翻译后的英文文本。",
                temperature: 0.5, maxTokens: 500, isPredefined: true
            ),
            StyleTemplate(
                id: "translate-zh",
                name: "翻译为中文",
                systemPrompt: "你是一个专业的英中翻译。请将用户输入的英文文本翻译为自然流畅的中文。输出只包含翻译后的中文文本。",
                temperature: 0.5, maxTokens: 500, isPredefined: true
            ),
            StyleTemplate(
                id: "code-doc",
                name: "代码文档",
                systemPrompt: "你是一个技术文档专家。请将用户输入的技术描述或代码片段转换为清晰的文档格式，包含功能说明、参数描述和使用示例。输出只包含文档内容。",
                temperature: 0.4, maxTokens: 600, isPredefined: true
            )
        ]
    }
}

// ========================================
// MARK: - Template Store
// ========================================

@MainActor
@Observable
final class StyleTemplateStore {

    static let shared = StyleTemplateStore()

    private let defaults = UserDefaults.standard
    private let customTemplatesKey = "com.voiceflow.customTemplates"

    private(set) var templates: [StyleTemplate] = []

    private init() { loadTemplates() }

    // ----------------------------------------
    // MARK: - CRUD
    // ----------------------------------------

    private func loadTemplates() {
        var all: [StyleTemplate] = []
        if let data = defaults.data(forKey: customTemplatesKey),
           let custom = try? JSONDecoder().decode([StyleTemplate].self, from: data) {
            all.append(contentsOf: custom)
        }
        all.append(contentsOf: Self.predefinedTemplates)
        templates = all
    }

    func addTemplate(_ template: StyleTemplate) {
        var custom = loadCustomTemplates()
        custom.append(template)
        saveCustomTemplates(custom)
        loadTemplates()
    }

    func deleteTemplate(_ template: StyleTemplate) {
        guard !template.isPredefined else { return }
        var custom = loadCustomTemplates()
        custom.removeAll { $0.id == template.id }
        saveCustomTemplates(custom)
        loadTemplates()
    }

    func updateTemplate(_ template: StyleTemplate) {
        guard !template.isPredefined else { return }
        var custom = loadCustomTemplates()
        if let idx = custom.firstIndex(where: { $0.id == template.id }) {
            custom[idx] = template
        }
        saveCustomTemplates(custom)
        loadTemplates()
    }

    // ----------------------------------------
    // MARK: - Query
    // ----------------------------------------

    func template(byId id: String) -> StyleTemplate? {
        templates.first { $0.id == id }
    }

    var customTemplates: [StyleTemplate]      { templates.filter { !$0.isPredefined } }
    var predefinedTemplateList: [StyleTemplate] { templates.filter { $0.isPredefined } }

    // ----------------------------------------
    // MARK: - Private
    // ----------------------------------------

    private func loadCustomTemplates() -> [StyleTemplate] {
        guard let data = defaults.data(forKey: customTemplatesKey),
              let ts = try? JSONDecoder().decode([StyleTemplate].self, from: data)
        else { return [] }
        return ts
    }

    private func saveCustomTemplates(_ templates: [StyleTemplate]) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        defaults.set(data, forKey: customTemplatesKey)
    }

    static var predefinedTemplates: [StyleTemplate] { StyleTemplate.predefinedTemplates }
}
