/**
 * [INPUT]: 依赖 SwiftUI 框架，依赖 AppState 全局状态，依赖 Darwin Notification
 * [OUTPUT]: 对外提供 @main App 入口点，处理 URL Scheme 唤起 + 后台录音
 * [POS]: VoiceFlowiOS 应用的根入口，管理 ContentView 生命周期 + URL Scheme 处理
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 *
 * 架构说明（后台常驻模式）：
 *   1. App 启动时预配置 AVAudioSession，进入后台时启动静音播放保活
 *   2. 键盘优先通过 Darwin Notification (requestStart) 直接触发后台录音
 *   3. 仅在主 App 未存活时，fallback 到 URL Scheme 唤醒
 *   4. 录音完成后，结果写入 App Group，Darwin 通知键盘读取并插入
 *   5. AVAudioSession 永不 deactivate，确保后台常驻能力
 */

import SwiftUI
import UIKit
import AVFoundation

// ========================================
// MARK: - Darwin Notification Names
// ========================================

let kVoiceFlowRecordingStarted = CFNotificationName("com.swordsmanye.voiceflow.recordingStarted" as CFString)
let kVoiceFlowRecordingStopped = CFNotificationName("com.swordsmanye.voiceflow.recordingStopped" as CFString)
let kVoiceFlowAudioLevel = CFNotificationName("com.swordsmanye.voiceflow.audioLevel" as CFString)
let kVoiceFlowResultReady = CFNotificationName("com.swordsmanye.voiceflow.resultReady" as CFString)
let kVoiceFlowStopRecording = CFNotificationName("com.swordsmanye.voiceflow.stopRecording" as CFString)
let kVoiceFlowRequestStart = CFNotificationName("com.swordsmanye.voiceflow.requestStart" as CFString)
let kVoiceFlowRequestAck   = CFNotificationName("com.swordsmanye.voiceflow.requestAck" as CFString)

// ========================================
// MARK: - VoiceFlow iOS App
// ========================================

@main
struct VoiceFlowiOSApp: App {

    @State private var appState = AppState.shared
    @Environment(\.scenePhase) private var scenePhase

