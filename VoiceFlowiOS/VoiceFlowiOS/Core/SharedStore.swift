/**
 * [INPUT]: 依赖 Foundation (FileManager + App Group 容器)
 * [OUTPUT]: 对外提供 SharedStore 静态方法，跨进程数据读写
 * [POS]: 主 App 与键盘 Extension 的数据桥梁，App Group 文件共享
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 *
 * 架构说明：
 *   通过 App Group 共享容器目录的文件读写实现跨进程通信。
 *   比 UserDefaults(suiteName:) 更可靠（不受 cfprefsd 限制）。
 *   比 Keychain 更轻量，无需额外 capability 配置。
 */

import Foundation

// ========================================
// MARK: - App Group 文件共享
// ========================================

enum SharedStore {

    private static let groupID = "group.com.swordsmanye.voiceflow.ios"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    // ----------------------------------------
    // MARK: - 读写
    // ----------------------------------------

    static func write(_ key: String, _ value: String) {
        guard let url = containerURL?.appendingPathComponent("vf_\(key).txt") else {
            print("[SharedStore] ❌ containerURL is nil")
            return
        }
        do {
            try value.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("[SharedStore] ❌ write failed: \(error)")
        }
    }

    static func read(_ key: String) -> String? {
        guard let url = containerURL?.appendingPathComponent("vf_\(key).txt") else {
            print("[SharedStore] ❌ containerURL is nil")
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func remove(_ key: String) {
        guard let url = containerURL?.appendingPathComponent("vf_\(key).txt") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
