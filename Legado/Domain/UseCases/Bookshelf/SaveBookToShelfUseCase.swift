import Foundation

/// 添加或保存书籍至书架用例
public final class SaveBookToShelfUseCase: Sendable {
    private let bookRepository: BookRepository

    public init(bookRepository: BookRepository) {
        self.bookRepository = bookRepository
    }

    public func execute(_ book: Book) async throws {
        try await bookRepository.saveBook(book)
    }
}
