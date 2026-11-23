import Foundation
@testable import Legado
import SwiftData
import Testing

@Suite("SwiftData Book Storage Suite")
struct BookStorageTests {
    @Test("Test SwiftData Book and Chapter Persistence")
    func bookAndChapterStorage() async throws {
        let provider = ModelContainerProvider(inMemory: true)
        let repo = BookRepositoryImpl(modelContainer: provider.container)

        let book = Book(
            bookUrl: "local://test/book/123",
            tocUrl: "",
            origin: "local",
            originName: "本地导入",
            name: "诡秘之主",
            author: "爱潜水的乌贼",
            kind: "西方玄幻",
            intro: "蒸汽与机械的浪潮中...")

        try await repo.saveBook(book)

        let shelf = try await repo.getBookshelf()
        #expect(shelf.count == 1)
        #expect(shelf.first?.name == "诡秘之主")
        #expect(shelf.first?.author == "爱潜水的乌贼")

        // Save chapters
        let chapters = [
            Chapter(url: "local://test/book/123/0", title: "第一章 绯红", bookUrl: book.bookUrl, index: 0),
            Chapter(url: "local://test/book/123/1", title: "第二章 宿命", bookUrl: book.bookUrl, index: 1),
        ]
        try await repo.saveChapters(chapters, for: book.bookUrl)

        let fetchedChapters = try await repo.getChapters(for: book.bookUrl)
        #expect(fetchedChapters.count == 2)
        #expect(fetchedChapters[0].title == "第一章 绯红")

        // Read Record
        let record = ReadRecord(bookName: "诡秘之主", bookAuthor: "爱潜水的乌贼", readTimeSeconds: 3600, wordsRead: 15000)
        try await repo.saveReadRecord(record)

        let fetchedRecord = try await repo.getReadRecord(bookName: "诡秘之主", bookAuthor: "爱潜水的乌贼")
        #expect(fetchedRecord != nil)
        #expect(fetchedRecord?.wordsRead == 15000)

        // Remove book
        try await repo.removeBook(by: book.bookUrl)
        let emptyShelf = try await repo.getBookshelf()
        #expect(emptyShelf.isEmpty)
        let emptyChapters = try await repo.getChapters(for: book.bookUrl)
        #expect(emptyChapters.isEmpty)
    }
}
