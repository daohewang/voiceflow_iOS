/**
 * [INPUT]: 依赖 Foundation 框架
 * [OUTPUT]: 对外提供 HistoryEntry 数据模型
 * [POS]: VoiceFlowiOS/Models 的历史记录条目，被 AppState 和 HistoryView 消费
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - History Entry
// ========================================

struct HistoryEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let asrText: String
    let finalText: String
    let durationSeconds: Int
}
