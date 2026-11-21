import SwiftUI
import UIKit

/// 阅读器当前页摘录、复制、批注书签与一键创建净化规则弹窗（对标 Legado 正文长按操作菜单）
public struct PageTextActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedExcerpt: String
    @State private var bookmarkNote = ""
    @State private var replaceTarget = ""
    @State private var replaceWith = ""
    @State private var feedbackText: String?

    let pageText: String
    let chapterTitle: String
    let bookName: String
    let onAddBookmarkWithNote: (_ excerpt: String, _ note: String) -> Void
    let onQuickPurifyRuleSaved: () -> Void

    public init(
        pageText: String,
        chapterTitle: String,
        bookName: String,
        onAddBookmarkWithNote: @escaping (_ excerpt: String, _ note: String) -> Void,
        onQuickPurifyRuleSaved: @escaping () -> Void) {
        self.pageText = pageText
        self.chapterTitle = chapterTitle
        self.bookName = bookName
        self.onAddBookmarkWithNote = onAddBookmarkWithNote
        self.onQuickPurifyRuleSaved = onQuickPurifyRuleSaved
        let firstPara = pageText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\u{3000}")) }
            .first(where: { !$0.isEmpty }) ?? pageText
        _selectedExcerpt = State(initialValue: String(firstPara.prefix(120)))
    }

    private var paragraphs: [String] {
        pageText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\u{3000}")) }
            .filter { !$0.isEmpty }
    }

    public var body: some View {
        NavigationStack {
            Form {
                paragraphPickerSection
                copyAndBookmarkSection
                quickPurifySection
            }
            .navigationTitle("正文摘录与净化")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .overlay(alignment: .bottom) {
                if let feedbackText {
                    Text(feedbackText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule(style: .continuous))
                        .padding(.bottom, 16)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var paragraphPickerSection: some View {
        Section {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                Button {
                    selectedExcerpt = para
                    replaceTarget = para
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(
                            systemName: selectedExcerpt == para
                                ? "checkmark.circle.fill"
                                : "circle")
                            .foregroundStyle(selectedExcerpt == para ? Color.accentColor : Color.secondary)
                            .padding(.top, 2)
                        Text(para)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("点选本页段落（\(chapterTitle)）")
        }
    }

    private var copyAndBookmarkSection: some View {
        Section("复制与批注书签") {
            TextField("摘录内容（可自由裁剪）", text: $selectedExcerpt, axis: .vertical)
                .font(.footnote)
                .lineLimit(2 ... 5)

            TextField("添加阅读想法 / 笔记（可选）", text: $bookmarkNote, axis: .vertical)
                .font(.footnote)
                .lineLimit(1 ... 3)

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = selectedExcerpt.isEmpty ? pageText : selectedExcerpt
                    showFeedback("已复制到剪贴板")
                } label: {
                    Label("复制选中", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    let excerpt = selectedExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
                    onAddBookmarkWithNote(excerpt.isEmpty ? String(pageText.prefix(80)) : excerpt, bookmarkNote)
                    showFeedback("已保存批注书签")
                } label: {
                    Label("存为书签", systemImage: "bookmark.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var quickPurifySection: some View {
        Section {
            TextField("要替换或删除的错词 / 广告文本", text: $replaceTarget)
                .font(.footnote)
            TextField("替换为（留空表示直接删除）", text: $replaceWith)
                .font(.footnote)

            Button {
                let target = replaceTarget.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !target.isEmpty else { return }
                let rule = ReplaceRule(
                    name: "快捷净化：\(String(target.prefix(12)))",
                    group: "快捷净化",
                    pattern: target,
                    replacement: replaceWith,
                    scope: bookName,
                    scopeTitle: false,
                    scopeContent: true,
                    isEnabled: true,
                    isRegex: false)
                _ = ReplaceRuleStore.shared.upsert(rule)
                onQuickPurifyRuleSaved()
                showFeedback("已添加净化规则并立即重排")
            } label: {
                Label("一键净化此词（仅对本书生效）", systemImage: "wand.and.stars")
            }
            .disabled(replaceTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("一键净化排版")
        } footer: {
            Text("发现广告水印、错别字或乱码行时，可一键加入替换净化规则并即时生效。")
        }
    }

    private func showFeedback(_ message: String) {
        feedbackText = message
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if feedbackText == message {
                feedbackText = nil
            }
        }
    }
}
