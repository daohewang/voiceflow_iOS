/**
 * [INPUT]: 依赖 SwiftUI、Foundation、RecordingCoordinator、UsageStats、StyleTemplateStore
 * [OUTPUT]: 对外提供 AppState 可观察全局状态，完整的录音状态机 + 历史记录 + 统计
 * [POS]: VoiceFlowiOS 的核心状态层，被所有视图消费，持有 RecordingCoordinator
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import ActivityKit
import SwiftUI
import AVFoundation
import UIKit

// ========================================
// MARK: - App State
// ========================================

@MainActor
@Observable
final class AppState {

    enum KeyboardLaunchBehavior: Equatable {
        case none
        case restoreOnly
        case startRecording
    }
    
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
        get {
            guard sharedUD.object(forKey: "isVoiceFlowEnabled") != nil else { return true }
            return sharedUD.bool(forKey: "isVoiceFlowEnabled")
        }
        set { 
            let oldValue = isVoiceFlowEnabled
            sharedUD.set(newValue, forKey: "isVoiceFlowEnabled")
            
            if oldValue && !newValue {
                // 当主应用开关切到关闭时，彻底销毁底层音频引擎并停止后台保活，消除灵动岛麦克风图标
                coordinator?.teardownRecording()
                BackgroundKeepAlive.shared.stop()
                keyboardLaunchBehavior = .none
                currentSessionSource = .none
                print("[AppState] VoiceFlow disabled. Engine tore down and KeepAlive stopped.")
            }
            syncSharedServiceSnapshot(reason: "voiceFlowEnabled=\(newValue)")
        }
    }

    /// 从键盘触发的录音（用于显示"返回键盘"引导）
    var isKeyboardRecording: Bool = false
    var keyboardLaunchBehavior: KeyboardLaunchBehavior = .none
    private var currentSessionSource: SharedStore.SessionSource = .none

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
    var isBackgroundCaptureReady: Bool { coordinator?.isWarmStandbyReady ?? false }

    // ----------------------------------------
    // MARK: - Init
    // ----------------------------------------

    private init() {
        loadHistory()
        coordinator = RecordingCoordinator(appState: self)
        syncSharedServiceSnapshot(reason: "init")
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
        keyboardLaunchBehavior = .none
        currentSessionSource = isKeyboardRecording ? .keyboard : .mainApp
        syncSharedServiceSnapshot(reason: "startRecording")
        startLiveActivity()
        await coordinator?.startRecording()
    }

    func stopRecording() async {
        guard case .recording = recordingStatus else {
            print("[StopFlow] stop ignored because status=\(recordingStatus)")
            return
        }
        print("[StopFlow] user requested stop, status=\(recordingStatus), isKeyboardRecording=\(isKeyboardRecording)")
        logAudioSnapshot(tag: "before_stop")
        stopLiveActivity()
        BackgroundKeepAlive.shared.stop()
        logAudioSnapshot(tag: "after_live_activity_and_keepalive_stop")
        scheduleStopFlowSnapshots()
        await coordinator?.stopRecording()
        logAudioSnapshot(tag: "after_coordinator_stop")
    }

    func cancelRecording() {
        coordinator?.cancelRecording()
        stopLiveActivity()
        keyboardLaunchBehavior = .none
        currentSessionSource = .none
        syncSharedServiceSnapshot(reason: "cancelRecording")
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
        keyboardLaunchBehavior = .none
        currentSessionSource = .none
        syncSharedServiceSnapshot(reason: "forceReset")
    }

    func refreshSharedServiceState(reason: String) {
        syncSharedServiceSnapshot(reason: reason)
    }

    func ensureArmedWarmStandbyIfNeeded(reason: String) async {
        guard isVoiceFlowEnabled else {
            print("[ArmedState] warm standby skipped (\(reason)) because VoiceFlow is disabled")
            return
        }
        guard recordingStatus == .idle || recordingStatus == .done || isErrorState(recordingStatus) else {
            print("[ArmedState] warm standby skipped (\(reason)) because status=\(recordingStatus)")
            return
        }

        PermissionManager.shared.refreshStatus()
        guard PermissionManager.shared.microphoneStatus == .granted else {
            print("[ArmedState] warm standby skipped (\(reason)) because mic permission is \(PermissionManager.shared.microphoneStatus)")
            syncSharedServiceSnapshot(reason: "warmStandbySkipped:\(reason)")
            return
        }

        coordinator?.ensureWarmStandbyIfPossible()
        syncSharedServiceSnapshot(reason: "warmStandby:\(reason)")
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
        if status == .done || status == .idle || isErrorState(status) {
            keyboardLaunchBehavior = .none
            currentSessionSource = .none
        }
        syncSharedServiceSnapshot(reason: "recordingStatus=\(status)")
    }

    private func onRecordingStatusChanged(_ status: RecordingStatus) {
        switch status {
        case .recording:
            postDarwin(kVoiceFlowRecordingStarted)

        case .processing:
            postDarwin(kVoiceFlowRecordingStopped)
            print("[StopFlow] KeepAlive skipped during processing; relying on background task")

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
            if isVoiceFlowEnabled {
                BackgroundKeepAlive.shared.start()
                print("[ArmedState] KeepAlive resumed after done")
            } else {
                BackgroundKeepAlive.shared.stop()
                print("[ArmedState] KeepAlive remained stopped after done because VoiceFlow is disabled")
            }

        case .error(let msg):
            if isKeyboardRecording {
                SharedStore.write("pendingResult", "ERROR:\(msg)")
                SharedStore.write("recordingState", "idle")
                postDarwin(kVoiceFlowResultReady)
            }
            isKeyboardRecording = false
            postDarwin(kVoiceFlowRecordingStopped)
            if isVoiceFlowEnabled {
                BackgroundKeepAlive.shared.start()
                print("[ArmedState] KeepAlive resumed after error")
            } else {
                BackgroundKeepAlive.shared.stop()
                print("[ArmedState] KeepAlive remained stopped after error because VoiceFlow is disabled")
            }

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
        guard let activity = liveActivity else {
            print("[StopFlow] Live Activity already nil")
            return
        }
        // 同步置 nil — 防止 startLiveActivity 在 Task 完成前误判为无活动
        self.liveActivity = nil
        SharedStore.write("liveActivityActive", "false")
        print("[StopFlow] Live Activity stop requested")

        Task {
            let finalState = VoiceFlowActivityAttributes.ContentState(status: "录制结束", startTime: Date())
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            print("[StopFlow] Live Activity stop finished")
        }
    }

    private func syncSharedServiceSnapshot(reason: String) {
        let permissionStatus = PermissionManager.shared.microphoneStatus
        let serviceState: SharedStore.ServiceState

        if !isVoiceFlowEnabled {
            serviceState = .disabledByUser
        } else if permissionStatus != .granted {
            serviceState = .disabledBySystemPermission
        } else {
            switch recordingStatus {
            case .recording:
                serviceState = .recording
            case .processing:
                serviceState = .processing
            case .idle, .done, .error:
                serviceState = .armed
            }
        }

        SharedStore.writeServiceState(serviceState)
        SharedStore.write("voiceFlowEnabled", isVoiceFlowEnabled ? "true" : "false")
        let sharedSource: SharedStore.SessionSource
        switch serviceState {
        case .recording, .processing:
            sharedSource = currentSessionSource
        default:
            sharedSource = .none
        }
        SharedStore.writeSessionSource(sharedSource)
        print("[ServiceState] synced reason=\(reason), serviceState=\(serviceState.rawValue), permission=\(permissionStatus), voiceFlowEnabled=\(isVoiceFlowEnabled), sessionSource=\(sharedSource.rawValue)")
    }

    private func isErrorState(_ status: RecordingStatus) -> Bool {
        if case .error = status { return true }
        return false
    }

    private func logAudioSnapshot(tag: String) {
        let session = AVAudioSession.sharedInstance()
        let routeInputs = session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ",")
        print("[StopFlow][Snapshot] tag=\(tag), appState=\(UIApplication.shared.applicationState.rawValue), recordingStatus=\(recordingStatus), keepalive=\(BackgroundKeepAlive.shared.isActive), liveActivity=\(liveActivity != nil), category=\(session.category.rawValue), mode=\(session.mode.rawValue), routeInputs=\(routeInputs.isEmpty ? "none" : routeInputs)")
    }

    private func scheduleStopFlowSnapshots() {
        let delays: [(String, UInt64)] = [
            ("+100ms", 100_000_000),
            ("+500ms", 500_000_000),
            ("+1000ms", 1_000_000_000)
        ]

        for (label, delay) in delays {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                self?.logAudioSnapshot(tag: label)
            }
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
