/**
 * [INPUT]: 依赖 AppState.isVoiceFlowEnabled、AppState.recordingStatus
 * [OUTPUT]: 对外提供 MainToggleCard，VoiceFlow 开关卡片，开关触发真实录音
 * [POS]: HomeView 的核心控制组件，用户主要交互区域
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ========================================
// MARK: - Main Toggle Card
// ========================================

struct MainToggleCard: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {

            // ----------------------------------------
            // MARK: - Toggle 区域
            // ----------------------------------------

            HStack(alignment: .top, spacing: 12) {

                // 标题 + 描述
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.isVoiceFlowEnabled ? "VoiceFlow 已开启" : "VoiceFlow 已关闭")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)

                    Text(statusDescription)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(hex: "#71717a"))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 黑色圆角 Toggle
                Toggle("", isOn: Binding(
                    get: { appState.isVoiceFlowEnabled },
                    set: { enabled in
                        appState.isVoiceFlowEnabled = enabled
                        Task {
                            if enabled {
                                await appState.startRecording()
                            } else {
                                await appState.stopRecording()
                            }
                        }
                    }
                ))
                .toggleStyle(BlackToggleStyle())
                .labelsHidden()
                // 处理中时禁用开关，防止重复触发
                .disabled({
                    if case .processing = appState.recordingStatus { return true }
                    return false
                }())
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // ----------------------------------------
            // MARK: - 处理进度条（processing 状态显示）
            // ----------------------------------------

            if case .processing = appState.recordingStatus {
                ProgressView(value: nil as Double?)
                    .tint(.black)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            // ----------------------------------------
            // MARK: - 分割线
            // ----------------------------------------

            Rectangle()
                .fill(Color(hex: "#f1f1f1"))
                .frame(height: 1)
                .padding(.horizontal, 20)

            // ----------------------------------------
            // MARK: - 语音偏好设置入口
            // ----------------------------------------

            Button {
                // 导航到设置 Tab
                appState.selectedTab = .account
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundStyle(.black)

                    Text("语音偏好设置")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.black)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "#71717a"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color(hex: "#f1f1f1"), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 2)
                .shadow(color: .black.opacity(0.01), radius: 5, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        // 同步 isVoiceFlowEnabled 与 isRecording 状态
        .onChange(of: appState.isRecording) { _, isRecording in
            if !isRecording && appState.isVoiceFlowEnabled {
                // 录音已停止（可能因错误），同步关闭开关
                if case .error(_) = appState.recordingStatus {
                    appState.isVoiceFlowEnabled = false
                }
            }
        }
    }

    private var statusDescription: String {
        switch appState.recordingStatus {
        case .idle:
            return appState.isVoiceFlowEnabled
                ? "正在实时优化您的语音输入。"
                : "点击开启 VoiceFlow 语音输入功能。"
        case .recording:
            return "正在录音并实时识别语音..."
        case .processing:
            return "AI 正在润色识别结果..."
        case .done:
            return "已完成，文本已复制到剪贴板。"
        case .error(let msg):
            return "错误：\(msg)"
        }
    }
}

// ========================================
// MARK: - Black Toggle Style
// ========================================

struct BlackToggleStyle: ToggleStyle {

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        Button { configuration.isOn.toggle() } label: {
            ZStack {
                Capsule()
                    .fill(isOn ? Color.black : Color(hex: "#e4e4e7"))
                    .frame(width: 51, height: 31)
                Circle()
                    .fill(.white)
                    .frame(width: 27, height: 27)
                    .offset(x: isOn ? 10 : -10)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

// ========================================
// MARK: - Preview
// ========================================

#Preview {
    MainToggleCard()
        .environment(AppState.shared)
        .padding()
        .background(Color(hex: "#fcfcfc"))
}
