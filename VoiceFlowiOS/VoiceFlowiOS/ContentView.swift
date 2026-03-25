/**
 * [INPUT]: 依赖 AppState、HomeView、BottomNavBar、AVFoundation
 * [OUTPUT]: 对外提供 ContentView 根视图，含权限引导 + TabBar 导航
 * [POS]: VoiceFlowiOS 的根视图容器，首次启动拦截麦克风权限引导
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI
import AVFoundation

// ========================================
// MARK: - Content View
// ========================================

struct ContentView: View {

    @Environment(AppState.self) private var appState
    @State private var permissionsReady = false

    var body: some View {
        ZStack {
            Color(hex: "#fcfcfc").ignoresSafeArea()

            if permissionsReady {
                if appState.isKeyboardRecording {
                    ReturnGuideView()
                } else {
                    MainAppView()
                }
            } else {
                PermissionOnboardingView {
                    permissionsReady = true
                    // 键盘唤起后，只有“真正开始录音”场景才在授权完成后自动起录。
                    if appState.isKeyboardRecording && appState.keyboardLaunchBehavior == .startRecording {
                        Task { await appState.startRecording() }
                    }
                }
            }
        }
        .onAppear {
            // 权限已授予 → 跳过引导
            if AVAudioSession.sharedInstance().recordPermission == .granted {
                permissionsReady = true
            }
        }
        .onChange(of: appState.isKeyboardRecording) { _, isRecording in
            // 键盘唤起时，仅在权限已授予情况下跳过引导
            // 未授权 → 保持 PermissionOnboardingView 显示，引导用户授权
            if isRecording && AVAudioSession.sharedInstance().recordPermission == .granted {
                permissionsReady = true
            }
        }
    }
}

// ========================================
// MARK: - Main App View
// ========================================

private struct MainAppView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabContentView(selectedTab: appState.selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) { BottomNavBar() }
    }
}

private struct TabContentView: View {
    let selectedTab: TabItem

    var body: some View {
        switch selectedTab {
        case .home:       HomeView()
        case .history:    HistoryView()
        case .dictionary: DictionaryView()
        case .account:    AccountView()
        }
    }
}

// ========================================
// MARK: - 权限引导页（仅麦克风，回调驱动）
// ========================================

private struct PermissionOnboardingView: View {
    let onComplete: () -> Void

    @State private var micGranted = false
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.black)
                    .frame(width: 80, height: 80)
                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 24)

            Text("VoiceFlow")
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 8)

            Text("语音输入，智能润色")
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "#71717a"))
                .padding(.bottom, 40)

            // 麦克风权限状态
            PermissionRow(icon: "mic.fill", title: "麦克风",
                          desc: "录制语音进行识别", granted: micGranted)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)

            // 操作按钮
            Button {
                guard !isRequesting else { return }
                if micGranted {
                    onComplete()
                } else {
                    isRequesting = true
                    requestMicrophone()
                }
            } label: {
                Text(buttonTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.black))
            }
            .disabled(isRequesting)
            .padding(.horizontal, 32)

            Spacer()
        }
        .onAppear { refreshStatus() }
    }

    private var buttonTitle: String {
        if isRequesting { return "授权中..." }
        if micGranted { return "开始使用" }
        return "开启权限"
    }

    private func refreshStatus() {
        micGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        if micGranted { onComplete() }
    }

    // 纯回调，不用 async/await，不会产生 CheckedContinuation 泄漏
    private func requestMicrophone() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                micGranted = granted
                isRequesting = false
                if granted { onComplete() }
            }
        }
    }
}

// ========================================
// MARK: - Permission Row
// ========================================

private struct PermissionRow: View {
    let icon: String
    let title: String
    let desc: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(granted ? Color.green.opacity(0.1) : Color(hex: "#f1f5f9"))
                    .frame(width: 48, height: 48)
                Image(systemName: granted ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 20))
                    .foregroundStyle(granted ? .green : Color(hex: "#64748b"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(desc).font(.system(size: 13)).foregroundStyle(Color(hex: "#94a3b8"))
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(.white)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }
}

// ========================================
// MARK: - Return Guide View
// ========================================

private struct ReturnGuideView: View {
    @Environment(AppState.self) private var appState

    private var titleText: String {
        switch appState.keyboardLaunchBehavior {
        case .restoreOnly:
            return "VoiceFlow 已恢复"
        case .none, .startRecording:
            return "录音已在后台开启"
        }
    }

    private var subtitleText: String {
        switch appState.keyboardLaunchBehavior {
        case .restoreOnly:
            return "请点击屏幕左上角的返回按钮\n回到语音输入键盘继续录音"
        case .none, .startRecording:
            return "请点击屏幕左上角的返回按钮\n回到聊天输入界面"
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 引导箭头，指向左上角
            Image(systemName: "arrow.up.left")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.blue)
                .padding(.bottom, 20)
            
            Text(titleText)
                .font(.system(size: 24, weight: .bold))
            
            Text(subtitleText)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "#71717a"))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#fcfcfc"))
    }
}

// ========================================
// MARK: - Preview
// ========================================

#Preview {
    ContentView()
        .environment(AppState.shared)
}
