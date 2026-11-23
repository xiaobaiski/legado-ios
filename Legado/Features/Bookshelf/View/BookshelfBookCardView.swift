import SwiftUI

/// 书架宫格封面卡片视图 (iOS 原生液态玻璃质感)
public struct BookshelfBookCardView: View {
    public let book: Book
    public let isBatchMode: Bool
    public let isSelected: Bool
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
        allGroups: [String],
        onTap: @escaping () -> Void,
        onShowDetail: @escaping () -> Void,
        onEditMetadata: @escaping () -> Void = {},
        onRemove: @escaping () -> Void,
        onMoveGroup: @escaping (String?) -> Void) {
        self.book = book
        self.isBatchMode = isBatchMode
        self.isSelected = isSelected
        self.allGroups = allGroups
        self.onTap = onTap
        self.onShowDetail = onShowDetail
        self.onEditMetadata = onEditMetadata
        self.onRemove = onRemove
        self.onMoveGroup = onMoveGroup
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                coverSection
                infoSection
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.white.opacity(0.18),
                        lineWidth: isSelected ? 2 : 0.5))
            .shadow(color: AppTheme.Shadow.glass, radius: 8, x: 0, y: 4)
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

    private var coverSection: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(0.72, contentMode: .fit)
                .overlay {
                    bookCoverImage
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // 批量选择勾选框
            if isBatchMode {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.black.opacity(0.35))
                        .frame(width: 26, height: 26)
                    Image(systemName: isSelected ? "checkmark" : "circle")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .padding(6)
            }

            // 底部进度药丸
            VStack {
                Spacer()
                HStack {
                    Text(formatProgress(book: book))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                    Spacer()
                }
                .padding(6)
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(book.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 38, alignment: .topLeading)

            Text(book.author)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bookCoverImage: some View {
        BookCoverImage(coverUrl: book.coverUrl) {
            placeholderCover
        }
    }

    private var formatBadge: String? {
        if book.originName.localizedCaseInsensitiveContains("EPUB") {
            return "EPUB"
        }
        if book.isLocalFile {
            return "TXT"
        }
        return nil
    }

    private var placeholderCover: some View {
        BookDefaultCoverView(
            title: book.name,
            author: book.author,
            formatBadge: formatBadge,
            compact: false)
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
