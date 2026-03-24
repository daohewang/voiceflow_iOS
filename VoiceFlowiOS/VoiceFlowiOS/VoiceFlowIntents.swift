/**
 * [INPUT]: 依赖 AppIntents, AppState
 * [OUTPUT]: 对外提供 StartRecordingIntent 和 Live Activity 交互意图
 * [POS]: VoiceFlowiOS/AppIntent 的控制层，基于 iOS 18+ 允许后台录音
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import AppIntents
import SwiftUI

@available(iOS 18.0, *)
struct StartRecordingIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource { "Start Recording" }
    static var description: IntentDescription { IntentDescription("Starts background recording via VoiceFlow.") }
    
    // 该属性标明此意图在后台执行
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        print("[Intent] 🎤 AudioRecordingIntent triggered -> Start Recording")
        // 使用 NotificationCenter 解耦，以便该文件能在键盘和主 App 两个 Target 正常编译
        NotificationCenter.default.post(name: NSNotification.Name("VoiceFlowStartRecordingIntent"), object: nil)
        return .result()
    }
}
