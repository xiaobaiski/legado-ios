import Foundation

/// 获取书籍目录章节列表用例（纯本地存储读取，支持本地 TXT 修改目录规则后强制重分章）
public final class GetBookTocUseCase: Sendable {
    private let bookRepository: BookRepository
    private let bookCacheRepository: BookCacheRepository

    public init(
        bookRepository: BookRepository,
        bookCacheRepository: BookCacheRepository = BookCacheRepositoryImpl()) {
        self.bookRepository = bookRepository
        self.bookCacheRepository = bookCacheRepository
    }

    public func execute(book: Book, forceRefresh: Bool = false) async throws -> [Chapter] {
        let existing = try await bookRepository.getChapters(for: book.bookUrl)
        guard forceRefresh,
              book.isLocalFile,
              book.originName == "本地书籍",
              !existing.isEmpty else {
            return existing
        }
        return try await resplitTxtChaptersIfPossible(book: book, existing: existing) ?? existing
    }

    private func resplitTxtChaptersIfPossible(book: Book, existing: [Chapter]) async throws -> [Chapter]? {
        var combinedSections: [String] = []
        combinedSections.reserveCapacity(existing.count)
        for chapter in existing {
            guard let body = bookCacheRepository.getCachedChapterContent(
                bookUrl: book.bookUrl,
                index: chapter.index) else {
                continue
            }
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let isDefaultChunk = chapter.title.hasPrefix("第 ") && chapter.title.hasSuffix(" 节")
            let isGenericTitle = chapter.title == "正文" || chapter.title == "前言"
            if isDefaultChunk || isGenericTitle || trimmedBody.hasPrefix(chapter.title) {
                combinedSections.append(body)
            } else {
                combinedSections.append("\(chapter.title)\n\(body)")
            }
        }
        let fullText = combinedSections.joined(separator: "\n")
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let reparsed = TxtTocParser.parse(text: fullText)
        guard !reparsed.isEmpty else { return nil }
        guard reparsed.count != existing.count ||
            zip(reparsed, existing).contains(where: { $0.title != $1.title }) else {
            return nil
        }

        try? bookCacheRepository.clearBookCache(bookUrl: book.bookUrl)
        let chapters = reparsed.map { item in
            Chapter(
                url: "\(book.bookUrl)/\(item.index)",
                title: item.title,
                bookUrl: book.bookUrl,
                index: item.index)
        }
        for item in reparsed {
            try bookCacheRepository.saveChapterContent(bookUrl: book.bookUrl, index: item.index, content: item.content)
        }
        try await bookRepository.saveChapters(chapters, for: book.bookUrl)

        var updatedBook = book
        updatedBook.totalChapterNum = chapters.count
        updatedBook.latestChapterTitle = chapters.last?.title
        if chapters.indices.contains(updatedBook.durChapterIndex) {
            updatedBook.durChapterTitle = chapters[updatedBook.durChapterIndex].title
        } else {
            updatedBook.durChapterIndex = max(min(updatedBook.durChapterIndex, chapters.count - 1), 0)
            updatedBook.durChapterPos = 0
            updatedBook.durChapterTitle = chapters.first?.title
        }
        try await bookRepository.saveBook(updatedBook)
        return chapters
    }
}
