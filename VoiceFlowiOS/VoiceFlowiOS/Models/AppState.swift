/**
 * [INPUT]: 依赖 SwiftUI、Foundation、RecordingCoordinator、UsageStats、StyleTemplateStore
 * [OUTPUT]: 对外提供 AppState 可观察全局状态，完整的录音状态机 + 历史记录 + 统计
 * [POS]: VoiceFlowiOS 的核心状态层，被所有视图消费，持有 RecordingCoordinator
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import ActivityKit
import SwiftUI

// ========================================
// MARK: - App State
// ========================================

@MainActor
@Observable
final class AppState {
    
    // 实时活动引用
    private var liveActivity: Activity<VoiceFlowActivityAttributes>? = nil

    // ----------------------------------------
    // MARK: - Singleton
    // ----------------------------------------

    static let shared = AppState()

    // ----------------------------------------
    // MARK: - Recording Status
    // ----------------------------------------

    enum RecordingStatus: Equatable {
        case idle
        case recording
        case processing
        case done
        case error(String)
    }

    var recordingStatus: RecordingStatus = .idle

    var isRecording: Bool {
        if case .recording = recordingStatus { return true }
        return false
    }

    /// VoiceFlow 开关（绑定到 MainToggleCard）
    /// VoiceFlow 开关（绑定到 MainToggleCard）
    var isVoiceFlowEnabled: Bool {
        get { sharedUD.bool(forKey: "isVoiceFlowEnabled") }
        set { 
            let oldValue = isVoiceFlowEnabled
            sharedUD.set(newValue, forKey: "isVoiceFlowEnabled")
            
            if oldValue && !newValue {
                // 当主应用开关切到关闭时，彻底销毁底层音频引擎并停止后台保活，消除灵动岛麦克风图标
                coordinator?.teardownRecording()
                BackgroundKeepAlive.shared.stop()
                print("[AppState] VoiceFlow disabled. Engine tore down and KeepAlive stopped.")
            }
        }
    }

    /// 从键盘触发的录音（用于显示"返回键盘"引导）
    var isKeyboardRecording: Bool = false

    // ----------------------------------------
    // MARK: - Text State
    // ----------------------------------------

    /// 实时 ASR 识别文字
    var asrText: String = ""

    /// AI 润色结果
    var llmText: String = ""

    /// 剪贴板复制 toast 触发
    var clipboardCopied: Bool = false

    /// 实时音量级别（0.0~1.0），供 UI 波形动画使用
    var audioLevel: Float = 0.0

    // ----------------------------------------
    // MARK: - History
    // ----------------------------------------

    var isHistoryEnabled: Bool = true
    var historyEntries: [HistoryEntry] = []

    // ----------------------------------------
    // MARK: - Stats（从 UsageStats 读取）
    // ----------------------------------------

    var totalDictationHours: Double {
        Double(UsageStats.shared.totalRecordingSeconds) / 3600.0
    }

    var totalWords: Int { UsageStats.shared.totalCharactersTyped }

    var savedHours: Double {
        Double(UsageStats.shared.savedMinutes) / 60.0
    }

    var averageSpeed: Int { 150 }

    // ----------------------------------------
    // MARK: - Settings
    // ----------------------------------------

    // App Group 共享存储，供 Keyboard Extension 读取服务商选择
    private var sharedUD: UserDefaults {
        UserDefaults(suiteName: "group.com.swordsmanye.voiceflow.ios") ?? UserDefaults.standard
    }

    var selectedStyleId: String {
        get { sharedUD.string(forKey: "selectedStyleId") ?? "default" }
        set { sharedUD.set(newValue, forKey: "selectedStyleId") }
    }

    var llmProviderType: LLMProviderType {
        get {
            let raw = sharedUD.string(forKey: "llmProvider") ?? "OpenRouter"
            return LLMProviderType(rawValue: raw) ?? .openRouter
        }
        set { sharedUD.set(newValue.rawValue, forKey: "llmProvider") }
    }

    var asrProviderType: ASRProviderType {
        get {
            let raw = sharedUD.string(forKey: "asrProvider") ?? "ElevenLabs"
            return ASRProviderType(rawValue: raw) ?? .elevenLabs
        }
        set { sharedUD.set(newValue.rawValue, forKey: "asrProvider") }
    }

    // ----------------------------------------
    // MARK: - Navigation
    // ----------------------------------------

    var selectedTab: TabItem = .home

    // ----------------------------------------
    // MARK: - Coordinator
    // ----------------------------------------

    private var coordinator: RecordingCoordinator?

    // ----------------------------------------
    // MARK: - Init
    // ----------------------------------------

    private init() {
        loadHistory()
        coordinator = RecordingCoordinator(appState: self)
    }

    // ----------------------------------------
    // MARK: - Recording Actions
    // ----------------------------------------

    func startRecording() async {
        guard isVoiceFlowEnabled else {
            print("[AppState] VoiceFlow is disabled. Instructing keyboard to jump to main app.")
            updateRecordingStatus(.error("NEEDS_JUMP"))
            return
        }
        startLiveActivity()
        await coordinator?.startRecording()
    }

    func stopRecording() async {
        await coordinator?.stopRecording()
        stopLiveActivity()
    }

    func cancelRecording() {
        coordinator?.cancelRecording()
        stopLiveActivity()
    }

    /// 强制重置状态（用于卡死时的手动救援）
    func forceReset() {
        print("[AppState] ⚠️ Force Reset triggered")
        coordinator?.cancelRecording()
        stopLiveActivity()
        recordingStatus = .idle
        asrText = ""
        llmText = ""
        SharedStore.write("recordingState", "idle")
    }

    // ----------------------------------------
    // MARK: - 录音状态变更 + Darwin IPC
    // ----------------------------------------

    /// 更新录音状态并触发 Darwin 通知 + 键盘 IPC。
    /// 关键设计：不依赖 SwiftUI onChange — 后台不渲染时 onChange 不触发，
    /// 导致键盘永远收不到 recordingStarted/resultReady 等通知。
    func updateRecordingStatus(_ status: RecordingStatus) {
        recordingStatus = status
        onRecordingStatusChanged(status)
    }

    private func onRecordingStatusChanged(_ status: RecordingStatus) {
        switch status {
        case .recording:
            postDarwin(kVoiceFlowRecordingStarted)

        case .processing:
            postDarwin(kVoiceFlowRecordingStopped)
            // CRITICAL FIX: The app audioEngine is stopped during processing.
            // If the app is in the background, iOS will suspend it immediately because 
            // the audio session is no longer active. We MUST start KeepAlive to retain the audio bus!
            BackgroundKeepAlive.shared.start()

        case .done:
            if isKeyboardRecording {
                let result = llmText.isEmpty ? asrText : llmText
                if !result.isEmpty {
                    SharedStore.write("pendingResult", result)
                    SharedStore.write("recordingState", "done")
                    let readBack = SharedStore.read("pendingResult")
                    print("[AppState] Result write verify: \(readBack != nil ? "OK (\(readBack!.count) chars)" : "FAILED")")
                    postDarwin(kVoiceFlowResultReady)
                    print("[AppState] Posted resultReady")
                }
            }
            isKeyboardRecording = false
            BackgroundKeepAlive.shared.start()

        case .error(let msg):
            if isKeyboardRecording {
                SharedStore.write("pendingResult", "ERROR:\(msg)")
                SharedStore.write("recordingState", "idle")
                postDarwin(kVoiceFlowResultReady)
            }
            isKeyboardRecording = false
            postDarwin(kVoiceFlowRecordingStopped)
            BackgroundKeepAlive.shared.start()

        case .idle:
            break
        }
    }

    private func postDarwin(_ name: CFNotificationName) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name, nil, nil, true
        )
    }

    // ----------------------------------------
    // MARK: - Live Activity
    // ----------------------------------------

    func updateLiveActivityStatus(_ status: String) {
        // 先捕获引用，避免 Task 执行时 liveActivity 已被置 nil
        guard let activity = liveActivity else { return }
        Task {
            let updatedState = VoiceFlowActivityAttributes.ContentState(status: status, startTime: Date())
            await activity.update(ActivityContent(state: updatedState, staleDate: nil))
            print("[AppState] 🔄 Live Activity updated: \(status)")
        }
    }

    private func startLiveActivity() {
        guard liveActivity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[AppState] Live Activities are disabled by user or system.")
            return
        }

        let attributes = VoiceFlowActivityAttributes(sessionName: "Recording Session")
        let initialContentState = VoiceFlowActivityAttributes.ContentState(status: "正在录音...", startTime: Date())

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialContentState, staleDate: nil),
                pushType: nil
            )
            self.liveActivity = activity
            SharedStore.write("liveActivityActive", "true")
            SharedStore.write("hasStartedLiveActivityBefore", "true")
            print("[AppState] ✅ Live Activity started: \(activity.id)")
        } catch {
            print("[AppState] ❌ Failed to start Live Activity: \(error)")
        }
    }

    private func stopLiveActivity() {
        guard let activity = liveActivity else { return }
        // 同步置 nil — 防止 startLiveActivity 在 Task 完成前误判为无活动
        self.liveActivity = nil
        SharedStore.write("liveActivityActive", "false")

        Task {
            let finalState = VoiceFlowActivityAttributes.ContentState(status: "录制结束", startTime: Date())
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            print("[AppState] 🛑 Live Activity stopped")
        }
    }

    // ----------------------------------------
    // MARK: - History Management
    // ----------------------------------------

    func addHistoryEntry(asrText: String, finalText: String, durationSeconds: Int) {
        guard isHistoryEnabled else { return }
        let entry = HistoryEntry(
            id: UUID(),
            date: Date(),
            asrText: asrText,
            finalText: finalText,
            durationSeconds: durationSeconds
        )
        historyEntries.insert(entry, at: 0)
        if historyEntries.count > 100 { historyEntries.removeLast() }
        saveHistory()
    }

    func clearHistory() {
        historyEntries.removeAll()
        saveHistory()
    }

    // ----------------------------------------
    // MARK: - Private Persistence
    // ----------------------------------------

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "historyEntries"),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        historyEntries = entries
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(historyEntries) else { return }
        UserDefaults.standard.set(data, forKey: "historyEntries")
    }
}

// ========================================
// MARK: - Tab Item
// ========================================

enum TabItem: String, CaseIterable {
    case home       = "home"
    case history    = "history"
    case dictionary = "dictionary"
    case account    = "account"

    var title: String {
        switch self {
        case .home:       return "首页"
        case .history:    return "历史记录"
        case .dictionary: return "人设"
        case .account:    return "设置"
        }
    }

    var icon: String {
        switch self {
        case .home:       return "house.fill"
        case .history:    return "clock.arrow.circlepath"
        case .dictionary: return "person.crop.rectangle.fill"
        case .account:    return "gearshape.fill"
        }
    }
}
