/**
 * [INPUT]: 依赖 Security 框架
 * [OUTPUT]: 对外提供 KeychainManager 单例，安全存储 API Keys
 * [POS]: VoiceFlowiOS/Core 的密钥管理层
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation
import Security

// ========================================
// MARK: - Keychain Manager
// ========================================

@MainActor
final class KeychainManager {
    
    // ----------------------------------------
    // MARK: - Singleton
    // ----------------------------------------
    
    static let shared = KeychainManager()
    
    // ----------------------------------------
    // MARK: - Keys
    // ----------------------------------------
    
    enum Key: String {
        case elevenLabs = "com.voiceflow.api.elevenlabs"
        case openRouter = "com.voiceflow.api.openrouter"
        case deepSeek = "com.voiceflow.api.deepseek"
    }
    
    // ----------------------------------------
    // MARK: - Service Identifier
    // ----------------------------------------
    
    private let serviceName = "com.swordsmanye.voiceflow.ios"
    
    private init() {}
    
    // ----------------------------------------
    // MARK: - Public API
    // ----------------------------------------
    
    /// 保存密钥到 Keychain
    func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingError
        }
        
        // 删除旧值
        try? delete(key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// 读取密钥
    func get(_ key: Key) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.retrievalFailed(status)
        }
        
        return value
    }
    
    /// 删除密钥
    func delete(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    /// 检查密钥是否存在
    func exists(_ key: Key) -> Bool {
        (try? get(key)) != nil
    }
}

// ========================================
// MARK: - Keychain Error
// ========================================

enum KeychainError: LocalizedError {
    case encodingError
    case saveFailed(OSStatus)
    case retrievalFailed(OSStatus)
    case deleteFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .encodingError:
            return "无法编码数据"
        case .saveFailed(let status):
            return "保存失败 (状态码: \(status))"
        case .retrievalFailed(let status):
            return "读取失败 (状态码: \(status))"
        case .deleteFailed(let status):
            return "删除失败 (状态码: \(status))"
        }
    }
}
