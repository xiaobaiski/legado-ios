import Foundation

/// 从书架移除书籍用例（同步清理章节文件、本地封面与关联书签）
public final class RemoveBookFromShelfUseCase: Sendable {
    private let bookRepository: BookRepository
    private let bookCacheRepository: BookCacheRepository?
    private let bookmarkRepository: BookmarkRepository?

    public init(
        bookRepository: BookRepository,
        bookCacheRepository: BookCacheRepository? = nil,
        bookmarkRepository: BookmarkRepository? = nil) {
        self.bookRepository = bookRepository
        self.bookCacheRepository = bookCacheRepository
        self.bookmarkRepository = bookmarkRepository
    }

    public func execute(bookUrl: String) async throws {
        try await bookRepository.removeBook(by: bookUrl)
        try? bookCacheRepository?.clearBookCache(bookUrl: bookUrl)
        try? await bookmarkRepository?.deleteBookmarks(forBookUrl: bookUrl)
        removeLocalCoverIfExists(for: bookUrl)
    }

    private func removeLocalCoverIfExists(for bookUrl: String) {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let coversDir = docs.appendingPathComponent("BookCovers", isDirectory: true)
        guard let items = try? fileManager.contentsOfDirectory(at: coversDir, includingPropertiesForKeys: nil) else {
            return
        }
        let prefix = BookCacheRepositoryImpl.deterministicKey(for: bookUrl) + "."
        for item in items where item.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: item)
        }
    }
}
