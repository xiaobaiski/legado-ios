import Foundation

/// 获取书籍目录章节列表用例（纯本地存储读取）
public final class GetBookTocUseCase: Sendable {
    private let bookRepository: BookRepository

    public init(bookRepository: BookRepository) {
        self.bookRepository = bookRepository
    }

    public func execute(book: Book, forceRefresh _: Bool = false) async throws -> [Chapter] {
        try await bookRepository.getChapters(for: book.bookUrl)
    }
}
