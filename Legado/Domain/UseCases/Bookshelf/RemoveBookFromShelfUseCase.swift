import Foundation

/// 从书架移除书籍用例
public final class RemoveBookFromShelfUseCase: Sendable {
    private let bookRepository: BookRepository
    private let bookCacheRepository: BookCacheRepository?

    public init(
        bookRepository: BookRepository,
        bookCacheRepository: BookCacheRepository? = nil) {
        self.bookRepository = bookRepository
        self.bookCacheRepository = bookCacheRepository
    }

    public func execute(bookUrl: String) async throws {
        try await bookRepository.removeBook(by: bookUrl)
        try? bookCacheRepository?.clearBookCache(bookUrl: bookUrl)
    }
}
