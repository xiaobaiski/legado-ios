import SwiftUI
import UniformTypeIdentifiers

/// Legado 兼容 TXT 目录分章规则管理视图（同步支持 `txtTocRule.json` 导入导出）
public struct TxtTocRuleManageView: View {
    @StateObject private var viewModel = TxtTocRuleManageViewModel()
    @State private var editingRule: TxtTocRule?
    @State private var isShowingJsonPicker = false
    @State private var isShowingResetAlert = false

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach(viewModel.rules) { rule in
                    tocRuleRow(rule)
                }
            } footer: {
                Text("导入本地 TXT 书籍时，引擎会自动从已启用的规则中评分选出匹配率最高的目录规则，完全兼容 Legado Android `txtTocRule.json`。")
            }
        }
        .navigationTitle("TXT 目录分章规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editingRule = TxtTocRule(name: "", rule: "", example: "")
                    } label: {
                        Label("新建目录规则", systemImage: "plus")
                    }

                    Button {
                        isShowingJsonPicker = true
                    } label: {
                        Label("从文件导入 txtTocRule.json", systemImage: "doc.badge.plus")
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
                        Label("恢复 Legado 默认目录规则", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            TxtTocRuleEditorSheet(rule: rule, viewModel: viewModel) { saved in
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
        .alert("恢复默认目录规则", isPresented: $isShowingResetAlert) {
            Button("取消", role: .cancel) {}
            Button("恢复默认", role: .destructive) {
                viewModel.resetDefaults()
            }
        } message: {
            Text("将重置为内置的 Legado 官方 TXT 目录正则规则集合。")
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

    private func tocRuleRow(_ rule: TxtTocRule) -> some View {
        HStack(spacing: 12) {
            Button {
                editingRule = rule
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name.isEmpty ? "自定义规则" : rule.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let example = rule.example, !example.isEmpty {
                        Text("示例：\(example)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(rule.rule)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.enable },
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
}

private struct TxtTocRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TxtTocRule
    @State private var sampleText: String
    let viewModel: TxtTocRuleManageViewModel
    let onSave: (TxtTocRule) -> Void

    init(rule: TxtTocRule, viewModel: TxtTocRuleManageViewModel, onSave: @escaping (TxtTocRule) -> Void) {
        _draft = State(initialValue: rule)
        _sampleText = State(initialValue: rule.example ?? "第一章 宿命之始\n正文内容...\n第二章 风起云涌")
        self.viewModel = viewModel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则信息") {
                    TextField("规则名称", text: $draft.name)
                    TextField("匹配示例（可选）", text: Binding(
                        get: { draft.example ?? "" },
                        set: { draft.example = $0.isEmpty ? nil : $0 }))
                }

                Section("目录正则表达式") {
                    TextField("输入章节标题正则表达式", text: $draft.rule, axis: .vertical)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("启用该规则", isOn: $draft.enable)
                }

                Section("实时匹配预览") {
                    TextField("输入测试文本（支持多行）", text: $sampleText, axis: .vertical)
                    let matches = viewModel.testRuleMatches(pattern: draft.rule, sample: sampleText)
                    if matches.isEmpty {
                        Text("未匹配到章节标题")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(matches.prefix(5).enumerated()), id: \.offset) { _, hit in
                            Label(hit, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(draft.name.isEmpty ? "编辑目录规则" : draft.name)
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
