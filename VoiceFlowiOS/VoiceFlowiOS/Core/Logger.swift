/**
 * [INPUT]: 依赖 Foundation 框架
 * [OUTPUT]: 对外提供 Logger 单例，写入调试日志到文件
 * [POS]: VoiceFlowiOS/Core 的调试日志系统，被 LLMClient 等组件使用
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - Logger
// ========================================

@MainActor
final class Logger: Sendable {

    static let shared = Logger()

    private let logFileURL: URL
    private let fileManager = FileManager.default
    private var logHandle: FileHandle?

    private init() {
        let logsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/VoiceFlow", isDirectory: true)

        try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logFileURL = logsDir.appendingPathComponent("debug.log")

        // 每次启动清空旧日志
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        logHandle = try? FileHandle(forWritingTo: logFileURL)
    }

    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullMessage = "[\(timestamp)] \(message)\n"
        guard let data = fullMessage.data(using: .utf8),
              let handle = logHandle else { return }
        handle.write(data)
    }

    func clear() {
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    func read() -> String {
        (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""
    }
}
