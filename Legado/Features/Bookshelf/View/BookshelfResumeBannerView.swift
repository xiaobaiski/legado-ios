import SwiftUI

/// 书架顶部「继续阅读」液态玻璃快捷卡片
struct BookshelfResumeBannerView: View {
    let book: Book
    let onTap: () -> Void

    private var subtitle: String {
        book.durChapterTitle ?? "第\(book.durChapterIndex + 1)章"
    }

    private var progressRatio: Double {
        guard book.totalChapterNum > 0 else { return 0.05 }
        return min(max(Double(book.durChapterIndex + 1) / Double(book.totalChapterNum), 0.03), 1.0)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                BookCoverImage(coverUrl: book.coverUrl) {
                    BookDefaultCoverView(title: book.name, author: book.author, compact: true)
                }
                .frame(width: 40, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("继续阅读")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Text(book.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    ProgressView(value: progressRatio)
                        .tint(.accentColor)
                        .scaleEffect(x: 1, y: 0.65, anchor: .center)
                }

                Text("继续")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.14)))
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
