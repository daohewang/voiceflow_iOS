/**
 * [INPUT]: 依赖 AVFoundation (AVAudioSession)
 * [OUTPUT]: 对外提供 PermissionManager 单例，检查/请求麦克风权限
 * [POS]: VoiceFlowiOS/Core 的权限中枢，被 AppState 和录音流程调用
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation
import AVFoundation

// ========================================
// MARK: - Permission Manager (iOS)
// ========================================

@MainActor
@Observable
final class PermissionManager {

    static let shared = PermissionManager()

    // ----------------------------------------
    // MARK: - Permission Status
    // ----------------------------------------

    enum PermissionStatus: Equatable {
        case notDetermined
        case granted
        case denied
    }

    private(set) var microphoneStatus: PermissionStatus = .notDetermined

    var allGranted: Bool { microphoneStatus == .granted }
    var needsGuidance: Bool { microphoneStatus == .denied }

    private init() { checkMicrophoneStatus() }

    // ----------------------------------------
    // MARK: - Public API
    // ----------------------------------------

    /// 刷新麦克风权限状态
    func refreshStatus() { checkMicrophoneStatus() }

    /// 请求麦克风权限（iOS 使用 AVAudioSession）
    func requestMicrophone() async -> Bool {
        return await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.microphoneStatus = granted ? .granted : .denied
                    self?.syncSharedSnapshot()
                    cont.resume(returning: granted)
                }
            }
        }
    }

    /// 检查当前麦克风权限状态
    func checkMicrophoneStatus() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:       microphoneStatus = .granted
        case .denied:        microphoneStatus = .denied
        case .undetermined:  microphoneStatus = .notDetermined
        @unknown default:    microphoneStatus = .notDetermined
        }
        syncSharedSnapshot()
    }

    private func syncSharedSnapshot() {
        let snapshot: SharedStore.PermissionSnapshot
        switch microphoneStatus {
        case .notDetermined:
            snapshot = .notDetermined
        case .granted:
            snapshot = .granted
        case .denied:
            snapshot = .denied
        }
        SharedStore.writePermissionSnapshot(snapshot)
    }
}
