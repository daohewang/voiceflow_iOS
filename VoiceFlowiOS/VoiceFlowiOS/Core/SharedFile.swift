/**
 * [INPUT]: 依赖 Foundation FileManager
 * [OUTPUT]: 对外提供 SharedFile 静态方法，App Group 文件 I/O
 * [POS]: 跨进程数据共享基础设施，替代 UserDefaults（cfprefsd 在 Extension 中不可靠）
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ========================================
// MARK: - App Group 文件共享
// ========================================

/// 文件 I/O 替代 UserDefaults — cfprefsd 在键盘 Extension 进程中不可靠
/// 使用 FileManager.containerURL 获取共享容器，直接读写文件
enum SharedFile {

    private static let groupID = "group.com.swordsmanye.voiceflow.ios"

    private static func url(for key: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("vf_\(key).dat")
    }

    static func read(_ key: String) -> String? {
        guard let url = url(for: key) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String) {
        guard let url = url(for: key) else { return }
        try? value.write(to: url, atomically: true, encoding: .utf8)
    }

    static func remove(_ key: String) {
        guard let url = url(for: key) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
