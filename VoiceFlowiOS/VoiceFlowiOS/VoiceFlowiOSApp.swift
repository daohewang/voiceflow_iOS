/**
 * [INPUT]: 依赖 SwiftUI 框架，依赖 AppState 全局状态，依赖 Darwin Notification
 * [OUTPUT]: 对外提供 @main App 入口点，处理 URL Scheme 唤起 + 后台录音
 * [POS]: VoiceFlowiOS 应用的根入口，管理 ContentView 生命周期 + URL Scheme 处理
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 *
 * 架构说明：
 *   1. 键盘 Extension 用 URL Scheme 唤醒主 App
 *   2. 主 App 在前台启动 AVAudioSession + 录音
 *   3. 录音启动后（无论成败）立即 suspend 返回后台
 *   4. 键盘通过 Darwin Notification 实时接收状态
 *   5. 录音完成后，结果写入 App Group，键盘读取并插入
 */

import SwiftUI
import UIKit

// ========================================
// MARK: - Darwin Notification Names
// ========================================

let kVoiceFlowRecordingStarted = CFNotificationName("com.swordsmanye.voiceflow.recordingStarted" as CFString)
let kVoiceFlowRecordingStopped = CFNotificationName("com.swordsmanye.voiceflow.recordingStopped" as CFString)
let kVoiceFlowAudioLevel = CFNotificationName("com.swordsmanye.voiceflow.audioLevel" as CFString)
let kVoiceFlowResultReady = CFNotificationName("com.swordsmanye.voiceflow.resultReady" as CFString)
let kVoiceFlowStopRecording = CFNotificationName("com.swordsmanye.voiceflow.stopRecording" as CFString)

// ========================================
// MARK: - VoiceFlow iOS App
// ========================================

@main
struct VoiceFlowiOSApp: App {

    @State private var appState = AppState.shared
    @State private var pendingRecordRequest = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear { setupDarwinListeners() }
                .onOpenURL { url in handleOpenURL(url) }
                .preferredColorScheme(.light)
                .onChange(of: appState.recordingStatus) { _, newStatus in
                    handleRecordingStatusChange(newStatus)
                }
        }
    }

    // ----------------------------------------
    // MARK: - Darwin 监听（接收键盘 stopRecording 命令）
    // ----------------------------------------

    private func setupDarwinListeners() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    // 申请后台执行时间 — 停止录音后音频 entitlement 失效
                    // 需要额外时间完成 ASR commit + LLM 润色 + 结果写入
                    var bgTaskID = UIBackgroundTaskIdentifier.invalid
                    bgTaskID = UIApplication.shared.beginBackgroundTask {
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                        bgTaskID = .invalid
                    }
                    print("[App] Background task started for stopRecording")

                    await AppState.shared.stopRecording()

                    // 停止录音完成后延迟结束后台任务，给 LLM 回调留时间
                    try? await Task.sleep(nanoseconds: 40_000_000_000) // 40s 上限
                    if bgTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                        print("[App] Background task ended")
                    }
                }
            },
            kVoiceFlowStopRecording.rawValue,
            nil,
            .deliverImmediately
        )
    }

    // ----------------------------------------
    // MARK: - URL Scheme 处理
    // ----------------------------------------

    private func handleOpenURL(_ url: URL) {
        print("[App] URL: \(url.absoluteString)")
        guard url.scheme == "voiceflow" else { return }

        switch url.host {
        case "startRecording":
            print("[App] ▶️ startRecording triggered from keyboard")
            pendingRecordRequest = true
            appState.selectedTab = .home
            appState.isVoiceFlowEnabled = true
            appState.isKeyboardRecording = true

            // 启动录音 → 无论成败都返回键盘
            Task { @MainActor in
                print("[App] Calling appState.startRecording()...")
                await appState.startRecording()
                print("[App] startRecording returned, status=\(appState.recordingStatus)")

                // 录音失败 → 错误写入 App Group 通知键盘
                if case .error(let msg) = appState.recordingStatus {
                    print("[App] ❌ Recording error: \(msg)")
                    saveErrorAndNotifyKeyboard(msg)
                    pendingRecordRequest = false
                    appState.isKeyboardRecording = false
                    return  // 不 suspend，留在前台让用户看到错误
                }

                // 等 500ms 让音频会话充分稳定，然后返回键盘
                print("[App] Recording OK, waiting 500ms before suspend...")
                try? await Task.sleep(nanoseconds: 500_000_000)
                suspendToBackground()
            }

        case "stopRecording":
            Task { await appState.stopRecording() }

        default:
            break
        }
    }

    // ----------------------------------------
    // MARK: - 录音状态变化处理
    // ----------------------------------------

    private func handleRecordingStatusChange(_ newStatus: AppState.RecordingStatus) {
        switch newStatus {
        case .recording:
            postDarwinNotification(kVoiceFlowRecordingStarted)

        case .processing:
            postDarwinNotification(kVoiceFlowRecordingStopped)

        case .done:
            if pendingRecordRequest {
                let result = appState.llmText.isEmpty ? appState.asrText : appState.llmText
                if !result.isEmpty { saveResultAndNotifyKeyboard(result) }
            }
            appState.isKeyboardRecording = false

        case .error(let msg):
            if pendingRecordRequest {
                saveErrorAndNotifyKeyboard(msg)
                pendingRecordRequest = false
            }
            appState.isKeyboardRecording = false
            postDarwinNotification(kVoiceFlowRecordingStopped)

        case .idle:
            break
        }
    }

    // ----------------------------------------
    // MARK: - 返回后台（suspend）
    // ----------------------------------------

    private func suspendToBackground() {
        guard appState.isKeyboardRecording else {
            print("[App] ⚠️ Not keyboard recording, skip suspend")
            return
        }
        print("[App] Attempting suspend to return to keyboard...")

        // 延迟到下一个 run loop 确保当前 UI 更新完成
        DispatchQueue.main.async {
            let sel = Selector(("suspend"))
            guard UIApplication.shared.responds(to: sel) else {
                print("[App] ❌ suspend selector not available")
                return
            }
            UIApplication.shared.perform(sel)
            print("[App] ✅ Suspended via perform")
        }
    }

    // ----------------------------------------
    // MARK: - 保存结果并通知键盘
    // ----------------------------------------

    private func saveResultAndNotifyKeyboard(_ text: String) {
        SharedStore.write("pendingResult", text)
        SharedStore.write("recordingState", "done")

        let readBack = SharedStore.read("pendingResult")
        print("[App] Keychain write verify: \(readBack != nil ? "✅ OK (\(readBack!.count) chars)" : "❌ FAILED")")

        pendingRecordRequest = false
        postDarwinNotification(kVoiceFlowResultReady)
        print("[App] Posted resultReady notification")
    }

    private func saveErrorAndNotifyKeyboard(_ error: String) {
        SharedStore.write("pendingResult", "ERROR:\(error)")
        SharedStore.write("recordingState", "idle")
        postDarwinNotification(kVoiceFlowResultReady)
    }

    // ----------------------------------------
    // MARK: - Darwin Notification 发送
    // ----------------------------------------

    private func postDarwinNotification(_ name: CFNotificationName) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name, nil, nil, true
        )
    }
}
