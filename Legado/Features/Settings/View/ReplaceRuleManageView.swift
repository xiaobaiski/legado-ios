import SwiftUI
import UniformTypeIdentifiers

/// Legado 兼容替换净化规则管理视图
public struct ReplaceRuleManageView: View {
    @StateObject private var viewModel = ReplaceRuleManageViewModel()
    @State private var editingRule: ReplaceRule?
    @State private var isShowingJsonPicker = false
    @State private var isShowingResetAlert = false

    private let onRulesChanged: () -> Void

    public init(onRulesChanged: @escaping () -> Void = {}) {
        self.onRulesChanged = onRulesChanged
    }

    public var body: some View {
        List {
            if viewModel.rules.isEmpty {
                ContentUnavailableView(
                    "暂无替换净化规则",
                    systemImage: "wand.and.stars",
                    description: Text("点击右上角新增规则或导入 Legado 替换净化 JSON"))
            } else {
                ForEach(viewModel.rules) { rule in
                    ruleRow(rule)
                }
            }
        }
        .navigationTitle("替换净化规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editingRule = ReplaceRule(name: "", pattern: "", replacement: "")
                    } label: {
                        Label("新建替换规则", systemImage: "plus")
                    }

                    Button {
                        isShowingJsonPicker = true
                    } label: {
                        Label("从文件导入 Legado JSON", systemImage: "doc.badge.plus")
                    }

                    Button {
                        viewModel.importFromClipboard()
                    } label: {
                        Label("从剪贴板导入 JSON", systemImage: "doc.on.clipboard")
                    }

                    Divider()

                    Button {
                        viewModel.copyExportJSON()
                    } label: {
                        Label("导出并复制 Legado JSON", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        isShowingResetAlert = true
                    } label: {
                        Label("恢复内置净化规则", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .onAppear {
            viewModel.onRulesMutated = onRulesChanged
        }
        .sheet(item: $editingRule) { rule in
            ReplaceRuleEditorSheet(rule: rule, viewModel: viewModel) { saved in
                viewModel.save(saved)
            }
        }
        .sheet(isPresented: $isShowingJsonPicker) {
            DocumentPickerView(
                allowedContentTypes: [.json, .plainText, .data],
                allowsMultipleSelection: false,
                onPick: { urls in
                    isShowingJsonPicker = false
                    if let first = urls.first {
                        viewModel.importFromFile(first)
                    }
                },
                onCancel: {
                    isShowingJsonPicker = false
                })
                .ignoresSafeArea()
        }
        .alert("恢复内置净化规则", isPresented: $isShowingResetAlert) {
            Button("取消", role: .cancel) {}
            Button("恢复默认", role: .destructive) {
                viewModel.resetDefaults()
            }
        } message: {
            Text("将重置为默认内置去广告、防盗水印与零宽字符清理规则。")
        }
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule(style: .continuous))
                    .padding(.bottom, 20)
            }
        }
    }

    private func ruleRow(_ rule: ReplaceRule) -> some View {
        HStack(spacing: 12) {
            Button {
                editingRule = rule
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(rule.name.isEmpty ? "未命名规则" : rule.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let group = rule.group, !group.isEmpty {
                            Text(group)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule(style: .continuous))
                        }
                    }

                    Text(rule.pattern)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        badge(rule.isRegex ? "正则" : "文本")
                        if rule.scopeContent { badge("正文") }
                        if rule.scopeTitle { badge("标题") }
                        if let scope = rule.scope, !scope.isEmpty {
                            badge("限: \(scope)")
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in
                    viewModel.toggleEnabled(id: rule.id)
                }))
                .labelsHidden()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.delete(id: rule.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule(style: .continuous))
    }
}

private struct ReplaceRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReplaceRule
    @State private var sampleText = ""
    let viewModel: ReplaceRuleManageViewModel
    let onSave: (ReplaceRule) -> Void

    init(rule: ReplaceRule, viewModel: ReplaceRuleManageViewModel, onSave: @escaping (ReplaceRule) -> Void) {
        _draft = State(initialValue: rule)
        self.viewModel = viewModel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("规则名称", text: $draft.name)
                    TextField("分组（可选）", text: Binding(
                        get: { draft.group ?? "" },
                        set: { draft.group = $0.isEmpty ? nil : $0 }))
                }

                Section("匹配与替换") {
                    TextField("匹配内容 / 正则表达式", text: $draft.pattern, axis: .vertical)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("替换为（留空表示删除）", text: $draft.replacement, axis: .vertical)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("使用正则表达式", isOn: $draft.isRegex)
                    Toggle("区分大小写", isOn: $draft.isCaseSensitive)
                    Toggle("作用于正文", isOn: $draft.scopeContent)
                    Toggle("作用于章节标题", isOn: $draft.scopeTitle)
                }

                Section("作用范围（留空全局生效）") {
                    TextField("仅对指定书名生效（逗号分隔）", text: Binding(
                        get: { draft.scope ?? "" },
                        set: { draft.scope = $0.isEmpty ? nil : $0 }))
                    TextField("排除书名（逗号分隔）", text: Binding(
                        get: { draft.excludeScope ?? "" },
                        set: { draft.excludeScope = $0.isEmpty ? nil : $0 }))
                }

                Section("实时效果测试") {
                    TextField("输入示例正文测试替换效果...", text: $sampleText, axis: .vertical)
                    if !sampleText.isEmpty {
                        Text(viewModel.previewResult(sample: sampleText, rule: draft))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(draft.name.isEmpty ? "编辑替换规则" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }
}
