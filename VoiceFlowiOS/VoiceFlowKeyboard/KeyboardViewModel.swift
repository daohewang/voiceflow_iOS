/**
 * [INPUT]: 依赖 UIKit、Darwin Notification，通过 App Group 文件共享录音结果
 * [OUTPUT]: 对外提供 KeyboardViewModel，管理录音触发→读取结果→插入流程
 * [POS]: VoiceFlowKeyboard Extension 的状态层，被 KeyboardView 消费
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 *
 * 架构说明（后台常驻模式）：
 *   1. 键盘 Extension 只负责"触发"和"接收结果"
 *   2. 真正的录音由主 App 在后台执行（静音播放保活，永不被回收）
 *   3. 触发优先级：Darwin requestStart（无需跳转）→ URL Scheme（兜底）
 *   4. Darwin Notification 做信号通知，App Group 文件做数据传递
 */

import Foundation
import UIKit
import OSLog

@inline(__always)
func keyboardLog(_ message: String) {
    KeyboardDebugLog.logger.debug("\(message, privacy: .public)")
}

enum KeyboardDebugLog {
    static let logger = Logger(subsystem: "com.swordsmanye.voiceflow.keyboard", category: "lifecycle")
}

// ========================================
// MARK: - Darwin Notification Names
// ========================================

private let kRecordingStarted = CFNotificationName("com.swordsmanye.voiceflow.recordingStarted" as CFString)
private let kRecordingStopped = CFNotificationName("com.swordsmanye.voiceflow.recordingStopped" as CFString)
private let kAudioLevel       = CFNotificationName("com.swordsmanye.voiceflow.audioLevel" as CFString)
private let kResultReady      = CFNotificationName("com.swordsmanye.voiceflow.resultReady" as CFString)
private let kStopRecording    = CFNotificationName("com.swordsmanye.voiceflow.stopRecording" as CFString)
private let kRequestStart     = CFNotificationName("com.swordsmanye.voiceflow.requestStart" as CFString)
private let kRequestAck       = CFNotificationName("com.swordsmanye.voiceflow.requestAck" as CFString)

// ========================================
// MARK: - Keychain 跨进程数据共享
// ========================================

/// App Group 文件共享 — 主 App 和键盘通过共享容器目录读写文件
private let kGroupID = "group.com.swordsmanye.voiceflow.ios"

private func sharedContainerURL() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: kGroupID)
}

private func sharedRead(_ key: String) -> String? {
    guard let url = sharedContainerURL()?.appendingPathComponent("vf_\(key).txt") else {
        keyboardLog("[KeyboardVM] ❌ containerURL is nil")
        return nil
    }
    return try? String(contentsOf: url, encoding: .utf8)
}

private func sharedWrite(_ key: String, _ value: String) {
    guard let url = sharedContainerURL()?.appendingPathComponent("vf_\(key).txt") else { return }
    try? value.write(to: url, atomically: true, encoding: .utf8)
}

private func sharedRemove(_ key: String) {
    guard let url = sharedContainerURL()?.appendingPathComponent("vf_\(key).txt") else { return }
    try? FileManager.default.removeItem(at: url)
}

// ========================================
// MARK: - Keyboard View Model
// ========================================

@MainActor
@Observable
final class KeyboardViewModel {
    nonisolated(unsafe) private static var activeInstanceID: UUID?

    private enum SharedServiceState: String {
        case disabledByUser
        case disabledBySystemPermission
        case armed
        case recording
        case processing
    }

    private enum SharedPermissionSnapshot: String {
        case notDetermined
        case granted
        case denied
    }

    weak var inputVC: UIInputViewController?
    private let instanceID = UUID()

    // ----------------------------------------
    // MARK: - State
    // ----------------------------------------

    enum RecordState: Equatable { case idle, recording, processing, waitingMainApp }

    var recordState: RecordState = .idle
    var displayText: String = ""
    var audioLevel: Float = 0.0
    var errorMsg: String? = nil
    private var ackReceived = false
    private var ackTimeoutTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var processingTimeoutTask: Task<Void, Never>?

    // ----------------------------------------
    // MARK: - Init / Deinit
    // ----------------------------------------

