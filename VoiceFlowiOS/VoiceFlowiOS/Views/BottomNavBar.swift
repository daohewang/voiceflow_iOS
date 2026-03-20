/**
 * [INPUT]: 依赖 AppState.selectedTab 状态，依赖 TabItem 枚举
 * [OUTPUT]: 对外提供 BottomNavBar 底部导航栏，全宽固定布局
 * [POS]: ContentView 的 safeAreaInset(bottom)，随系统 home indicator 自动适配
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ========================================
// MARK: - Bottom Nav Bar
// ========================================

struct BottomNavBar: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {

            // 0.5pt 细线分隔，随主题自动适配
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                ForEach(TabItem.allCases, id: \.self) { tab in
                    TabBarItem(
                        tab: tab,
                        isSelected: appState.selectedTab == tab
                    ) {
                        appState.selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}

// ========================================
// MARK: - Tab Bar Item
// ========================================

private struct TabBarItem: View {

    let tab: TabItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .black : Color(hex: "#94a3b8"))

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .black : Color(hex: "#94a3b8"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// ========================================
// MARK: - Preview
// ========================================

#Preview {
    VStack {
        Spacer()
        BottomNavBar()
    }
    .background(Color(hex: "#fcfcfc"))
    .environment(AppState.shared)
}
