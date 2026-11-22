import SwiftUI

/// 书架列表行项视图 (iOS 原生液态玻璃质感)
public struct BookshelfBookRowView: View {
    public let book: Book
    public let isBatchMode: Bool
    public let isSelected: Bool
    public let isUpdated: Bool
    public let allGroups: [String]
    public let onTap: () -> Void
    public let onShowDetail: () -> Void
    public let onEditMetadata: () -> Void
    public let onRemove: () -> Void
    public let onMoveGroup: (String?) -> Void

    public init(
        book: Book,
        isBatchMode: Bool,
        isSelected: Bool,
        isUpdated: Bool,
        allGroups: [String],
        onTap: @escaping () -> Void,
        onShowDetail: @escaping () -> Void,
        onEditMetadata: @escaping () -> Void = {},
        onRemove: @escaping () -> Void,
        onMoveGroup: @escaping (String?) -> Void) {
        self.book = book
        self.isBatchMode = isBatchMode
        self.isSelected = isSelected
        self.isUpdated = isUpdated
        self.allGroups = allGroups
        self.onTap = onTap
        self.onShowDetail = onShowDetail
        self.onEditMetadata = onEditMetadata
        self.onRemove = onRemove
        self.onMoveGroup = onMoveGroup
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                if isBatchMode {
                    selectionCheckbox
                }

                coverImage
                    .frame(width: 54, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                bookDetails

                Spacer()
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.white.opacity(0.18),
                        lineWidth: isSelected ? 1.5 : 0.5))
            .shadow(color: AppTheme.Shadow.glass, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isBatchMode {
                Button(action: onShowDetail) {
                    Label("查看详情与目录", systemImage: "info.circle")
                }

                Button(action: onEditMetadata) {
                    Label("编辑书名与作者", systemImage: "pencil")
                }

                Menu("移动至分组") {
                    Button("移出分组") {
                        onMoveGroup(nil)
                    }
                    ForEach(allGroups.filter { !["全部", "在读", "未读", "完结"].contains($0) }, id: \.self) { grp in
                        Button(grp) {
                            onMoveGroup(grp)
                        }
                    }
                }

                Button(role: .destructive, action: onRemove) {
                    Label("移出书架", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Subviews

    private var selectionCheckbox: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .transition(.scale.combined(with: .opacity))
    }

    private var coverImage: some View {
        BookCoverImage(coverUrl: book.coverUrl) {
            placeholderCover
        }
    }

    private var placeholderCover: some View {
        BookDefaultCoverView(title: book.name, author: book.author, compact: true)
    }

    private var progressFraction: Double? {
        guard book.totalChapterNum > 0, book.durChapterIndex > 0 || book.durChapterPos > 0 else {
            return nil
        }
        return min(max(Double(book.durChapterIndex + 1) / Double(book.totalChapterNum), 0.03), 1.0)
    }

    private var bookDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(book.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if isUpdated {
                    Text("更新")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.red.gradient)
                        }
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                }

                Spacer()

                Text(formatProgress(book: book))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(book.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            let hasProgress = book.durChapterIndex > 0 || book.durChapterPos > 0
            if let durTitle = book.durChapterTitle, !durTitle.isEmpty, hasProgress {
                Text("读至: \(durTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if book.totalChapterNum > 0 {
                Text("共 \(book.totalChapterNum) 章")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let ratio = progressFraction {
                ProgressView(value: ratio)
                    .tint(.accentColor)
                    .scaleEffect(x: 1, y: 0.65, anchor: .center)
            }
        }
    }

    private func formatProgress(book: Book) -> String {
        if book.durChapterIndex == 0 {
            return book.durChapterPos > 0 ? "在读" : "未读"
        }
        if book.totalChapterNum > 0 {
            let percent = Int((Double(book.durChapterIndex + 1) / Double(book.totalChapterNum)) * 100)
            return "\(max(percent, 1))%"
        }
        return "第\(book.durChapterIndex + 1)章"
    }
}