    init(inputVC: UIInputViewController) {
        self.inputVC = inputVC
        becomeActive(reason: "init")
        setupDarwinObservers()
        recoverState()
    }

    deinit {
        // 移除全部 Darwin 通知观察者，防止泄漏 + use-after-free
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), ptr
        )
        if Self.activeInstanceID == instanceID {
            Self.activeInstanceID = nil
        }
        keyboardLog("[KeyboardVM] Observers removed in deinit")
    }

    // ----------------------------------------
    // MARK: - 状态恢复（键盘被 iOS 重建后调用）
    // ----------------------------------------

    /// 键盘进程被重建后，从共享文件恢复当前录音状态
    private func recoverState() {
        becomeActive(reason: "recoverState")
        // 先检查有没有待插入的结果
        if consumePendingResult() { return }

        let sharedRecordingState = sharedRead("recordingState")

        if let rawServiceState = sharedRead("serviceState"),
           let serviceState = SharedServiceState(rawValue: rawServiceState) {
            switch serviceState {
            case .recording:
                cancelPendingStartupWaiters(reason: "recoverState:serviceState=recording")
                recordState = .recording
                displayText = "正在录音..."
            case .processing:
                cancelPendingStartupWaiters(reason: "recoverState:serviceState=processing")
                recordState = .processing
                displayText = "处理中..."
            case .armed:
                if sharedRecordingState == "starting" {
                    recordState = .waitingMainApp
                    displayText = "准备录音..."
                    startRecoveryTimeout()
                    keyboardLog("[KeyboardVM] Recovered serviceState=armed with shared starting -> waitingMainApp")
                } else {
                    cancelPendingStartupWaiters(reason: "recoverState:serviceState=armed")
                    recordState = .idle
                    displayText = ""
                }
            case .disabledByUser, .disabledBySystemPermission:
                cancelPendingStartupWaiters(reason: "recoverState:serviceState=\(serviceState.rawValue)")
                recordState = .idle
                displayText = ""
            }
            keyboardLog("[KeyboardVM] Recovered shared serviceState: \(serviceState.rawValue)")
            return
        }

        // 检查录音是否在进行中
        if let state = sharedRecordingState {
            switch state {
            case "recording":
                cancelPendingStartupWaiters(reason: "recoverState:recordingState=recording")
                recordState = .recording
                displayText = "正在录音..."
                keyboardLog("[KeyboardVM] Recovered state: recording")
            case "processing":
                cancelPendingStartupWaiters(reason: "recoverState:recordingState=processing")
                recordState = .processing
                displayText = "处理中..."
                keyboardLog("[KeyboardVM] Recovered state: processing")
            case "starting":
                recordState = .waitingMainApp
                displayText = "准备录音..."
                startRecoveryTimeout()
                keyboardLog("[KeyboardVM] Recovered state: starting -> waitingMainApp")
            case "done":
                // 上一次录音已完成但结果可能已被消费，视为 idle
                sharedRemove("recordingState")
                cancelPendingStartupWaiters(reason: "recoverState:recordingState=done")
                recordState = .idle
                keyboardLog("[KeyboardVM] Recovered state: done → treated as idle")
            default:
                cancelPendingStartupWaiters(reason: "recoverState:recordingState=\(state)")
                keyboardLog("[KeyboardVM] Recovered state: idle (\(state))")
                recordState = .idle
                displayText = ""
            }
        } else {
            cancelPendingStartupWaiters(reason: "recoverState:noSharedState")
            keyboardLog("[KeyboardVM] No shared state file")
            recordState = .idle
            displayText = ""
        }
    }

    // ----------------------------------------
    // MARK: - Darwin Notification Observers
    // ----------------------------------------

    private func setupDarwinObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let ptr = Unmanaged.passUnretained(self).toOpaque()

        let pairs: [(CFNotificationName, @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void)] = [
            (kRecordingStarted, { _, obs, _, _, _ in
                guard let obs else { return }
                let vm = Unmanaged<KeyboardViewModel>.fromOpaque(obs).takeUnretainedValue()
                Task { @MainActor in vm.onRecordingStarted() }
            }),
            (kRecordingStopped, { _, obs, _, _, _ in
                guard let obs else { return }
                let vm = Unmanaged<KeyboardViewModel>.fromOpaque(obs).takeUnretainedValue()
                Task { @MainActor in vm.onRecordingStopped() }
            }),
            (kResultReady, { _, obs, _, _, _ in
                guard let obs else { return }
                let vm = Unmanaged<KeyboardViewModel>.fromOpaque(obs).takeUnretainedValue()
                Task { @MainActor in vm.onResultReady() }
            }),
            (kAudioLevel, { _, obs, _, _, _ in
                guard let obs else { return }
                let vm = Unmanaged<KeyboardViewModel>.fromOpaque(obs).takeUnretainedValue()
                Task { @MainActor in vm.onAudioLevelUpdate() }
            }),
            (kRequestAck, { _, obs, _, _, _ in
                guard let obs else { return }
                let vm = Unmanaged<KeyboardViewModel>.fromOpaque(obs).takeUnretainedValue()
                Task { @MainActor in vm.onRequestAck() }
            }),
        ]

        for (name, callback) in pairs {
            CFNotificationCenterAddObserver(center, ptr, callback, name.rawValue, nil, .deliverImmediately)
        }
        keyboardLog("[KeyboardVM] Darwin observers registered")
    }

    private var isActiveInstance: Bool {
        Self.activeInstanceID == instanceID
    }

    private func becomeActive(reason: String) {
        Self.activeInstanceID = instanceID
        keyboardLog("[KeyboardVM] Became active instance reason=\(reason)")
    }

    func suspendInactiveInstance(reason: String) {
        if Self.activeInstanceID == instanceID {
            Self.activeInstanceID = nil
        }
        ackTimeoutTask?.cancel()
        recoveryTask?.cancel()
        processingTimeoutTask?.cancel()
        ackTimeoutTask = nil
        recoveryTask = nil
        processingTimeoutTask = nil
        keyboardLog("[KeyboardVM] Suspended instance reason=\(reason)")
    }

    // ----------------------------------------
    // MARK: - Darwin Notification Handlers
    // ----------------------------------------

    private func cancelPendingStartupWaiters(reason: String) {
        ackTimeoutTask?.cancel()
        recoveryTask?.cancel()
        ackTimeoutTask = nil
        recoveryTask = nil
        keyboardLog("[KeyboardVM] Cleared startup waiters reason=\(reason)")
    }

    private func onRecordingStarted() {
        guard isActiveInstance else {
            keyboardLog("[KeyboardVM] Ignored recordingStarted for stale instance")
            return
        }
        cancelPendingStartupWaiters(reason: "recordingStarted")
        keyboardLog("[KeyboardVM] Recording started")
        recordState = .recording
        displayText = "正在录音..."
        errorMsg = nil
    }

    private func onRecordingStopped() {
        guard isActiveInstance else {
            keyboardLog("[KeyboardVM] Ignored recordingStopped for stale instance")
            return
        }
        print("[KeyboardVM] Recording stopped (current state: \(recordState))")
        // 仅在录音状态下才转为处理中，防止收到上一次会话的迟到通知
        guard recordState == .recording else {
            print("[KeyboardVM] ⚠️ Ignoring recordingStopped — not in recording state")
            return
        }
        cancelPendingStartupWaiters(reason: "recordingStopped")
        recordState = .processing
        displayText = "处理中..."
        startProcessingTimeout()
    }

    private func onResultReady() {
        guard isActiveInstance else {
            keyboardLog("[KeyboardVM] Ignored resultReady for stale instance")
            return
        }
        print("[KeyboardVM][Inject] resultReady notification received, recordState=\(recordState), sharedState=\(sharedRead("recordingState") ?? "nil")")
        processingTimeoutTask?.cancel()
        if !consumePendingResult() {
            // 文件 I/O 可能尚未落盘，短暂重试
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                if !self.consumePendingResult() {
                    print("[KeyboardVM][Inject] ⚠️ resultReady fired but no pending result after retry, sharedState=\(sharedRead("recordingState") ?? "nil")")
                    self.recordState = .idle
                }
            }
        }
    }

    private func onAudioLevelUpdate() {
        guard isActiveInstance else { return }
        if let str = sharedRead("audioLevel"), let level = Float(str) {
            audioLevel = level
        }
    }

    /// 主 App 存活确认 — 取消 URL Scheme 兜底计时
    private func onRequestAck() {
        guard isActiveInstance else {
            keyboardLog("[KeyboardVM] Ignored requestAck for stale instance")
            return
        }
        guard recordState == .waitingMainApp else { return }
        ackTimeoutTask?.cancel()
        ackReceived = true
        displayText = "准备录音..."
        keyboardLog("[KeyboardVM] ACK received — main app alive, waiting for recording")
    }

    private func readSharedPermissionSnapshot() -> SharedPermissionSnapshot? {
        guard let raw = sharedRead("recordPermissionSnapshot") else { return nil }
        return SharedPermissionSnapshot(rawValue: raw)
    }

    private func readSharedServiceState() -> SharedServiceState? {
        guard let raw = sharedRead("serviceState") else { return nil }
        return SharedServiceState(rawValue: raw)
    }

    // ----------------------------------------
    // MARK: - 读取并消费待插入结果
    // ----------------------------------------

    /// 从共享文件读取待插入结果，插入光标处，返回是否成功消费
    @discardableResult
    private func consumePendingResult() -> Bool {
        guard let result = sharedRead("pendingResult"), !result.isEmpty else {
            print("[KeyboardVM][Inject] no pending result")
            return false
        }

        print("[KeyboardVM][Inject] found pending result chars=\(result.count), sharedState=\(sharedRead("recordingState") ?? "nil")")

        // 错误消息
        if result.hasPrefix("ERROR:") {
            sharedRemove("pendingResult")
            sharedRemove("recordingState")
            
            let errMsg = String(result.dropFirst(6))
            
            if errMsg == "NEEDS_JUMP" {
                print("[KeyboardVM][Inject] main app requested URL Scheme jump due to background mic block")
                openMainAppViaURLScheme(host: "startRecording")
                // 不设置 errorMsg，不处理 UI 报错，直接静默跳转
                recordState = .idle
                return true
            }

            errorMsg = errMsg
            displayText = ""
            recordState = .idle
            print("[KeyboardVM][Inject] error payload consumed: \(errorMsg ?? "")")
            return true
        }

        // 确保 inputVC 存在才能插入
        guard let vc = inputVC else {
            print("[KeyboardVM][Inject] ⚠️ inputVC is nil, keeping result for later")
            return false  // 不删数据，等 viewWillAppear 时重试
        }

        // 先插入，再清除
        print("[KeyboardVM][Inject] inserting text chars=\(result.count)")
        vc.textDocumentProxy.insertText(result)
        sharedRemove("pendingResult")
        sharedRemove("recordingState")
        displayText = result
        recordState = .idle
        audioLevel = 0
        print("[KeyboardVM][Inject] ✅ insertText completed")
        return true
    }

    // ----------------------------------------
    // MARK: - Public Actions
    // ----------------------------------------

    func toggleRecording() {
        switch recordState {
        case .idle:
            triggerRecording()
        case .recording:
            stopRecordingFromKeyboard()
        case .processing, .waitingMainApp:
            break
        }
    }

    func switchKeyboard() { inputVC?.advanceToNextInputMode() }
    func deleteBackward() { inputVC?.textDocumentProxy.deleteBackward() }
    func insertNewline()  { inputVC?.textDocumentProxy.insertText("\n") }

    /// 用户从主 App 返回时调用
    func onReturnFromMainApp() {
        becomeActive(reason: "onReturnFromMainApp")
        keyboardLog("[KeyboardVM] Returned from main app")
        recoverState()
    }

    // ----------------------------------------
    // MARK: - 停止录音
    // ----------------------------------------

    private func stopRecordingFromKeyboard() {
        guard isActiveInstance else {
            keyboardLog("[KeyboardVM] Ignored stopRecordingFromKeyboard for stale instance")
            return
        }
        recordState = .processing
        displayText = "处理中..."
        startProcessingTimeout()
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            kStopRecording, nil, nil, true
        )
        print("[KeyboardVM] Sent stop signal to main app")
    }

    // ----------------------------------------
    // MARK: - 智能录音触发（Darwin 优先，URL Scheme 兜底）
    // ----------------------------------------

    /// 智能录音触发：Darwin 触发 + ACK 检测，超时 fallback URL Scheme
    private func triggerRecording() {
        becomeActive(reason: "triggerRecording")
        displayText = ""
        errorMsg = nil
        ackReceived = false

        let permissionSnapshot = readSharedPermissionSnapshot()
        let serviceState = readSharedServiceState()
        let sharedRecordingState = sharedRead("recordingState")
        keyboardLog("[KeyboardDecision] tapRecord permission=\(permissionSnapshot?.rawValue ?? "nil") serviceState=\(serviceState?.rawValue ?? "nil") current=\(recordState)")

        switch sharedRecordingState {
        case "starting":
            recordState = .waitingMainApp
            displayText = "准备录音..."
            startRecoveryTimeout()
            keyboardLog("[KeyboardDecision] adopted existing shared starting before new trigger")
            return
        case "recording":
            cancelPendingStartupWaiters(reason: "triggerRecording:sharedRecording")
            recordState = .recording
            displayText = "正在录音..."
            errorMsg = nil
            keyboardLog("[KeyboardDecision] attached existing shared recording before new trigger")
            return
        case "processing":
            cancelPendingStartupWaiters(reason: "triggerRecording:sharedProcessing")
            recordState = .processing
            displayText = "处理中..."
            errorMsg = "上一段仍在处理中，请稍后"
            startProcessingTimeout()
            keyboardLog("[KeyboardDecision] attached existing shared processing before new trigger")
            return
        default:
            break
        }

        switch permissionSnapshot {
        case .granted:
            break
        case .notDetermined, .denied, .none:
            print("[KeyboardDecision] action=openMainAppForPermissionRecovery")
            openMainAppViaURLScheme(host: "restoreVoiceFlow")
            return
        }

        switch serviceState {
        case .disabledByUser:
            print("[KeyboardDecision] action=openMainAppForVoiceFlowRestore")
            openMainAppViaURLScheme(host: "restoreVoiceFlow")
            return
        case .disabledBySystemPermission:
            print("[KeyboardDecision] action=openMainAppForPermissionRecovery")
            openMainAppViaURLScheme(host: "restoreVoiceFlow")
            return
        case .recording:
            print("[KeyboardDecision] action=attachExistingRecording")
            recordState = .recording
            displayText = "正在录音..."
            return
        case .processing:
            print("[KeyboardDecision] action=blockDuringProcessing")
            recordState = .processing
            displayText = "处理中..."
            errorMsg = "上一段仍在处理中，请稍后"
            startProcessingTimeout()
            return
        case .armed:
            break
        case .none:
            print("[KeyboardDecision] action=openMainAppForUnknownStateRecovery")
            openMainAppViaURLScheme(host: "restoreVoiceFlow")
            return
        }

        sharedRemove("pendingResult")
        sharedRemove("audioLevel")
        if sharedRecordingState == "idle" || sharedRecordingState == "done" {
            sharedRemove("recordingState")
        }

        // 放弃不稳定的心跳时间戳检测，直接使用 Darwin 通知 + ACK 机制
        // 因为即使主 App 存活，后台 Timer 也极易被 iOS 降频导致心跳更新延迟，产生误判跳转
        recordState = .waitingMainApp
        displayText = "启动中..."

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            kRequestStart, nil, nil, true
        )
        keyboardLog("[KeyboardDecision] action=requestStartViaDarwin")

        // Darwin 直启在键盘切回 / 扩展重建时 ACK 可能迟到。
        // 对可直接 startRecording 的场景多给一个短宽限，避免已经起录却又误跳 URL。
        ackTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, !Task.isCancelled,
                  self.isActiveInstance,
                  self.recordState == .waitingMainApp, !self.ackReceived else { return }
            if self.adoptProgressedSharedStateIfNeeded(reason: "ackTimeout:firstCheck")
                || self.shouldSuppressFallbackBecauseProgressed() {
                self.displayText = "准备录音..."
                keyboardLog("[KeyboardDecision] fallback suppressed because shared state already progressed")
                return
            }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled,
                  self.isActiveInstance,
                  self.recordState == .waitingMainApp, !self.ackReceived else { return }
            if self.adoptProgressedSharedStateIfNeeded(reason: "ackTimeout:secondCheck")
                || self.shouldSuppressFallbackBecauseProgressed() {
                self.displayText = "准备录音..."
                keyboardLog("[KeyboardDecision] fallback suppressed on second check because shared state already progressed")
                return
            }
            let initialHost = self.fallbackHostForCurrentSharedState()
            if initialHost == "startRecording" {
                self.displayText = "准备录音..."
                keyboardLog("[KeyboardDecision] extending ACK grace before startRecording fallback")
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled,
                      self.isActiveInstance,
                      self.recordState == .waitingMainApp, !self.ackReceived else { return }
                if self.adoptProgressedSharedStateIfNeeded(reason: "ackTimeout:finalCheck")
                    || self.shouldSuppressFallbackBecauseProgressed() {
                    self.displayText = "准备录音..."
                    keyboardLog("[KeyboardDecision] fallback suppressed on final grace check because shared state already progressed")
                    return
                }
            }
            let finalHost = self.fallbackHostForCurrentSharedState()
            keyboardLog("[KeyboardDecision] noACKFallback route=\(finalHost)")
            self.openMainAppViaURLScheme(host: finalHost)
        }

        startRecoveryTimeout()
    }

    // ----------------------------------------
    // MARK: - 状态恢复超时（防卡死）
    // ----------------------------------------

    /// 15s 内未进入 recording/processing → 自动恢复 idle
    private func startRecoveryTimeout() {
        recoveryTask?.cancel()
        recoveryTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }

            let interval: UInt64 = 150_000_000
            let maxChecks = 100 // 约 15 秒

            for check in 1...maxChecks {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                guard self.isActiveInstance else { return }
                guard self.recordState == .waitingMainApp else { return }

                if self.adoptProgressedSharedStateIfNeeded(reason: "recoveryPoll#\(check)")
                    || self.shouldSuppressFallbackBecauseProgressed() {
                    self.displayText = "准备录音..."
                    keyboardLog("[KeyboardVM] Recovery poll adopted progressed state at check #\(check)")
                    return
                }

                let serviceState = self.readSharedServiceState()
                let permissionSnapshot = self.readSharedPermissionSnapshot()
                if permissionSnapshot != .granted
                    || serviceState == .disabledByUser
                    || serviceState == .disabledBySystemPermission {
                    let host = self.fallbackHostForCurrentSharedState()
                    keyboardLog("[KeyboardVM] Recovery poll detected service unavailable at check #\(check), route=\(host)")
                    self.openMainAppViaURLScheme(host: host)
                    return
                }
            }

            if self.recordState == .waitingMainApp {
                print("[KeyboardVM] ⚠️ Recovery timeout — resetting to idle")
                self.errorMsg = "录音启动超时，请重试"
                self.recordState = .idle
                self.displayText = ""
            }
        }
    }

    private func shouldSuppressFallbackBecauseProgressed() -> Bool {
        let sharedState = sharedRead("recordingState") ?? "nil"
        let serviceState = readSharedServiceState()?.rawValue ?? "nil"
        let progressed = sharedState == "starting"
            || sharedState == "recording"
            || sharedState == "processing"
            || serviceState == SharedServiceState.recording.rawValue
            || serviceState == SharedServiceState.processing.rawValue
        keyboardLog("[KeyboardDecision] fallback check shared recordingState=\(sharedState) serviceState=\(serviceState) progressed=\(progressed)")
        return progressed
    }

    private func fallbackHostForCurrentSharedState() -> String {
        let permissionSnapshot = readSharedPermissionSnapshot()
        let serviceState = readSharedServiceState()

        if permissionSnapshot != .granted {
            return "restoreVoiceFlow"
        }

        switch serviceState {
        case .disabledByUser, .disabledBySystemPermission:
            return "restoreVoiceFlow"
        default:
            return "startRecording"
        }
    }

    @discardableResult
    private func adoptProgressedSharedStateIfNeeded(reason: String) -> Bool {
        let sharedState = sharedRead("recordingState") ?? "nil"
        let serviceState = readSharedServiceState()

        switch serviceState {
        case .recording:
            cancelPendingStartupWaiters(reason: "\(reason):serviceRecording")
            recordState = .recording
            displayText = "正在录音..."
            errorMsg = nil
            keyboardLog("[KeyboardVM] Adopted serviceState -> recording reason=\(reason)")
            return true
        case .processing:
            cancelPendingStartupWaiters(reason: "\(reason):serviceProcessing")
            recordState = .processing
            displayText = "处理中..."
            startProcessingTimeout()
            keyboardLog("[KeyboardVM] Adopted serviceState -> processing reason=\(reason)")
            return true
        default:
            break
        }

        switch sharedState {
        case "recording":
            cancelPendingStartupWaiters(reason: "\(reason):sharedRecording")
            recordState = .recording
            displayText = "正在录音..."
            errorMsg = nil
            keyboardLog("[KeyboardVM] Adopted shared state -> recording reason=\(reason)")
            return true
        case "processing":
            cancelPendingStartupWaiters(reason: "\(reason):sharedProcessing")
            recordState = .processing
            displayText = "处理中..."
            startProcessingTimeout()
            keyboardLog("[KeyboardVM] Adopted shared state -> processing reason=\(reason)")
            return true
        case "starting":
            displayText = "准备录音..."
            keyboardLog("[KeyboardVM] Shared state still starting reason=\(reason)")
            return true
        default:
            break
        }
        return false
    }

    // ----------------------------------------
    // MARK: - 处理超时（防止 processing 卡死）
    // ----------------------------------------

    /// 30s 内未收到结果 → 自动恢复 idle + 尝试读取残留结果
    private func startProcessingTimeout() {
        processingTimeoutTask?.cancel()
        processingTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.isActiveInstance else { return }
            guard self.recordState == .processing else { return }
            // 超时前最后尝试读取结果
            if self.consumePendingResult() { return }
            let sharedState = sharedRead("recordingState") ?? "nil"
            let hasPendingResult = (sharedRead("pendingResult")?.isEmpty == false)
            let inputVCMissing = self.inputVC == nil
            print("[KeyboardVM][Timeout] processing timeout sharedState=\(sharedState) hasPendingResult=\(hasPendingResult) inputVCNil=\(inputVCMissing)")
            self.errorMsg = self.processingTimeoutMessage(sharedState: sharedState, hasPendingResult: hasPendingResult, inputVCMissing: inputVCMissing)
            self.recordState = .idle
            self.displayText = ""
        }
    }

    private func processingTimeoutMessage(sharedState: String, hasPendingResult: Bool, inputVCMissing: Bool) -> String {
        if inputVCMissing || hasPendingResult || sharedState == "done" {
            return "结果回填超时，请返回键盘重试"
        }
        return "语音处理超时，请重试"
    }

    /// URL Scheme 兜底：跳转主 App 做恢复或启动
    /// Extension 进程没有 UIApplication.shared，必须通过 extensionContext 或 selector 打开 URL
    private func openMainAppViaURLScheme(host: String) {
        guard isActiveInstance else {
            keyboardLog("[KeyboardDecision] skipped openURL for stale instance host=\(host)")
            return
        }
        guard let url = URL(string: "voiceflow://\(host)") else {
            errorMsg = "无法打开主应用"
            recordState = .idle
            return
        }

        keyboardLog("[KeyboardDecision] openURL=\(url.absoluteString)")
        displayText = "跳转中..."

        // 优先使用 extensionContext（官方 API，需要 Full Access）
        if let context = inputVC?.extensionContext {
            context.open(url) { [weak self] ok in
                Task { @MainActor [weak self] in
                    if !ok {
                        keyboardLog("[KeyboardVM] extensionContext.open failed, trying responder chain")
                        self?.openURLViaResponderChain(url)
                    }
                }
            }
            return
        }

        // extensionContext 不可用时走 responder chain
        openURLViaResponderChain(url)
    }

    /// 通过 responder chain 查找 UIApplication 并打开 URL（备用路径）
    private func openURLViaResponderChain(_ url: URL) {
        var responder: UIResponder? = inputVC
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:]) { ok in
                    Task { @MainActor [weak self] in
                        if !ok {
                            self?.errorMsg = "请先手动打开 VoiceFlow 主应用"
                            self?.recordState = .idle
                        }
                    }
                }
                return
            }
            responder = r.next
        }

        errorMsg = "请在系统设置中开启键盘「完全访问」权限"
        recordState = .idle
    }
}
