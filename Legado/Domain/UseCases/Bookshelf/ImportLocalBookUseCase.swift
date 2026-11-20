import Foundation

/// 本地书籍导入错误定义
public enum LocalBookImportError: LocalizedError, Sendable {
    case unsupportedFormat(String)
    case unreadableFile
    case emptyContent

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            return "暂不支持 .\(ext) 格式，请选择 TXT 或 EPUB 电子书"

        case .unreadableFile:
            return "无法读取所选文件，请确认文件已下载到本地"

        case .emptyContent:
            return "文件内容为空，无法解析章节"
        }
    }
}

/// 本地书籍导入用例 (支持 TXT 智能分卷解析与 EPUB 元数据/封面/目录解析持久化)
public final class ImportLocalBookUseCase: Sendable {
    private static let supportedExtensions: Set<String> = ["", "txt", "text", "md", "log", "epub"]

    private let bookRepository: BookRepository
    private let bookCacheRepository: BookCacheRepository

    public init(
        bookRepository: BookRepository,
        bookCacheRepository: BookCacheRepository) {
        self.bookRepository = bookRepository
        self.bookCacheRepository = bookCacheRepository
    }

    /// 导入本地文件（TXT / EPUB）至书架
    public func execute(fileUrl: URL) async throws -> Book {
        let ext = fileUrl.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw LocalBookImportError.unsupportedFormat(ext)
        }

        let fileData = try readSecurityScopedFile(at: fileUrl)
        let rawFileName = fileUrl.deletingPathExtension().lastPathComponent
        let cleanedTitle = cleanBookTitle(rawFileName)

        if ext == "epub" {
            return try await importEpub(data: fileData, fallbackTitle: cleanedTitle)
        }
        return try await importPlainText(data: fileData, title: cleanedTitle)
    }

    private func importEpub(data: Data, fallbackTitle: String) async throws -> Book {
        let parsed = try EpubParser.parse(data: data, fallbackTitle: fallbackTitle)
        let bookUrl = "local://\(UUID().uuidString)"
        let coverUrl = saveCoverImageIfPresent(
            data: parsed.coverData,
            ext: parsed.coverExtension,
            bookUrl: bookUrl)

        let book = Book(
            bookUrl: bookUrl,
            tocUrl: bookUrl,
            origin: "local",
            originName: "本地 EPUB",
            name: parsed.title,
            author: parsed.author,
            coverUrl: coverUrl,
            intro: parsed.intro,
            latestChapterTitle: parsed.chapters.last?.title,
            durChapterTitle: parsed.chapters.first?.title,
            durChapterIndex: 0,
            durChapterTime: Int64(Date().timeIntervalSince1970 * 1000),
            wordCount: formatWordCount(parsed.totalWordCount),
            totalChapterNum: parsed.chapters.count)

        try await persistImportedBook(book: book, parsedChapters: parsed.chapters)
        return book
    }

    private func importPlainText(data: Data, title: String) async throws -> Book {
        let content = CharsetDetector.decode(data: data)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalBookImportError.emptyContent
        }

        let parsedChapters = TxtTocParser.parse(text: content)
        guard !parsedChapters.isEmpty else {
            throw LocalBookImportError.emptyContent
        }

        let bookUrl = "local://\(UUID().uuidString)"
        let book = Book(
            bookUrl: bookUrl,
            tocUrl: bookUrl,
            origin: "local",
            originName: "本地书籍",
            name: title,
            author: "本地导入",
            latestChapterTitle: parsedChapters.last?.title,
            durChapterTitle: parsedChapters.first?.title,
            durChapterIndex: 0,
            durChapterTime: Int64(Date().timeIntervalSince1970 * 1000),
            wordCount: formatWordCount(content.count),
            totalChapterNum: parsedChapters.count)

        try await persistImportedBook(book: book, parsedChapters: parsedChapters)
        return book
    }

    private func persistImportedBook(book: Book, parsedChapters: [ParsedTxtChapter]) async throws {
        let chapters = parsedChapters.map { parsed in
            Chapter(
                url: "\(book.bookUrl)/\(parsed.index)",
                title: parsed.title,
                bookUrl: book.bookUrl,
                index: parsed.index)
        }

        for parsed in parsedChapters {
            try bookCacheRepository.saveChapterContent(
                bookUrl: book.bookUrl,
                index: parsed.index,
                content: parsed.content)
        }

        try await bookRepository.saveChapters(chapters, for: book.bookUrl)
        try await bookRepository.saveBook(book)
    }

    private func saveCoverImageIfPresent(data: Data?, ext: String, bookUrl: String) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let coversDir = docs.appendingPathComponent("BookCovers", isDirectory: true)
        try? fileManager.createDirectory(at: coversDir, withIntermediateDirectories: true)

        let key = BookCacheRepositoryImpl.deterministicKey(for: bookUrl)
        let coverFile = coversDir.appendingPathComponent("\(key).\(ext)")
        do {
            try data.write(to: coverFile, options: .atomic)
            return coverFile.absoluteString
        } catch {
            return nil
        }
    }

    private func readSecurityScopedFile(at fileUrl: URL) throws -> Data {
        let isAccessing = fileUrl.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                fileUrl.stopAccessingSecurityScopedResource()
            }
            if fileUrl.path.contains("LegadoImportStaging") {
                try? FileManager.default.removeItem(at: fileUrl.deletingLastPathComponent())
            }
        }

        do {
            return try Data(contentsOf: fileUrl)
        } catch {
            throw LocalBookImportError.unreadableFile
        }
    }

    private func formatWordCount(_ count: Int) -> String {
        if count >= 10000 {
            return String(format: "%.1f万字", Double(count) / 10000.0)
        }
        return "\(count)字"
    }

    /// 净化书名文件名 (剔除常见网文标签如 [全本]、(校对版))
    private func cleanBookTitle(_ rawName: String) -> String {
        var name = rawName
        let tagsToRemove = [
            "\\[.*?\\]",
            "\\(.*?\\)",
            "【.*?】",
            "（.*?）",
            "全本",
            "精校",
            "校对版",
            "完整版",
            "精校版",
        ]
        for pattern in tagsToRemove {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                name = regex.stringByReplacingMatches(
                    in: name,
                    options: [],
                    range: NSRange(location: 0, length: name.utf16.count),
                    withTemplate: "")
            }
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? rawName : trimmed
    }
}
