import Foundation

/// 阅读器目标导航模型
public struct ReaderDestination: Identifiable, Sendable {
    public let id: String
    public let book: Book
    public let chapterIndex: Int?
    public let initialOffset: Int?

    public init(book: Book, chapterIndex: Int? = nil, initialOffset: Int? = nil) {
        let keyPart = chapterIndex.map(String.init) ?? "resume"
        let offsetPart = initialOffset.map { "_\($0)" } ?? ""
        self.id = "\(book.bookUrl)_\(keyPart)\(offsetPart)"
        self.book = book
        self.chapterIndex = chapterIndex
        self.initialOffset = initialOffset
    }
}
