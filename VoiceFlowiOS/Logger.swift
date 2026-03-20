/**
 * [INPUT]: 依赖 Foundation 框架
 * [OUTPUT]: 对外提供 Logger 单例，统一日志管理
 * [POS]: VoiceFlowiOS/Core 的日志层
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - Logger
// ========================================

@MainActor
final class Logger {
    
    // ----------------------------------------
    // MARK: - Singleton
    // ----------------------------------------
    
    static let shared = Logger()
    
    // ----------------------------------------
    // MARK: - Configuration
    // ----------------------------------------
    
    var isEnabled: Bool = true
    
    private init() {}
    
    // ----------------------------------------
    // MARK: - Public API
    // ----------------------------------------
    
    func log(_ message: String, level: LogLevel = .info) {
        guard isEnabled else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let prefix = level.emoji
        
        print("[\(timestamp)] \(prefix) \(message)")
    }
    
    func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    func info(_ message: String) {
        log(message, level: .info)
    }
    
    func warning(_ message: String) {
        log(message, level: .warning)
    }
    
    func error(_ message: String) {
        log(message, level: .error)
    }
    
    // ----------------------------------------
    // MARK: - Private
    // ----------------------------------------
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// ========================================
// MARK: - Log Level
// ========================================

enum LogLevel {
    case debug
    case info
    case warning
    case error
    
    var emoji: String {
        switch self {
        case .debug:   return "🔍"
        case .info:    return "ℹ️"
        case .warning: return "⚠️"
        case .error:   return "❌"
        }
    }
}