    // Darwin 监听 + 音频会话必须在 App 启动时立即注册，
    // 而非等到 ContentView.onAppear — 否则 URL Scheme 冷启动时
    // listener 尚未就位，键盘发来的 stopRecording 等通知会丢失。
    init() {
        setupDarwinListeners()
        configureAudioSessionOnce()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(PermissionManager.shared)
                .onOpenURL { url in handleOpenURL(url) }
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
                .onChange(of: appState.recordingStatus) { _, newStatus in
                    handleRecordingStatusChange(newStatus)
                }
        }
    }

    // ----------------------------------------
    // MARK: - Darwin 监听（接收键盘 stopRecording 命令）
    // ----------------------------------------

    private static var darwinListenersRegistered = false

    private func setupDarwinListeners() {
        guard !Self.darwinListenersRegistered else { return }
        Self.darwinListenersRegistered = true
        
        // 监听来自 AppIntent 的特权背景启动请求 (iOS 18)
        NotificationCenter.default.addObserver(forName: NSNotification.Name("VoiceFlowStartRecordingIntent"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                print("[App] 🎤 Received VoiceFlowStartRecordingIntent from Intent")
                let status = AppState.shared.recordingStatus
                if status != .recording && status != .processing {
                    await AppState.shared.startRecording()
                }
            }
        }

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

                    // 等待录音处理完成（轮询状态，最长 25s，避免超出 iOS 后台时限）
                    for _ in 0..<25 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        let status = AppState.shared.recordingStatus
                        if case .done = status { break }
                        if case .error = status { break }
                        if case .idle = status { break }
                    }
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

        // 键盘 Darwin 请求开始录音（后台直接响应，无需 URL Scheme 跳转）
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    // 去重：仅在非活动状态响应，防止 Darwin 重复投递
                    let status = AppState.shared.recordingStatus
                    guard status != .recording && status != .processing else {
                        print("[App] Already recording/processing, ignoring duplicate requestStart")
                        return
                    }
                    guard AppState.shared.isBackgroundCaptureReady else {
                        print("[App] requestStart received in background but armed state is cold — no ACK, let keyboard fallback URL")
                        return
                    }
                    // 立即 ACK — 让键盘知道主 App 存活
                    CFNotificationCenterPostNotification(
                        CFNotificationCenterGetDarwinNotifyCenter(),
                        kVoiceFlowRequestAck, nil, nil, true
                    )
                    // 不停止 KeepAlive — .mixWithOthers 让静音播放和录音共存
                    // 避免 stop→start 硬件时序竞争（isBusy 561015905）
                    AppState.shared.isKeyboardRecording = true
                    print("[App] Darwin requestStart received — starting recording from background")
                    await AppState.shared.startRecording()
                    // 错误处理统一由 handleRecordingStatusChange 负责
                }
            },
            kVoiceFlowRequestStart.rawValue,
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
            print("[App] ▶️ startRecording triggered from keyboard (URL Scheme)")
            appState.selectedTab = .home
            appState.isVoiceFlowEnabled = true
            appState.isKeyboardRecording = true
            appState.keyboardLaunchBehavior = .startRecording

            // 仅在麦克风权限已授予时直接启动录音
            // 未授权 → ContentView 会显示 PermissionOnboardingView，
            // 授权完成后由 onComplete 回调自动启动录音
            guard AVAudioSession.sharedInstance().recordPermission == .granted else {
                print("[App] Mic permission not granted — showing onboarding")
                return
            }

            Task { @MainActor in
                // iOS 深层机制：即使触发了 URL Scheme，代码执行时 App 可能仍处于状态切换中（尚未完全 Active）。
                // 若此时立刻启动音频引擎，非常容易遭遇 2003329396 后台录音限制阻拦。
                // 因此我们延迟 500ms，确保 App 已经彻底转入前台，再安全拉起内核。
                try? await Task.sleep(nanoseconds: 500_000_000)

                await appState.startRecording()

                if case .error(let msg) = appState.recordingStatus {
                    print("[App] ❌ Recording error: \(msg)")
                    saveErrorAndNotifyKeyboard(msg)
                    appState.isKeyboardRecording = false
                }
            }

        case "restoreVoiceFlow":
            print("[App] ▶️ restoreVoiceFlow triggered from keyboard (URL Scheme)")
            appState.selectedTab = .home
            appState.isKeyboardRecording = true
            appState.keyboardLaunchBehavior = .restoreOnly
            appState.isVoiceFlowEnabled = true

            let permission = AVAudioSession.sharedInstance().recordPermission
            if permission == .granted {
                print("[App] VoiceFlow restored to armed — waiting for user to return to keyboard")
            } else {
                print("[App] VoiceFlow restore requires microphone permission — showing onboarding")
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
            if appState.isKeyboardRecording {
                let result = appState.llmText.isEmpty ? appState.asrText : appState.llmText
                if !result.isEmpty { saveResultAndNotifyKeyboard(result) }
            }
            appState.isKeyboardRecording = false
            // 无条件重启保活 — 防止前台→后台窗口期被 iOS suspend
            BackgroundKeepAlive.shared.start()

        case .error(let msg):
            if appState.isKeyboardRecording {
                saveErrorAndNotifyKeyboard(msg)
            }
            appState.isKeyboardRecording = false
            postDarwinNotification(kVoiceFlowRecordingStopped)
            BackgroundKeepAlive.shared.start()

        case .idle:
            break
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

    // ----------------------------------------
    // MARK: - 音频会话预配置
    // ----------------------------------------

    /// 启动时预配置 AVAudioSession（.playAndRecord），
    /// 为后台 keepalive 和 Darwin 直接触发录音打下基础。
    /// 不会触发麦克风权限弹窗（只有实际录音时才请求）。
    private static var audioSessionConfigured = false

    private func configureAudioSessionOnce() {
        guard !Self.audioSessionConfigured else { return }
        Self.audioSessionConfigured = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setActive(true)
            print("[App] ✅ Audio session pre-configured")
        } catch {
            print("[App] ⚠️ Audio session pre-config failed: \(error)")
        }
    }

    // ----------------------------------------
    // MARK: - Scene Phase（后台保活管理）
    // ----------------------------------------

    /// App 进入后台 → 启动静音播放保活
    /// App 回到前台 → 停止保活（节省资源）
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if appState.isVoiceFlowEnabled {
                BackgroundKeepAlive.shared.start()
                print("[App] Entered background — keepalive started")
            } else {
                BackgroundKeepAlive.shared.stop()
                print("[App] Entered background — keepalive skipped because VoiceFlow is disabled")
            }
        case .active:
            // 如果键盘正在录音中（或者处于 AI 处理中），不要停止保活，否则会导致录音中断
            if appState.recordingStatus == .idle {
                BackgroundKeepAlive.shared.stop()
                print("[App] Entered active — keepalive stopped")
            } else {
                print("[App] Entered active — keepalive maintained for ongoing recording")
            }
        default:
            break
        }
    }
}
