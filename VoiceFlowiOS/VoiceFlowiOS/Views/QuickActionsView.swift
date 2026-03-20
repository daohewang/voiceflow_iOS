/**
 * [INPUT]: 无外部依赖，纯 UI 组件
 * [OUTPUT]: 对外提供 QuickActionsView，快速操作列表
 * [POS]: HomeView 的快速入口区，两个功能行
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ========================================
// MARK: - Quick Actions View
// ========================================

struct QuickActionsView: View {

    var body: some View {
        VStack(spacing: 0) {
            ActionRow(
                icon: "plus.circle",
                title: "开始新听写",
                subtitle: "立即捕捉您的灵感",
                action: {}
            )

            Divider()
                .padding(.horizontal, 16)

            ActionRow(
                icon: "character.bubble",
                title: "翻译设置",
                subtitle: "管理多语言翻译模型",
                action: {}
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#f8fafc"))
        )
        .padding(.horizontal, 16)
    }
}

// ========================================
// MARK: - Action Row
// ========================================

private struct ActionRow: View {

    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {

                // ----------------------------------------
                // MARK: - 圆形图标
                // ----------------------------------------

                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black)
                }

                // ----------------------------------------
                // MARK: - 文字
                // ----------------------------------------

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.black)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: "#71717a"))
                }

                Spacer()

                // ----------------------------------------
                // MARK: - 右箭头
                // ----------------------------------------

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#94a3b8"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// ========================================
// MARK: - Preview
// ========================================

#Preview {
    QuickActionsView()
        .padding()
        .background(Color(hex: "#fcfcfc"))
}
