/**
 * [INPUT]: 依赖 AppState 统计数据
 * [OUTPUT]: 对外提供 StatsGridView 统计网格，2x2 布局
 * [POS]: HomeView 的统计数据展示层，4个指标卡片
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ========================================
// MARK: - Stats Grid View
// ========================================

struct StatsGridView: View {

    @Environment(AppState.self) private var appState

    // 2x2 网格布局
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            StatCard(
                icon: "clock",
                label: "总听写时间",
                value: String(format: "%.1f", appState.totalDictationHours),
                unit: "小时"
            )
            StatCard(
                icon: "text.alignleft",
                label: "听写的单词",
                value: formatNumber(appState.totalWords),
                unit: nil
            )
            StatCard(
                icon: "bolt",
                label: "节省的时间",
                value: String(format: "%.1f", appState.savedHours),
                unit: "小时"
            )
            StatCard(
                icon: "speedometer",
                label: "平均速度",
                value: "\(appState.averageSpeed)",
                unit: "wpm"
            )
        }
        .padding(.horizontal, 16)
    }

    // 静态常量，避免每次渲染重复分配重量级 ObjC 对象
    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private func formatNumber(_ n: Int) -> String {
        Self.decimalFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// ========================================
// MARK: - Stat Card
// ========================================

private struct StatCard: View {

    let icon: String
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // ----------------------------------------
            // MARK: - 标签行
            // ----------------------------------------

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#71717a"))

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "#71717a"))
                    .tracking(0.6)
            }

            // ----------------------------------------
            // MARK: - 数值行
            // ----------------------------------------

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(.black)

                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.black)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(21)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(hex: "#f1f1f1"), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 2)
                .shadow(color: .black.opacity(0.01), radius: 5, x: 0, y: 4)
        )
    }
}

// ========================================
// MARK: - Preview
// ========================================

#Preview {
    StatsGridView()
        .environment(AppState.shared)
        .padding()
        .background(Color(hex: "#fcfcfc"))
}
