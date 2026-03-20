/**
 * [INPUT]: 依赖 UIKit、Darwin Notification，通过 App Group 文件共享录音结果
 * [OUTPUT]: 对外提供 KeyboardViewModel，管理录音触发→读取结果→插入流程
 * [POS]: VoiceFlowKeyboard Extension 的状态层，被 KeyboardView 消费
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 *
 * 架构说明：
 *   1. 键盘 Extension 只负责"触发"和"接收结果"
 *   2. 真正的录音由主 App 在后台执行
 *   3. Darwin Notification 做信号通知，文件做数据传递
 *   4. UserDefaults 在键盘进程中不可靠(cfprefsd 限制)，改用文件 I/O
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
            default:
                print("[KeyboardVM] Recovered state: idle (\(state))")
            }
        } else {
            print("[KeyboardVM] No shared state file")
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
        print("[KeyboardVM] Recording started")
        recordState = .recording
        displayText = "正在录音..."
        errorMsg = nil
    }

    private func onRecordingStopped() {
        print("[KeyboardVM] Recording stopped")
        recordState = .processing
        displayText = "处理中..."
    }

    private func onResultReady() {
        print("[KeyboardVM] Result ready notification received")
        if !consumePendingResult() {
            print("[KeyboardVM] ⚠️ resultReady fired but no pending result in Keychain")
            recordState = .idle
        }
    }

    private func onAudioLevelUpdate() {
        if let str = sharedRead("audioLevel"), let level = Float(str) {
            audioLevel = level
        }
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
            errorMsg = String(result.dropFirst(6))
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
            openMainAppForRecording()
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
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            kStopRecording, nil, nil, true
        )
        print("[KeyboardVM] Sent stop signal to main app")
    }

    // ----------------------------------------
    // MARK: - 打开主 App 开始录音
    // ----------------------------------------

    private func openMainAppForRecording() {
        displayText = ""
        errorMsg = nil

        // 清除旧数据
        sharedRemove("pendingResult")
        sharedRemove("audioLevel")

        recordState = .waitingMainApp
        displayText = "跳转中..."

        guard let url = URL(string: "voiceflow://startRecording") else {
            errorMsg = "无法打开主应用"
            recordState = .idle
            return
        }

        // 遍历 responder chain 找 UIApplication 打开 URL
        print("[KeyboardVM] inputVC = \(String(describing: inputVC))")
        var responder: UIResponder? = inputVC
        var depth = 0
        while let r = responder {
            depth += 1
            print("[KeyboardVM] responder[\(depth)] = \(type(of: r))")
            if let app = r as? UIApplication {
                print("[KeyboardVM] ✅ Found UIApplication at depth \(depth)")
                app.open(url, options: [:]) { ok in
                    Task { @MainActor [weak self] in
                        print("[KeyboardVM] Open URL result: \(ok)")
                        if !ok {
                            self?.errorMsg = "URL 打开失败"
                            self?.recordState = .idle
                        }
                    }
                }
                return
            }
            responder = r.next
        }

        print("[KeyboardVM] ❌ UIApplication not found after \(depth) responders")
        errorMsg = "无法打开主应用"
        recordState = .idle
    }
}
