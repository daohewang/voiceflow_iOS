/**
 * [INPUT]: 依赖 AppState、StatsGridView、MainToggleCard、QuickActionsView
 * [OUTPUT]: 对外提供 HomeView，VoiceFlowiOS 首页，含录音控制 + 实时文字展示
 * [POS]: 首页主视图，1:1 还原 Figma "VoiceFlow 首页 (优化阴影)" node 1:2
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ========================================
// MARK: - Home View
// ========================================

struct HomeView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ----------------------------------------
                    // MARK: - Header
                    // ----------------------------------------

                    HomeHeader()
                        .padding(.bottom, 20)

                    // ----------------------------------------
                    // MARK: - Stats Grid (2x2)
                    // ----------------------------------------

                    StatsGridView()
                        .padding(.bottom, 20)

                    // ----------------------------------------
                    // MARK: - Main Toggle Card（绑定录音）
                    // ----------------------------------------

                    MainToggleCard()
                        .padding(.bottom, 24)

                    // ----------------------------------------
                    // MARK: - 实时识别结果卡片
                    // ----------------------------------------

                    if !appState.asrText.isEmpty || !appState.llmText.isEmpty {
                        ResultCard()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // ----------------------------------------
                    // MARK: - 快速操作
                    // ----------------------------------------

                    VStack(alignment: .leading, spacing: 12) {
                        Text("快速操作")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)

                        QuickActionsView()
                    }

                }
                .padding(.top, 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.asrText.isEmpty && appState.llmText.isEmpty)
            }
            .contentMargins(.bottom, 16, for: .scrollContent)
            .background(Color(hex: "#fcfcfc").ignoresSafeArea(edges: .top))

            // ----------------------------------------
            // MARK: - 剪贴板复制 Toast
            // ----------------------------------------

            if appState.clipboardCopied {
                ClipboardToast()
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.clipboardCopied)
    }
}

// ========================================
// MARK: - Home Header
// ========================================

private struct HomeHeader: View {

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.black)
                        .frame(width: 24, height: 24)
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("VoiceFlow")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
            }

            Spacer()

            HStack(spacing: 8) {
                HeaderButton(icon: "magnifyingglass", action: {})
                HeaderButton(icon: "bell", action: {})
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

private struct HeaderButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color(hex: "#f1f1f1"), lineWidth: 1))
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black)
            }
        }
        .buttonStyle(.plain)
    }
}

// ========================================
// MARK: - Result Card（实时识别结果展示）
// ========================================

private struct ResultCard: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // 状态标签
            HStack(spacing: 6) {
                statusIndicator
                Text(statusLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "#64748b"))
                // 强制重置按钮（仅在非空闲时显示，用于故障恢复）
                if appState.recordingStatus != .idle {
                    Button {
                        appState.forceReset()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("重置")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }

                // 复制按钮（有最终结果时显示）
                if !appState.llmText.isEmpty || (!appState.asrText.isEmpty && appState.llmText.isEmpty) {
                    Button {
                        let text = appState.llmText.isEmpty ? appState.asrText : appState.llmText
                        UIPasteboard.general.string = text
                        appState.clipboardCopied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            appState.clipboardCopied = false
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#64748b"))
                    }
                    .buttonStyle(.plain)
                }
            }

            // ASR 原文
            if !appState.asrText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("识别原文")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(hex: "#94a3b8"))
                        .tracking(0.8)
                        .textCase(.uppercase)
                    Text(appState.asrText)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#475569"))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // LLM 润色结果
            if !appState.llmText.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 润色")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(hex: "#94a3b8"))
                        .tracking(0.8)
                        .textCase(.uppercase)
                    Text(appState.llmText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "#0f172a"))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#f1f5f9"), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 4)
        )
    }

    // 状态指示点
    @ViewBuilder
    private var statusIndicator: some View {
        switch appState.recordingStatus {
        case .recording:
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .scaleEffect(1.5)
                )
        case .processing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 8, height: 8)
        default:
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        }
    }

    private var statusLabel: String {
        switch appState.recordingStatus {
        case .recording:   return "正在识别..."
        case .processing:  return "AI 润色中..."
        case .done:        return "已完成 · 复制到剪贴板"
        default:           return "识别结果"
        }
    }
}

// ========================================
// MARK: - Clipboard Toast
// ========================================

private struct ClipboardToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("已复制到剪贴板")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(hex: "#0f172a"))
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        )
    }
}

// ========================================
// MARK: - Preview
// ========================================

#Preview {
    HomeView()
        .environment(AppState.shared)
}
