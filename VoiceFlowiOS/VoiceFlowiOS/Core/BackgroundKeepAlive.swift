/**
 * [INPUT]: 依赖 AVFoundation (AVAudioPlayer, AVAudioSession interruption), 依赖 SharedStore 写心跳
 * [OUTPUT]: 对外提供 BackgroundKeepAlive 单例，静音播放维持后台存活 + 心跳时间戳
 * [POS]: VoiceFlowiOS/Core 的后台保活基础设施，被 VoiceFlowiOSApp 管理生命周期
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 *
 * 架构说明：
 *   iOS 会终止无活跃音频会话的后台进程。
 *   通过循环播放静音音频，维持 UIBackgroundModes:audio 的合法性，
 *   使主 App 能长期驻留后台，随时响应键盘的 Darwin Notification 录音请求。
 *   参考豆包/Wispr Flow 的后台常驻策略（specs/hold.md）。
 */

import AVFoundation

// ========================================
// MARK: - Background Keep Alive
// ========================================

/// 静音播放保活器 — 让主 App 在后台持续存活
/// 原理：AVAudioPlayer 循环播放 1 秒静音 WAV，消耗极低，
///       但足以让 iOS 认为 App 正在使用音频，不回收进程。
@MainActor
final class BackgroundKeepAlive {

    static let shared = BackgroundKeepAlive()

    // ----------------------------------------
    // MARK: - State
    // ----------------------------------------

    private var player: AVAudioPlayer?
    private var heartbeatTimer: Timer?
    private(set) var isActive = false

    // ----------------------------------------
    // MARK: - Init
    // ----------------------------------------

    private init() {
        // 监听音频中断（来电/Siri 等），中断结束后自动恢复播放
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            // 在闭包内提取值，避免跨隔离域传递 Notification
            let typeVal = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                guard let typeVal,
                      let type = AVAudioSession.InterruptionType(rawValue: typeVal)
                else { return }
                if type == .ended, let self, self.isActive {
                    self.player?.play()
                    print("[KeepAlive] Resumed after interruption")
                }
            }
        }
    }

    // ----------------------------------------
    // MARK: - Control
    // ----------------------------------------

    /// 启动静音播放，维持后台音频会话
    func start() {
        guard !isActive else { return }

        guard let p = try? AVAudioPlayer(data: Self.silentWAV) else {
            print("[KeepAlive] ❌ AVAudioPlayer init failed")
            return
        }

        p.numberOfLoops = -1
        p.volume = 0.0
        p.play()

        player = p
        isActive = true
        startHeartbeat()  // 立即写心跳 + 启动定时器
        print("[KeepAlive] ✅ Started silent playback + heartbeat")
    }

    /// 停止静音播放（前台时释放资源）
    func stop() {
        guard isActive else { return }
        player?.stop()
        player = nil
        isActive = false
        stopHeartbeat()
        print("[KeepAlive] Stopped")
    }

    // ----------------------------------------
    // MARK: - Heartbeat（让键盘知道主 App 存活）
    // ----------------------------------------

    private func startHeartbeat() {
        writeHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.writeHeartbeat() }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        SharedStore.remove("heartbeat")
    }

    private func writeHeartbeat() {
        SharedStore.write("heartbeat", String(Date().timeIntervalSince1970))
    }

    // ----------------------------------------
    // MARK: - Silent WAV (1s, 16kHz, mono, 16-bit)
    // ----------------------------------------

    /// 预生成的 32044 字节静音 WAV — 比文件资源更轻量
    private static let silentWAV: Data = {
        let sr: UInt32  = 16000
        let ch: UInt16  = 1
        let bps: UInt16 = 16
        let pcmBytes    = Int(sr) * Int(ch) * Int(bps / 8)

        var d = Data(capacity: 44 + pcmBytes)

        func u16(_ v: UInt16) { var le = v.littleEndian; Swift.withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { var le = v.littleEndian; Swift.withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }

        // RIFF header
        d.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        u32(UInt32(36 + pcmBytes))
        d.append(contentsOf: [0x57, 0x41, 0x56, 0x45])

        // fmt chunk
        d.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        u32(16); u16(1); u16(ch); u32(sr)
        u32(sr * UInt32(ch) * UInt32(bps / 8))
        u16(ch * (bps / 8)); u16(bps)

        // data chunk (all zeros = silence)
        d.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        u32(UInt32(pcmBytes))
        d.append(Data(count: pcmBytes))

        return d
    }()
}
