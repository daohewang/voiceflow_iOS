/**
 * [INPUT]: 无外部依赖
 * [OUTPUT]: 对外提供 UsageStats 单例，使用统计数据管理
 * [POS]: VoiceFlowiOS/Core 的统计层，被 AppState 消费
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - Usage Stats
// ========================================

@MainActor
@Observable
final class UsageStats {

    // ----------------------------------------
    // MARK: - Singleton
    // ----------------------------------------

    static let shared = UsageStats()

    // ----------------------------------------
    // MARK: - Properties
    // ----------------------------------------

    /// 总录音次数
    private(set) var totalRecordings: Int = 0

    /// 总录音时长（秒）
    private(set) var totalRecordingSeconds: Int = 0

    /// 总输入字数
    private(set) var totalCharactersTyped: Int = 0

    /// 估算节省时间（分钟）
    /// 假设打字速度 60 字/分钟，说话速度 150 字/分钟
    var savedMinutes: Int {
        Int(Double(totalCharactersTyped) * 0.015)
    }

    var formattedRecordingTime: String {
        let minutes = totalRecordingSeconds / 60
        return minutes > 0 ? "\(minutes) 分钟" : "\(totalRecordingSeconds) 秒"
    }

    var formattedTimeSaved: String { "\(savedMinutes) 分钟" }

    // ----------------------------------------
    // MARK: - Storage Keys
    // ----------------------------------------

    private let defaults = UserDefaults.standard
    private enum Key: String {
        case totalRecordings      = "usage.totalRecordings"
        case totalRecordingSeconds = "usage.totalRecordingSeconds"
        case totalCharactersTyped  = "usage.totalCharactersTyped"
    }

    // ----------------------------------------
    // MARK: - Initialization
    // ----------------------------------------

    private init() { loadFromStorage() }

    // ----------------------------------------
    // MARK: - Public API
    // ----------------------------------------

    func recordSession(durationSeconds: Int, characterCount: Int) {
        totalRecordings += 1
        totalRecordingSeconds += durationSeconds
        totalCharactersTyped += characterCount
        saveToStorage()
    }

    func recordSession(characters: Int) {
        recordSession(durationSeconds: 30, characterCount: characters)
    }

    func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return minutes > 0 ? "\(minutes) 分钟" : "\(seconds) 秒"
    }

    // ----------------------------------------
    // MARK: - Private Helpers
    // ----------------------------------------

    private func loadFromStorage() {
        totalRecordings       = defaults.integer(forKey: Key.totalRecordings.rawValue)
        totalRecordingSeconds = defaults.integer(forKey: Key.totalRecordingSeconds.rawValue)
        totalCharactersTyped  = defaults.integer(forKey: Key.totalCharactersTyped.rawValue)
    }

    private func saveToStorage() {
        defaults.set(totalRecordings,       forKey: Key.totalRecordings.rawValue)
        defaults.set(totalRecordingSeconds, forKey: Key.totalRecordingSeconds.rawValue)
        defaults.set(totalCharactersTyped,  forKey: Key.totalCharactersTyped.rawValue)
    }
}
