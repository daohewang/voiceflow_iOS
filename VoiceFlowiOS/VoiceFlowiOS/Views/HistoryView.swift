/**
 * [INPUT]: 依赖 AppState.historyEntries、AppState.isHistoryEnabled
 * [OUTPUT]: 对外提供 HistoryView，历史记录页 - 展示真实录音历史
 * [POS]: ContentView TabContentRouter 的 .history case 目标视图
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ========================================
// MARK: - History View
// ========================================

struct HistoryView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                // ----------------------------------------
                // MARK: - 大标题 Header
                // ----------------------------------------

                HistoryHeader()

                // ----------------------------------------
                // MARK: - 设置卡片区
                // ----------------------------------------

                HistorySettingsSection()
                    .padding(.bottom, 8)

                // ----------------------------------------
                // MARK: - 时间线列表
                // ----------------------------------------

                if appState.historyEntries.isEmpty {
                    HistoryEmptyState()
                        .padding(.top, 48)
                } else {
                    HistoryTimelineView(entries: appState.historyEntries)
                }
            }
        }
        .contentMargins(.bottom, 16, for: .scrollContent)
        .background(Color.white.ignoresSafeArea(edges: .top))
    }
}

// ========================================
// MARK: - History Header
// ========================================

private struct HistoryHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HeaderIconBtn(icon: "chevron.left")
                Spacer()
                HeaderIconBtn(icon: "magnifyingglass")
            }
            Text("历史记录")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color(hex: "#0f172a"))
                .tracking(-0.9)
        }
        .padding(.horizontal, 24)
        .padding(.top, 48)
        .padding(.bottom, 24)
    }
}

private struct HeaderIconBtn: View {
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
// MARK: - Settings Cards Section
// ========================================

private struct HistorySettingsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 12) {
            HistoryToggleCard()
            HistoryLinkCard(title: "数据隐私", subtitle: "您的数据经过端到端加密保护")
        }
        .padding(.horizontal, 24)
    }
}

private struct HistoryToggleCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("保留历史")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#0f172a"))
                Text("自动保存您的所有语音转录记录")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "#64748b"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $state.isHistoryEnabled)
                .toggleStyle(BlackToggleStyle())
                .labelsHidden()
        }
        .padding(17)
        .settingsCardStyle()
    }
}

private struct HistoryLinkCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "#0f172a"))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "#64748b"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "#94a3b8"))
            }
            .padding(17)
            .settingsCardStyle()
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func settingsCardStyle() -> some View {
        self.background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#f1f5f9").opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 30, x: 0, y: 10)
                .shadow(color: .black.opacity(0.03), radius: 12, x: 0, y: 4)
        )
    }
}

// ========================================
// MARK: - Empty State
// ========================================

private struct HistoryEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#94a3b8"))
            Text("暂无历史记录")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "#0f172a"))
            Text("开启 VoiceFlow 录音后，转录记录将显示在这里。")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#64748b"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
    }
}

// ========================================
// MARK: - Timeline View（真实数据）
// ========================================

private struct HistoryTimelineView: View {
    let entries: [HistoryEntry]

    // 按日期分组
    private var sections: [(title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        var todayEntries: [HistoryEntry] = []
        var yesterdayEntries: [HistoryEntry] = []
        var olderEntries: [HistoryEntry] = []

        for entry in entries {
            let entryDay = calendar.startOfDay(for: entry.date)
            if entryDay == today {
                todayEntries.append(entry)
            } else if entryDay == yesterday {
                yesterdayEntries.append(entry)
            } else {
                olderEntries.append(entry)
            }
        }

        var result: [(title: String, entries: [HistoryEntry])] = []
        if !todayEntries.isEmpty     { result.append(("今天",   todayEntries)) }
        if !yesterdayEntries.isEmpty { result.append(("昨天", yesterdayEntries)) }
        if !olderEntries.isEmpty     { result.append(("更早",   olderEntries)) }
        return result
    }

    var body: some View {
        ForEach(sections, id: \.title) { section in
            HistorySectionBlock(title: section.title, entries: section.entries)
        }
    }
}

// ========================================
// MARK: - History Section Block
// ========================================

private struct HistorySectionBlock: View {
    let title: String
    let entries: [HistoryEntry]

    var body: some View {
        VStack(spacing: 0) {
            SectionDividerHeader(title: title)
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HistoryEntryItem(entry: entry, isLast: index == entries.count - 1)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct SectionDividerHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "#94a3b8"))
                .tracking(1.2)
                .textCase(.uppercase)
            Rectangle()
                .fill(Color(hex: "#f1f5f9"))
                .frame(height: 1)
        }
    }
}

// ========================================
// MARK: - History Entry Item
// ========================================

private struct HistoryEntryItem: View {
    let entry: HistoryEntry
    let isLast: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {

            // 左侧：时间 + 竖线
            VStack(spacing: 4) {
                Text(Self.timeFormatter.string(from: entry.date))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color(hex: "#94a3b8"))
                    .padding(.top, 4)
                Rectangle()
                    .fill(isLast ? Color.clear : Color(hex: "#f1f5f9"))
                    .frame(width: 1)
            }
            .frame(width: 32)

            // 右侧：内容
            VStack(alignment: .leading, spacing: 6) {
                // 润色结果（优先显示）
                let displayText = entry.finalText.isEmpty ? entry.asrText : entry.finalText
                Text(displayText)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#334155"))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                // 录音时长
                HStack(spacing: 4) {
                    Image(systemName: "mic")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#94a3b8"))
                    Text(formatDuration(entry.durationSeconds))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#94a3b8"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) 秒" }
        return "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}

// ========================================
// MARK: - Preview
// ========================================

#Preview {
    HistoryView()
        .environment(AppState.shared)
}
