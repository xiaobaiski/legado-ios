import Foundation

/// 阅读器目标导航模型
public struct ReaderDestination: Identifiable, Sendable {
    public let id: String
    public let book: Book
    public let chapterIndex: Int?

    public init(book: Book, chapterIndex: Int? = nil) {
        let keyPart = chapterIndex.map(String.init) ?? "resume"
        self.id = "\(book.bookUrl)_\(keyPart)"
        self.book = book
        self.chapterIndex = chapterIndex
    }
}
