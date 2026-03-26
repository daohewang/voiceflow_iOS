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

    enum AutoClosePolicy: String, CaseIterable, Equatable {
#if DEBUG
        case thirtySeconds
#endif
        case fiveMinutes
        case oneHour
        case never

        var title: String {
            switch self {
#if DEBUG
            case .thirtySeconds:
                return "30秒后关闭"
#endif
            case .fiveMinutes:
                return "5分钟后关闭"
            case .oneHour:
                return "1小时后关闭"
            case .never:
                return "永不关闭"
            }
        }

        var durationSeconds: TimeInterval? {
            switch self {
#if DEBUG
            case .thirtySeconds:
                return 30
#endif
            case .fiveMinutes:
                return 5 * 60
            case .oneHour:
                return 60 * 60
            case .never:
                return nil
            }
        }
    }
    
    // 实时活动引用
    private var liveActivity: Activity<VoiceFlowActivityAttributes>? = nil
    private var autoCloseTask: Task<Void, Never>?
    private var autoCloseDeadline: Date?
    private var autoCloseScheduledPolicy: AutoClosePolicy?

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
                pendingRestoreWarmStandby = false
                currentSessionSource = .none
                print("[AppState] VoiceFlow disabled. Engine tore down and KeepAlive stopped.")
            }
            refreshSharedServiceState(reason: "voiceFlowEnabled=\(newValue)")
        }
    }

    var autoClosePolicy: AutoClosePolicy {
        get {
            let raw = sharedUD.string(forKey: "voiceFlowAutoClosePolicy") ?? AutoClosePolicy.fiveMinutes.rawValue
            return AutoClosePolicy(rawValue: raw) ?? .fiveMinutes
        }
        set {
            sharedUD.set(newValue.rawValue, forKey: "voiceFlowAutoClosePolicy")
            print("[AutoClose] policy changed to \(newValue.title)")
            updateAutoCloseTimer(reason: "policyChanged:\(newValue.rawValue)")
        }
    }

    /// 从键盘触发的录音（用于显示"返回键盘"引导）
    var isKeyboardRecording: Bool = false
    var keyboardLaunchBehavior: KeyboardLaunchBehavior = .none
    var pendingRestoreWarmStandby: Bool = false
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
        refreshSharedServiceState(reason: "init")
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
        refreshSharedServiceState(reason: "startRecording")
        await coordinator?.startRecording()
    }

    func stopRecording() async {
        guard case .recording = recordingStatus else {
            print("[StopFlow] stop ignored because status=\(recordingStatus)")
            return
        }
        print("[StopFlow] user requested stop, status=\(recordingStatus), isKeyboardRecording=\(isKeyboardRecording)")
        logAudioSnapshot(tag: "before_stop")
        BackgroundKeepAlive.shared.stop()
        logAudioSnapshot(tag: "after_live_activity_and_keepalive_stop")
        scheduleStopFlowSnapshots()
        await coordinator?.stopRecording()
        logAudioSnapshot(tag: "after_coordinator_stop")
    }

    func cancelRecording() {
        coordinator?.cancelRecording()
        keyboardLaunchBehavior = .none
        pendingRestoreWarmStandby = false
        currentSessionSource = .none
        refreshSharedServiceState(reason: "cancelRecording")
    }

    /// 强制重置状态（用于卡死时的手动救援）
    func forceReset() {
        print("[AppState] ⚠️ Force Reset triggered")
        coordinator?.cancelRecording()
        recordingStatus = .idle
        asrText = ""
        llmText = ""
        SharedStore.write("recordingState", "idle")
        keyboardLaunchBehavior = .none
        pendingRestoreWarmStandby = false
        currentSessionSource = .none
        refreshSharedServiceState(reason: "forceReset")
    }

    func refreshSharedServiceState(reason: String) {
        syncSharedServiceSnapshot(reason: reason)
        updateAutoCloseTimer(reason: reason)
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
        refreshSharedServiceState(reason: "recordingStatus=\(status)")
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
                    print("[AppState][Result] writing keyboard result chars=\(result.count), source=\(currentSessionSource.rawValue)")
                    SharedStore.write("pendingResult", result)
                    SharedStore.write("recordingState", "done")
                    let readBack = SharedStore.read("pendingResult")
                    print("[AppState][Result] write verify: \(readBack != nil ? "OK (\(readBack!.count) chars)" : "FAILED")")
                    postDarwin(kVoiceFlowResultReady)
                    print("[AppState][Result] posted resultReady")
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
                print("[AppState][Result] writing keyboard error payload: \(msg)")
                SharedStore.write("pendingResult", "ERROR:\(msg)")
                SharedStore.write("recordingState", "idle")
                postDarwin(kVoiceFlowResultReady)
                print("[AppState][Result] posted resultReady for error")
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
        let mode = liveActivityMode(for: recordingStatus)
        Task {
            await reconcileLiveActivity(reason: "statusUpdate:\(status)", forcedMode: mode)
            print("[AppState] 🔄 Live Activity updated: \(status)")
        }
    }

    private func stopLiveActivity() {
        guard let activity = liveActivity else {
            print("[LiveActivity] stop skipped because activity is nil")
            return
        }
        nonisolated(unsafe) let currentActivity = activity
        self.liveActivity = nil
        SharedStore.write("liveActivityActive", "false")
        print("[LiveActivity] stop requested")

        Task {
            let finalState = VoiceFlowActivityAttributes.ContentState(mode: .armed, startTime: Date())
            await currentActivity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            print("[LiveActivity] stop finished")
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
        Task { @MainActor [weak self] in
            await self?.reconcileLiveActivity(reason: reason)
        }
    }

    private func reconcileLiveActivity(reason: String, forcedMode: VoiceFlowActivityAttributes.LiveActivityMode? = nil) async {
        guard isVoiceFlowEnabled, PermissionManager.shared.microphoneStatus == .granted else {
            if liveActivity != nil {
                print("[LiveActivity] reconcile=\(reason) -> stop (service disabled or permission unavailable)")
                stopLiveActivity()
            }
            return
        }

        guard let mode = forcedMode ?? liveActivityMode(for: recordingStatus) else {
            if liveActivity != nil {
                print("[LiveActivity] reconcile=\(reason) -> stop (no visible mode)")
                stopLiveActivity()
            }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] reconcile=\(reason) skipped because activities are disabled")
            return
        }

        let contentState = VoiceFlowActivityAttributes.ContentState(mode: mode, startTime: Date())
        if let activity = liveActivity {
            nonisolated(unsafe) let currentActivity = activity
            await currentActivity.update(ActivityContent(state: contentState, staleDate: nil))
            print("[LiveActivity] updated mode=\(mode.rawValue) reason=\(reason)")
            return
        }

        do {
            let activity = try Activity.request(
                attributes: VoiceFlowActivityAttributes(sessionName: "VoiceFlow"),
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            self.liveActivity = activity
            SharedStore.write("liveActivityActive", "true")
            SharedStore.write("hasStartedLiveActivityBefore", "true")
            print("[LiveActivity] started mode=\(mode.rawValue) reason=\(reason) id=\(activity.id)")
        } catch {
            print("[LiveActivity] failed to start mode=\(mode.rawValue) reason=\(reason): \(error)")
        }
    }

    private func liveActivityMode(for status: RecordingStatus) -> VoiceFlowActivityAttributes.LiveActivityMode? {
        guard isVoiceFlowEnabled, PermissionManager.shared.microphoneStatus == .granted else { return nil }
        switch status {
        case .recording:
            return .recording
        case .processing:
            return .processing
        case .idle, .done, .error:
            return .armed
        }
    }

    private func isErrorState(_ status: RecordingStatus) -> Bool {
        if case .error = status { return true }
        return false
    }

    private func updateAutoCloseTimer(reason: String) {
        guard isVoiceFlowEnabled else {
            cancelAutoClose(reason: "\(reason):voiceFlowDisabled")
            return
        }

        guard PermissionManager.shared.microphoneStatus == .granted else {
            cancelAutoClose(reason: "\(reason):permissionNotGranted")
            return
        }

        switch recordingStatus {
        case .recording, .processing:
            cancelAutoClose(reason: "\(reason):busy")
        case .idle, .done, .error:
            scheduleAutoCloseIfNeeded(reason: reason)
        }
    }

    private func scheduleAutoCloseIfNeeded(reason: String) {
        guard let duration = autoClosePolicy.durationSeconds else {
            cancelAutoClose(reason: "\(reason):policyNever")
            print("[AutoClose] skip scheduling (\(reason)) because policy is 永不关闭")
            return
        }

        if autoCloseTask != nil,
           autoCloseScheduledPolicy == autoClosePolicy,
           let deadline = autoCloseDeadline,
           deadline > Date() {
            print("[AutoClose] keep existing schedule policy=\(autoClosePolicy.title) reason=\(reason) deadline=\(deadline)")
            return
        }

        cancelAutoClose(reason: "\(reason):reschedule")

        let deadline = Date().addingTimeInterval(duration)
        autoCloseDeadline = deadline
        autoCloseScheduledPolicy = autoClosePolicy
        print("[AutoClose] scheduled policy=\(autoClosePolicy.title) reason=\(reason) deadline=\(deadline)")

        autoCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard self.isVoiceFlowEnabled else { return }
            guard self.permissionEligibleForArmedAutoClose else { return }

            print("[AutoClose] deadline reached, disabling VoiceFlow")
            self.autoCloseTask = nil
            self.autoCloseDeadline = nil
            self.autoCloseScheduledPolicy = nil
            self.isVoiceFlowEnabled = false
        }
    }

    private func cancelAutoClose(reason: String) {
        if autoCloseTask != nil {
            print("[AutoClose] cancelled reason=\(reason)")
        }
        autoCloseTask?.cancel()
        autoCloseTask = nil
        autoCloseDeadline = nil
        autoCloseScheduledPolicy = nil
    }

    private var permissionEligibleForArmedAutoClose: Bool {
        guard PermissionManager.shared.microphoneStatus == .granted else { return false }
        switch recordingStatus {
        case .idle, .done, .error:
            return true
        case .recording, .processing:
            return false
        }
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
