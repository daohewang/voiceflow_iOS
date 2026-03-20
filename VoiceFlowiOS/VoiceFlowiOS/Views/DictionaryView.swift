/**
 * [INPUT]: 依赖 AppState.selectedStyleId、StyleTemplateStore.shared
 * [OUTPUT]: 对外提供 DictionaryView（人设模板页），展示/选择/新建/删除模板
 * [POS]: ContentView TabContentRouter 的 .dictionary case 目标视图
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ========================================
// MARK: - Dictionary View（人设模板）
// ========================================

struct DictionaryView: View {

    @Environment(AppState.self) private var appState
    @State private var selectedTab: Int = 0
    @State private var showNewTemplateSheet = false
    @State private var templateToDelete: StyleTemplate? = nil
    @State private var showDeleteConfirm = false

    private let tabs = ["所有", "内置", "自定义"]

    private var store: StyleTemplateStore { StyleTemplateStore.shared }

    // 按 Tab 过滤
    private var filteredTemplates: [StyleTemplate] {
        switch selectedTab {
        case 1: return store.predefinedTemplateList
        case 2: return store.customTemplates
        default: return store.templates
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ----------------------------------------
                    // MARK: - 大标题 Header
                    // ----------------------------------------

                    DictHeader()

                    // ----------------------------------------
                    // MARK: - Tab 筛选栏
                    // ----------------------------------------

                    DictTabBar(tabs: tabs, selectedTab: $selectedTab)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)

                    // ----------------------------------------
                    // MARK: - 模板列表
                    // ----------------------------------------

                    VStack(spacing: 0) {
                        ForEach(filteredTemplates) { template in
                            TemplateEntryItem(
                                template: template,
                                isSelected: appState.selectedStyleId == template.id,
                                onSelect: { appState.selectedStyleId = template.id },
                                onDelete: {
                                    templateToDelete = template
                                    showDeleteConfirm = true
                                }
                            )
                        }

                        if filteredTemplates.isEmpty {
                            TemplateEmptyState(tabIndex: selectedTab)
                                .padding(.top, 48)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 80) // FAB 空间
                }
            }
            .contentMargins(.bottom, 16, for: .scrollContent)

            // ----------------------------------------
            // MARK: - 浮动操作按钮 (FAB)
            // ----------------------------------------

            Button { showNewTemplateSheet = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(.black)
                            .shadow(color: .black.opacity(0.08), radius: 32, x: 0, y: 12)
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
        .background(Color.white.ignoresSafeArea(edges: .top))
        .sheet(isPresented: $showNewTemplateSheet) {
            NewTemplateSheet()
        }
        .confirmationDialog(
            "删除此人设？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let t = templateToDelete {
                    store.deleteTemplate(t)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
    }
}

// ========================================
// MARK: - Dict Header
// ========================================

private struct DictHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                DictHeaderBtn(icon: "chevron.left")
                Spacer()
                DictHeaderBtn(icon: "magnifyingglass")
            }
            Text("人设模板")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color(hex: "#0f172a"))
                .tracking(-0.9)
        }
        .padding(.horizontal, 24)
        .padding(.top, 48)
        .padding(.bottom, 16)
    }
}

private struct DictHeaderBtn: View {
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
// MARK: - Tab Bar
// ========================================

private struct DictTabBar: View {
    let tabs: [String]
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index }
                } label: {
                    VStack(spacing: 0) {
                        Text(tab)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                selectedTab == index ? Color(hex: "#0f172a") : Color(hex: "#94a3b8")
                            )
                            .padding(.bottom, 14)
                        Rectangle()
                            .fill(selectedTab == index ? Color.black : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: "#f1f5f9")).frame(height: 1)
        }
    }
}

// ========================================
// MARK: - Template Entry Item
// ========================================

private struct TemplateEntryItem: View {
    let template: StyleTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    // 取 systemPrompt 前 50 字作描述
    private var description: String {
        let p = template.systemPrompt
        return p.count > 50 ? String(p.prefix(50)) + "…" : p
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {

                // 图标背景（选中高亮）
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? Color.black : Color(hex: "#f1f5f9"))
                        .frame(width: 48, height: 48)
                    Image(systemName: isSelected ? "checkmark" : "person.crop.rectangle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color.white : Color(hex: "#475569"))
                }

                // 名称 + 描述
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(template.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: "#0f172a"))
                        if isSelected {
                            Text("当前")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.black))
                        }
                        if !template.isPredefined {
                            Text("自定义")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color(hex: "#64748b"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(hex: "#f1f5f9")))
                        }
                    }
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#64748b"))
                        .lineLimit(2)
                }

                Spacer()

                // 删除按钮（仅自定义模板）
                if !template.isPredefined {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#ef4444"))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "#94a3b8"))
                }
            }
            .padding(17)
        }
        .buttonStyle(.plain)
    }
}

// ========================================
// MARK: - Empty State
// ========================================

private struct TemplateEmptyState: View {
    let tabIndex: Int
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(Color(hex: "#94a3b8"))
            Text(tabIndex == 2 ? "暂无自定义人设" : "暂无模板")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "#64748b"))
            if tabIndex == 2 {
                Text("点击右下角 + 按钮创建专属人设")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#94a3b8"))
            }
        }
    }
}

// ========================================
// MARK: - New Template Sheet
// ========================================

private struct NewTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var prompt: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section("人设名称") {
                    TextField("例如：技术文档助手", text: $name)
                }
                Section("系统提示词") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("新建人设")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        guard !name.isEmpty, !prompt.isEmpty else { return }
                        let template = StyleTemplate(name: name, systemPrompt: prompt)
                        StyleTemplateStore.shared.addTemplate(template)
                        dismiss()
                    }
                    .disabled(name.isEmpty || prompt.isEmpty)
                }
            }
        }
    }
}

// ========================================
// MARK: - Preview
// ========================================

#Preview {
    DictionaryView()
        .environment(AppState.shared)
}
