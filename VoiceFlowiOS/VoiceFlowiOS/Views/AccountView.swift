/**
 * [INPUT]: 依赖 AppState、KeychainManager，复用 Color+Hex 扩展
 * [OUTPUT]: 对外提供 AccountView，设置页 - API Key 配置 + 服务商选择
 * [POS]: ContentView TabContentRouter 的 .account case 目标视图
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI
import Speech

// ========================================
// MARK: - Account View（设置页）
// ========================================

struct AccountView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                // ----------------------------------------
                // MARK: - 大标题 Header
                // ----------------------------------------

                AccountHeader()

                // ----------------------------------------
                // MARK: - 通知 Banner
                // ----------------------------------------

                NotificationBanner()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)

                // ----------------------------------------
                // MARK: - API 设置区块
                // ----------------------------------------

                AccountSectionHeader(title: "API 密钥")
                    .padding(.top, 24)

                AccountCard {
                    APIKeyRow(
                        icon: "waveform",
                        title: "ElevenLabs API Key",
                        subtitle: "语音识别服务",
                        keychainKey: .elevenLabs
                    )
                    RowDivider()
                    APIKeyRow(
                        icon: "network",
                        title: "OpenRouter API Key",
                        subtitle: "多模型路由服务",
                        keychainKey: .openRouter
                    )
                    RowDivider()
                    APIKeyRow(
                        icon: "cpu",
                        title: "DeepSeek API Key",
                        subtitle: "DeepSeek 大语言模型",
                        keychainKey: .deepSeek
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // ----------------------------------------
                // MARK: - 服务商选择区块
                // ----------------------------------------

                AccountSectionHeader(title: "服务商选择")
                    .padding(.top, 24)

                AccountCard {
                    LLMProviderRow()
                    RowDivider()
                    ASRProviderRow()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // ----------------------------------------
                // MARK: - VoiceFlow 服务区块
                // ----------------------------------------

                AccountSectionHeader(title: "VoiceFlow 服务")
                    .padding(.top, 24)

                AccountCard {
                    AutoClosePolicyRow()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // ----------------------------------------
                // MARK: - 应用信息
                // ----------------------------------------

                AccountSectionHeader(title: "应用信息")
                    .padding(.top, 24)

                AccountCard {
                    PermissionCheckRow()
                    RowDivider()
                    AccountRow(icon: "info.circle",  title: "关于 VoiceFlow")
                    RowDivider()
                    AccountRow(icon: "doc.text",     title: "版本说明", badge: "v1.0.0")
                    RowDivider()
                    AccountRow(icon: "questionmark.circle", title: "帮助中心", trailing: .externalLink)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .contentMargins(.bottom, 16, for: .scrollContent)
        .background(Color(hex: "#fcfcfc").ignoresSafeArea(edges: .top))
    }
}

// ========================================
// MARK: - Account Header
// ========================================

private struct AccountHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                AccHeaderBtn(icon: "chevron.left")
                Spacer()
                AccHeaderBtn(icon: "ellipsis")
            }
            Text("设置")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color(hex: "#0f172a"))
                .tracking(-0.9)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 24)
    }
}

private struct AccHeaderBtn: View {
    let icon: String
    var body: some View {
        Button(action: {}) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "#0f172a"))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }
}

// ========================================
// MARK: - Notification Banner
// ========================================

private struct NotificationBanner: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color(hex: "#f1f5f9")).frame(width: 40, height: 40)
                    Image(systemName: "bell.slash")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "#64748b"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("通知：已关闭")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: "#0f172a"))
                    Text("开启通知以获取账户动态和重要提醒。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "#64748b"))
                }
                Spacer()
            }
            Button(action: {}) {
                Text("开启通知")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.black))
            }
            .buttonStyle(.plain)
        }
        .padding(21)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: "#f1f5f9"), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 40, x: 0, y: 10)
        )
    }
}

// ========================================
// MARK: - Section Header
// ========================================

private struct AccountSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: "#94a3b8"))
            .tracking(1.2)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
    }
}

// ========================================
// MARK: - Account Card
// ========================================

private struct AccountCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: "#f1f5f9"), lineWidth: 1))
                    .shadow(color: .black.opacity(0.05), radius: 40, x: 0, y: 10)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// ========================================
// MARK: - API Key Row
// ========================================

private struct APIKeyRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let keychainKey: KeychainManager.Key

    @State private var apiKey: String = ""
    @State private var isEditing: Bool = false
    @State private var isRevealed: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#475569"))
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#0f172a"))
                if isEditing {
                    HStack(spacing: 4) {
                        Group {
                            if isRevealed {
                                TextField("粘贴 API Key", text: $apiKey)
                            } else {
                                SecureField("粘贴 API Key", text: $apiKey)
                            }
                        }
                        .font(.system(size: 13))
                        .focused($isFocused)
                        .onSubmit { saveKey() }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            isRevealed.toggle()
                        } label: {
                            Image(systemName: isRevealed ? "eye.slash" : "eye")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#94a3b8"))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text(maskedKey)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#64748b"))
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#94a3b8"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 编辑 / 保存按钮
            Button {
                if isEditing {
                    saveKey()
                } else {
                    startEditing()
                }
            } label: {
                Text(isEditing ? "保存" : "编辑")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "#0f172a"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.white)
                            .overlay(Capsule().stroke(Color(hex: "#e2e8f0"), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .onAppear { loadKey() }
    }

    private var maskedKey: String {
        guard let key = try? KeychainManager.shared.get(keychainKey), !key.isEmpty else {
            return "未配置"
        }
        let prefix = key.prefix(8)
        return "\(prefix)••••••••"
    }

    private func loadKey() {
        apiKey = (try? KeychainManager.shared.get(keychainKey)) ?? ""
    }

    private func startEditing() {
        loadKey()
        isEditing = true
        isRevealed = false
        isFocused = true
    }

    private func saveKey() {
        try? KeychainManager.shared.set(apiKey, for: keychainKey)
        isEditing = false
        isFocused = false
    }
}

// ========================================
// MARK: - LLM Provider Row
// ========================================

private struct LLMProviderRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#475569"))
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("LLM 提供商")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#0f172a"))
                Text("用于 AI 文字润色")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#64748b"))
            }

            Spacer()

            // 只展示支持的提供商
            Picker("LLM 提供商", selection: $state.llmProviderType) {
                ForEach([LLMProviderType.openRouter, .deepSeek], id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .tint(Color(hex: "#0f172a"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// ========================================
// MARK: - ASR Provider Row
// ========================================

private struct ASRProviderRow: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#475569"))
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("ASR 提供商")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#0f172a"))
                Text("语音识别服务")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#64748b"))
            }

            Spacer()

            Text("ElevenLabs")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#64748b"))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: "#f1f5f9")))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// ========================================
// MARK: - Auto Close Policy Row
// ========================================

private struct AutoClosePolicyRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        HStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#475569"))
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("自动关闭")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#0f172a"))
                Text("VoiceFlow 在待命态下的自动关闭策略")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#64748b"))
            }

            Spacer()

            Picker("自动关闭", selection: $state.autoClosePolicy) {
                ForEach(AppState.AutoClosePolicy.allCases, id: \.self) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .pickerStyle(.menu)
            .tint(Color(hex: "#0f172a"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// ========================================
// MARK: - Account Row
// ========================================

private struct AccountRow: View {
    enum TrailingItem { case chevron, externalLink }

    let icon: String
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var trailing: TrailingItem = .chevron

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#475569"))
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "#0f172a"))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(hex: "#64748b"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(hex: "#f1f5f9")))
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#64748b"))
                    }
                }

                Spacer()

                switch trailing {
                case .chevron:
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(hex: "#94a3b8"))
                case .externalLink:
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(hex: "#94a3b8"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(hex: "#f8fafc"))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

// ========================================
// MARK: - Permission Check Row
// ========================================

private struct PermissionCheckRow: View {
    @State private var micStatus: String = "检查中..."
    @State private var speechStatus: String = "检查中..."
    @State private var showDetail = false
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#f1f5f9"))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(allGranted ? Color.green : Color.orange)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("权限状态")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "#0f172a"))
                    Text(statusDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#64748b"))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: "#94a3b8"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .task {
            await checkPermissions()
        }
        .sheet(isPresented: $showDetail) {
            PermissionDetailView(
                micStatus: micStatus,
                speechStatus: speechStatus
            )
        }
    }
    
    private var allGranted: Bool {
        micStatus == "已授权" && speechStatus == "已授权"
    }
    
    private var statusDescription: String {
        if allGranted {
            return "所有权限已就绪"
        } else {
            return "需要授予必要权限"
        }
    }
    
    @MainActor
    private func checkPermissions() async {
        // 检查麦克风
        PermissionManager.shared.checkMicrophoneStatus()
        let micGranted = PermissionManager.shared.microphoneStatus == .granted
        micStatus = micGranted ? "已授权" : "未授权"
        
        // 检查语音识别
        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        switch speechAuth {
        case .authorized: speechStatus = "已授权"
        case .denied: speechStatus = "已拒绝"
        case .restricted: speechStatus = "受限制"
        case .notDetermined: speechStatus = "未询问"
        @unknown default: speechStatus = "未知"
        }
    }
}

// ========================================
// MARK: - Permission Detail View
// ========================================

private struct PermissionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let micStatus: String
    let speechStatus: String
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    PermissionDetailRow(
                        icon: "mic.fill",
                        title: "麦克风权限",
                        status: micStatus,
                        description: "用于录制您的语音输入"
                    )
                    
                    PermissionDetailRow(
                        icon: "waveform",
                        title: "语音识别权限",
                        status: speechStatus,
                        description: "用于将语音转换为文字"
                    )
                } header: {
                    Text("必需权限")
                } footer: {
                    Text("这些权限对于 VoiceFlow 的正常运行是必需的。如果权限被拒绝，请到系统设置中手动开启。")
                }
                
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "gear")
                            Text("打开系统设置")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                        }
                    }
                } header: {
                    Text("操作")
                }
            }
            .navigationTitle("权限状态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PermissionDetailRow: View {
    let icon: String
    let title: String
    let status: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(statusColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(status)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        if status == "已授权" {
            return .green
        } else if status == "已拒绝" {
            return .red
        } else {
            return .orange
        }
    }
}

// ========================================
// MARK: - Preview
// ========================================

#Preview {
    AccountView()
        .environment(AppState.shared)
}
