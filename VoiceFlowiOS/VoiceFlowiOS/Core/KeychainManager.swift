/**
 * [INPUT]: 依赖 Foundation (UserDefaults)
 * [OUTPUT]: 对外提供 KeychainManager 单例，存取 API Key
 * [POS]: VoiceFlowiOS/Core 的存储层，被 AppState 和 AccountView 消费
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - Keychain Manager (UserDefaults-based)
// ========================================

/// API Key 存储管理器
/// 职责：API Key 的持久化存储
@MainActor
final class KeychainManager {

    // ----------------------------------------
    // MARK: - Singleton
    // ----------------------------------------

    static let shared = KeychainManager()

    // App Group 共享存储，供 Keyboard Extension 读取相同的 API Key
    private let defaults = UserDefaults(suiteName: "group.com.swordsmanye.voiceflow.ios") ?? UserDefaults.standard
    private let prefix = "com.voiceflow."

    private init() {}

    // ----------------------------------------
    // MARK: - Keys
    // ----------------------------------------

    enum Key: String, Sendable, CaseIterable {
        case elevenLabs = "api.elevenlabs"
        case openRouter = "api.openrouter"
        case deepSeek   = "api.deepseek"
        case miniMax    = "api.minimax"
        case zhiPu      = "api.zhipu"
        case kimi       = "api.kimi"
        case openAI     = "api.openai"
    }

    // ----------------------------------------
    // MARK: - CRUD Operations
    // ----------------------------------------

    func set(_ value: String, for key: Key) throws {
        defaults.set(value, forKey: prefix + key.rawValue)
        defaults.synchronize()
    }

    func get(_ key: Key) throws -> String? {
        let value = defaults.string(forKey: prefix + key.rawValue)
        return value?.isEmpty == false ? value : nil
    }

    func delete(_ key: Key) throws {
        defaults.removeObject(forKey: prefix + key.rawValue)
        defaults.synchronize()
    }

    func update(_ value: String, for key: Key) throws {
        try set(value, for: key)
    }

    func exists(_ key: Key) -> Bool {
        guard let value = defaults.string(forKey: prefix + key.rawValue) else { return false }
        return !value.isEmpty
    }
}

// ========================================
// MARK: - Error Types
// ========================================

enum KeychainError: LocalizedError, Sendable {
    case writeFailed(Int)
    case readFailed(Int)
    case deleteFailed(Int)
    case updateFailed(Int)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .writeFailed(let s):  return "Storage write failed: \(s)"
        case .readFailed(let s):   return "Storage read failed: \(s)"
        case .deleteFailed(let s): return "Storage delete failed: \(s)"
        case .updateFailed(let s): return "Storage update failed: \(s)"
        case .invalidData:         return "Storage data is invalid"
        }
    }
}
