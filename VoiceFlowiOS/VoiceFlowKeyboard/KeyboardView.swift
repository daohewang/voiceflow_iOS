/**
 * [INPUT]: 依赖 KeyboardViewModel，复用主 App 设计系统（颜色、间距、排版）
 * [OUTPUT]: 对外提供 KeyboardView，VoiceFlow 自定义键盘完整 SwiftUI 界面
 * [POS]: VoiceFlowKeyboard Extension 的核心 UI，被 KeyboardViewController 宿主
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ========================================
// MARK: - Keyboard View
// ========================================

struct KeyboardView: View {

    @State var viewModel: KeyboardViewModel

    var body: some View {
        VStack(spacing: 0) {

            // ----------------------------------------
            // MARK: - Header（Logo + 功能按钮）
            // ----------------------------------------

            KeyboardHeader(
                onSwitch:  viewModel.switchKeyboard,
                onDelete:  viewModel.deleteBackward,
                onReturn:  viewModel.insertNewline
            )

            // 分割线
            Rectangle()
                .fill(Color(hex: "#f1f1f1"))
                .frame(height: 1)

            // ----------------------------------------
            // MARK: - 主内容区
            // ----------------------------------------

            VStack(spacing: 10) {

                // 实时文字预览
                LiveTextCard(text: viewModel.displayText, state: viewModel.recordState)

                // 录音中显示波形
                if viewModel.recordState == .recording {
                    WaveformBars(level: viewModel.audioLevel)
                        .frame(height: 28)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                // 录音按钮
                RecordButton(state: viewModel.recordState, audioLevel: viewModel.audioLevel, onTap: viewModel.toggleRecording)

                // 状态提示
                Text(statusLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxHeight: .infinity)
        }
        .background(Color(hex: "#fcfcfc"))
        .frame(height: 260)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.recordState)
    }

    private var statusLabel: String {
        switch viewModel.recordState {
        case .idle:            return viewModel.errorMsg ?? "轻触麦克风开始录音"
        case .recording:       return "正在识别 · 再次轻触停止"
        case .processing:      return "AI 润色中..."
        case .waitingMainApp:  return "已打开主应用，录音完成后返回此处"
        }
    }
    
    private var statusColor: Color {
        if viewModel.errorMsg != nil && viewModel.recordState == .idle {
            return Color(hex: "#ef4444") // 红色表示错误
        }
        if viewModel.recordState == .waitingMainApp {
            return Color(hex: "#3b82f6") // 蓝色提示等待主应用
        }
        return Color(hex: "#94a3b8") // 默认灰色
    }
}

// ========================================
// MARK: - Keyboard Header
// ========================================

private struct KeyboardHeader: View {
    let onSwitch: () -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void

    var body: some View {
        HStack(spacing: 0) {

            // 切换键盘（Globe）
            KeyboardHeaderBtn(icon: "globe", action: onSwitch)

            Spacer()

            // Logo
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.black)
                        .frame(width: 20, height: 20)
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("VoiceFlow")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "#0f172a"))
            }

            Spacer()

            // 删除 + 换行
            HStack(spacing: 0) {
                KeyboardHeaderBtn(icon: "delete.left", action: onDelete)
                KeyboardHeaderBtn(icon: "return",      action: onReturn)
            }
        }
        .frame(height: 44)
        .background(.white.opacity(0.96))
    }
}

private struct KeyboardHeaderBtn: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "#64748b"))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

// ========================================
// MARK: - Live Text Card
// ========================================

private struct LiveTextCard: View {
    let text: String
    let state: KeyboardViewModel.RecordState

    var body: some View {
        Group {
            if text.isEmpty {
                Text("识别结果将在这里显示…")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#94a3b8"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#0f172a"))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(
                        state == .recording ? Color.red.opacity(0.35) : Color(hex: "#f1f5f9"),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }
}

// ========================================
// MARK: - Waveform Bars
// ========================================

private struct WaveformBars: View {
    let level: Float

    private let barCount = 7

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let wave = abs(sin(t * 5.0 + Double(i) * 1.1))
                    let h = max(4, CGFloat(wave) * CGFloat(level + 0.2) * 60 + 4)
                    Capsule()
                        .fill(Color.black)
                        .frame(width: 3, height: h)
                }
            }
        }
        .frame(height: 28)
    }
}

// ========================================
// MARK: - Record Button
// ========================================

private struct RecordButton: View {
    let state: KeyboardViewModel.RecordState
    let audioLevel: Float
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // 录音中：音量驱动的波纹环
                if state == .recording {
                    Circle()
                        .fill(Color.red.opacity(0.06))
                        .frame(width: 100, height: 100)
                        .scaleEffect(1.0 + CGFloat(audioLevel) * 0.4)
                        .animation(.easeOut(duration: 0.15), value: audioLevel)

                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 80, height: 80)
                        .scaleEffect(1.0 + CGFloat(audioLevel) * 0.6)
                        .animation(.easeOut(duration: 0.12), value: audioLevel)
                }

                Circle()
                    .fill(bgColor)
                    .frame(width: 60, height: 60)
                    .shadow(color: bgColor.opacity(0.35), radius: 12, x: 0, y: 6)

                switch state {
                case .idle:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                case .recording:
                    // 麦克风 → 波纹图标，随音量跳动
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(1.0 + CGFloat(audioLevel) * 0.3)
                        .animation(.easeOut(duration: 0.1), value: audioLevel)
                case .processing:
                    ProgressView().tint(.white)
                case .waitingMainApp:
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(state == .processing)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state)
    }

    private var bgColor: Color {
        switch state {
        case .idle:            return .black
        case .recording:       return Color(hex: "#ef4444")
        case .processing:      return Color(hex: "#94a3b8")
        case .waitingMainApp:  return Color(hex: "#3b82f6")
        }
    }
}

// ========================================
// MARK: - Color+Hex（Extension 内独立定义）
// ========================================

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var val: UInt64 = 0
        Scanner(string: h).scanHexInt64(&val)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:  (a,r,g,b) = (255, (val>>8)*17, (val>>4 & 0xF)*17, (val & 0xF)*17)
        case 6:  (a,r,g,b) = (255, val>>16, val>>8 & 0xFF, val & 0xFF)
        case 8:  (a,r,g,b) = (val>>24, val>>16 & 0xFF, val>>8 & 0xFF, val & 0xFF)
        default: (a,r,g,b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:   Double(r)/255,
                  green: Double(g)/255,
                  blue:  Double(b)/255,
                  opacity: Double(a)/255)
    }
}

// ========================================
// MARK: - Preview
// ========================================

#if DEBUG
#Preview {
    KeyboardView(viewModel: KeyboardViewModel(inputVC: UIInputViewController()))
}
#endif
