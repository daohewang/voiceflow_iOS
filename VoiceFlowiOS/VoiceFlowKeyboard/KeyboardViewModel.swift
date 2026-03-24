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
        print("[KeyboardVM] ❌ containerURL is nil")
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

    weak var inputVC: UIInputViewController?

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
        setupDarwinObservers()
        recoverState()
    }

    deinit {
        // 移除全部 Darwin 通知观察者，防止泄漏 + use-after-free
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), ptr
        )
        print("[KeyboardVM] Observers removed in deinit")
    }

    // ----------------------------------------
    // MARK: - 状态恢复（键盘被 iOS 重建后调用）
    // ----------------------------------------

    /// 键盘进程被重建后，从共享文件恢复当前录音状态
    private func recoverState() {
        // 先检查有没有待插入的结果
        if consumePendingResult() { return }

        // 检查录音是否在进行中
        if let state = sharedRead("recordingState") {
            switch state {
            case "recording":
                recordState = .recording
                displayText = "正在录音..."
                print("[KeyboardVM] Recovered state: recording")
            case "processing":
                recordState = .processing
                displayText = "处理中..."
                print("[KeyboardVM] Recovered state: processing")
            case "done":
                // 上一次录音已完成但结果可能已被消费，视为 idle
                sharedRemove("recordingState")
                recordState = .idle
                print("[KeyboardVM] Recovered state: done → treated as idle")
            default:
                print("[KeyboardVM] Recovered state: idle (\(state))")
                recordState = .idle
                displayText = ""
            }
        } else {
            print("[KeyboardVM] No shared state file")
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
        print("[KeyboardVM] Darwin observers registered")
    }

    // ----------------------------------------
    // MARK: - Darwin Notification Handlers
    // ----------------------------------------

    private func onRecordingStarted() {
        recoveryTask?.cancel()
        print("[KeyboardVM] Recording started")
        recordState = .recording
        displayText = "正在录音..."
        errorMsg = nil
    }

    private func onRecordingStopped() {
        print("[KeyboardVM] Recording stopped (current state: \(recordState))")
        // 仅在录音状态下才转为处理中，防止收到上一次会话的迟到通知
        guard recordState == .recording else {
            print("[KeyboardVM] ⚠️ Ignoring recordingStopped — not in recording state")
            return
        }
        recordState = .processing
        displayText = "处理中..."
        startProcessingTimeout()
    }

    private func onResultReady() {
        print("[KeyboardVM] Result ready notification received")
        processingTimeoutTask?.cancel()
        if !consumePendingResult() {
            // 文件 I/O 可能尚未落盘，短暂重试
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                if !self.consumePendingResult() {
                    print("[KeyboardVM] ⚠️ resultReady fired but no pending result after retry")
                    self.recordState = .idle
                }
            }
        }
    }

    private func onAudioLevelUpdate() {
        if let str = sharedRead("audioLevel"), let level = Float(str) {
            audioLevel = level
        }
    }

    /// 主 App 存活确认 — 取消 URL Scheme 兜底计时
    private func onRequestAck() {
        guard recordState == .waitingMainApp else { return }
        ackTimeoutTask?.cancel()
        ackReceived = true
        displayText = "准备录音..."
        print("[KeyboardVM] ACK received — main app alive, waiting for recording")
    }

    // ----------------------------------------
    // MARK: - 读取并消费待插入结果
    // ----------------------------------------

    /// 从共享文件读取待插入结果，插入光标处，返回是否成功消费
    @discardableResult
    private func consumePendingResult() -> Bool {
        guard let result = sharedRead("pendingResult"), !result.isEmpty else {
            print("[KeyboardVM] No pending result")
            return false
        }

        print("[KeyboardVM] Found result: \(result.prefix(50))...")

        // 错误消息
        if result.hasPrefix("ERROR:") {
            sharedRemove("pendingResult")
            sharedRemove("recordingState")
            
            let errMsg = String(result.dropFirst(6))
            
            if errMsg == "NEEDS_JUMP" {
                print("[KeyboardVM] Main app requested URL Scheme jump due to background mic block.")
                openMainAppViaURLScheme()
                return true
            }

            errorMsg = errMsg
            displayText = ""
            recordState = .idle
            print("[KeyboardVM] Error from main app: \(errorMsg ?? "")")
            return true
        }

        // 确保 inputVC 存在才能插入
        guard let vc = inputVC else {
            print("[KeyboardVM] ⚠️ inputVC is nil, keeping result for later")
            return false  // 不删数据，等 viewWillAppear 时重试
        }

        // 先插入，再清除
        vc.textDocumentProxy.insertText(result)
        sharedRemove("pendingResult")
        sharedRemove("recordingState")
        displayText = result
        recordState = .idle
        audioLevel = 0
        print("[KeyboardVM] ✅ Inserted: \(result.prefix(50))...")
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
        print("[KeyboardVM] Returned from main app")
        recoverState()
    }

    // ----------------------------------------
    // MARK: - 停止录音
    // ----------------------------------------

    private func stopRecordingFromKeyboard() {
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
        displayText = ""
        errorMsg = nil
        ackReceived = false
        sharedRemove("pendingResult")
        sharedRemove("audioLevel")
        sharedRemove("recordingState")  // 清除上次残留的状态文件

        // 放弃不稳定的心跳时间戳检测，直接使用 Darwin 通知 + ACK 机制
        // 因为即使主 App 存活，后台 Timer 也极易被 iOS 降频导致心跳更新延迟，产生误判跳转
        recordState = .waitingMainApp
        displayText = "启动中..."

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            kRequestStart, nil, nil, true
        )
        print("[KeyboardVM] Sent Darwin requestStart")

        // 600ms 超时：若无 ACK → 主App极可能被睡眠/杀死，兜底 URL Scheme
        ackTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled,
                  self.recordState == .waitingMainApp, !self.ackReceived else { return }
            print("[KeyboardVM] No ACK in 600ms, falling back to URL Scheme")
            self.openMainAppViaURLScheme()
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
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.recordState == .waitingMainApp {
                print("[KeyboardVM] ⚠️ Recovery timeout — resetting to idle")
                self.errorMsg = "录音启动超时，请重试"
                self.recordState = .idle
                self.displayText = ""
            }
        }
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
            guard self.recordState == .processing else { return }
            // 超时前最后尝试读取结果
            if self.consumePendingResult() { return }
            print("[KeyboardVM] ⚠️ Processing timeout — resetting to idle")
            self.errorMsg = "处理超时，请重试"
            self.recordState = .idle
            self.displayText = ""
        }
    }

    /// URL Scheme 兜底：跳转主 App 前台启动录音
    /// Extension 进程没有 UIApplication.shared，必须通过 extensionContext 或 selector 打开 URL
    private func openMainAppViaURLScheme() {
        guard let url = URL(string: "voiceflow://startRecording") else {
            errorMsg = "无法打开主应用"
            recordState = .idle
            return
        }

        displayText = "跳转中..."

        // 优先使用 extensionContext（官方 API，需要 Full Access）
        if let context = inputVC?.extensionContext {
            context.open(url) { [weak self] ok in
                Task { @MainActor [weak self] in
                    if !ok {
                        print("[KeyboardVM] extensionContext.open failed, trying responder chain")
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
