import Foundation

/// 获取书籍详细信息用例（纯本地存储读取）
public final class GetBookDetailUseCase: Sendable {
    private let bookRepository: BookRepository

    public init(bookRepository: BookRepository) {
        self.bookRepository = bookRepository
    }

    public func execute(book: Book) async throws -> Book {
        (try? await bookRepository.getBook(by: book.bookUrl)) ?? book
    }
}
