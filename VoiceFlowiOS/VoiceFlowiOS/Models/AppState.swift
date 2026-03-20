/**
 * [INPUT]: 依赖 SwiftUI、Foundation、RecordingCoordinator、UsageStats、StyleTemplateStore
 * [OUTPUT]: 对外提供 AppState 可观察全局状态，完整的录音状态机 + 历史记录 + 统计
 * [POS]: VoiceFlowiOS 的核心状态层，被所有视图消费，持有 RecordingCoordinator
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ========================================
// MARK: - App State
// ========================================

@MainActor
@Observable
final class AppState {

    // ----------------------------------------
    // MARK: - Singleton
    // ----------------------------------------

    static let shared = AppState()

    // ----------------------------------------
    // MARK: - Recording Status
    // ----------------------------------------

    enum RecordingStatus: Equatable {
        case idle
        case recording
        case processing
        case done
        case error(String)
    }

    var recordingStatus: RecordingStatus = .idle

    var isRecording: Bool {
        if case .recording = recordingStatus { return true }
        return false
    }

    /// VoiceFlow 开关（绑定到 MainToggleCard）
    var isVoiceFlowEnabled: Bool = false

    /// 从键盘触发的录音（用于显示"返回键盘"引导）
    var isKeyboardRecording: Bool = false

    // ----------------------------------------
    // MARK: - Text State
    // ----------------------------------------

    /// 实时 ASR 识别文字
    var asrText: String = ""

    /// AI 润色结果
    var llmText: String = ""

    /// 剪贴板复制 toast 触发
    var clipboardCopied: Bool = false

    /// 实时音量级别（0.0~1.0），供 UI 波形动画使用
    var audioLevel: Float = 0.0

    // ----------------------------------------
    // MARK: - History
    // ----------------------------------------

    var isHistoryEnabled: Bool = true
    var historyEntries: [HistoryEntry] = []

    // ----------------------------------------
    // MARK: - Stats（从 UsageStats 读取）
    // ----------------------------------------

    var totalDictationHours: Double {
        Double(UsageStats.shared.totalRecordingSeconds) / 3600.0
    }

    var totalWords: Int { UsageStats.shared.totalCharactersTyped }

    var savedHours: Double {
        Double(UsageStats.shared.savedMinutes) / 60.0
    }

    var averageSpeed: Int { 150 }

    // ----------------------------------------
    // MARK: - Settings
    // ----------------------------------------

    // App Group 共享存储，供 Keyboard Extension 读取服务商选择
    private var sharedUD: UserDefaults {
        UserDefaults(suiteName: "group.com.swordsmanye.voiceflow.ios") ?? UserDefaults.standard
    }

    var selectedStyleId: String {
        get { sharedUD.string(forKey: "selectedStyleId") ?? "default" }
        set { sharedUD.set(newValue, forKey: "selectedStyleId") }
    }

    var llmProviderType: LLMProviderType {
        get {
            let raw = sharedUD.string(forKey: "llmProvider") ?? "OpenRouter"
            return LLMProviderType(rawValue: raw) ?? .openRouter
        }
        set { sharedUD.set(newValue.rawValue, forKey: "llmProvider") }
    }

    var asrProviderType: ASRProviderType {
        get {
            let raw = sharedUD.string(forKey: "asrProvider") ?? "ElevenLabs"
            return ASRProviderType(rawValue: raw) ?? .elevenLabs
        }
        set { sharedUD.set(newValue.rawValue, forKey: "asrProvider") }
    }

    // ----------------------------------------
    // MARK: - Navigation
    // ----------------------------------------

    var selectedTab: TabItem = .home

    // ----------------------------------------
    // MARK: - Coordinator
    // ----------------------------------------

    private var coordinator: RecordingCoordinator?

    // ----------------------------------------
    // MARK: - Init
    // ----------------------------------------

    private init() {
        loadHistory()
        coordinator = RecordingCoordinator(appState: self)
    }

    // ----------------------------------------
    // MARK: - Recording Actions
    // ----------------------------------------

    func startRecording() async {
        await coordinator?.startRecording()
    }

    func stopRecording() async {
        await coordinator?.stopRecording()
    }

    func cancelRecording() {
        coordinator?.cancelRecording()
    }

    // ----------------------------------------
    // MARK: - History Management
    // ----------------------------------------

    func addHistoryEntry(asrText: String, finalText: String, durationSeconds: Int) {
        guard isHistoryEnabled else { return }
        let entry = HistoryEntry(
            id: UUID(),
            date: Date(),
            asrText: asrText,
            finalText: finalText,
            durationSeconds: durationSeconds
        )
        historyEntries.insert(entry, at: 0)
        if historyEntries.count > 100 { historyEntries.removeLast() }
        saveHistory()
    }

    func clearHistory() {
        historyEntries.removeAll()
        saveHistory()
    }

    // ----------------------------------------
    // MARK: - Private Persistence
    // ----------------------------------------

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "historyEntries"),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        historyEntries = entries
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(historyEntries) else { return }
        UserDefaults.standard.set(data, forKey: "historyEntries")
    }
}

// ========================================
// MARK: - Tab Item
// ========================================

enum TabItem: String, CaseIterable {
    case home       = "home"
    case history    = "history"
    case dictionary = "dictionary"
    case account    = "account"

    var title: String {
        switch self {
        case .home:       return "首页"
        case .history:    return "历史记录"
        case .dictionary: return "人设"
        case .account:    return "设置"
        }
    }

    var icon: String {
        switch self {
        case .home:       return "house.fill"
        case .history:    return "clock.arrow.circlepath"
        case .dictionary: return "person.crop.rectangle.fill"
        case .account:    return "gearshape.fill"
        }
    }
}
