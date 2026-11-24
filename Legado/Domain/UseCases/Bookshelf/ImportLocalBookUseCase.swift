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
    private static let maxLocalFileBytes = 150 * 1024 * 1024
    private static let titleTagRegexes: [NSRegularExpression] = [
        "\\[.*?\\]",
        "\\(.*?\\)",
        "【.*?】",
        "（.*?）",
        "全本",
        "精校",
        "校对版",
        "完整版",
        "精校版",
    ].compactMap { try? NSRegularExpression(pattern: $0) }

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
        let bookUrl = await resolveTargetBookUrl(
            name: parsed.title,
            author: parsed.author,
            chapterCount: parsed.chapters.count)
        let coverUrl = saveCoverImageIfPresent(
            data: parsed.coverData,
            ext: parsed.coverExtension,
            bookUrl: bookUrl)

        let existing = try? await bookRepository.getBook(by: bookUrl)
        let book = Book(
            bookUrl: bookUrl,
            tocUrl: bookUrl,
            origin: "local",
            originName: "本地 EPUB",
            name: parsed.title,
            author: parsed.author,
            coverUrl: coverUrl ?? existing?.coverUrl,
            intro: parsed.intro,
            latestChapterTitle: parsed.chapters.last?.title,
            durChapterTitle: existing?.durChapterTitle ?? parsed.chapters.first?.title,
            durChapterIndex: min(existing?.durChapterIndex ?? 0, max(parsed.chapters.count - 1, 0)),
            durChapterPos: existing?.durChapterPos ?? 0,
            durChapterTime: existing?.durChapterTime ?? 0,
            wordCount: formatWordCount(parsed.totalWordCount),
            totalChapterNum: parsed.chapters.count,
            groupName: existing?.groupName)

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

        let bookUrl = await resolveTargetBookUrl(
            name: title,
            author: "本地导入",
            chapterCount: parsedChapters.count)
        let existing = try? await bookRepository.getBook(by: bookUrl)
        let book = Book(
            bookUrl: bookUrl,
            tocUrl: bookUrl,
            origin: "local",
            originName: "本地书籍",
            name: title,
            author: existing?.author ?? "本地导入",
            coverUrl: existing?.coverUrl,
            latestChapterTitle: parsedChapters.last?.title,
            durChapterTitle: existing?.durChapterTitle ?? parsedChapters.first?.title,
            durChapterIndex: min(existing?.durChapterIndex ?? 0, max(parsedChapters.count - 1, 0)),
            durChapterPos: existing?.durChapterPos ?? 0,
            durChapterTime: existing?.durChapterTime ?? 0,
            wordCount: formatWordCount(content.count),
            totalChapterNum: parsedChapters.count,
            groupName: existing?.groupName)

        try await persistImportedBook(book: book, parsedChapters: parsedChapters)
        return book
    }

    private func resolveTargetBookUrl(name: String, author: String, chapterCount: Int) async -> String {
        guard let shelf = try? await bookRepository.getBookshelf() else {
            return "local://\(UUID().uuidString)"
        }
        let targetName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let matched = shelf.first(where: {
            $0.isLocalFile &&
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetName &&
                WebDAVSyncHelper.authorsMatch($0.author, author) &&
                ($0.totalChapterNum == 0 || abs($0.totalChapterNum - chapterCount) <= 2)
        }) {
            return matched.bookUrl
        }
        return "local://\(UUID().uuidString)"
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
        guard let data, !data.isEmpty, data.count <= WebDAVSyncHelper.maxCoverArchiveBytes else { return nil }
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let coversDir = docs.appendingPathComponent("BookCovers", isDirectory: true)
        try? fileManager.createDirectory(at: coversDir, withIntermediateDirectories: true)

        let key = BookCacheRepositoryImpl.deterministicKey(for: bookUrl)
        let safeExt = WebDAVSyncHelper.sanitizeImageExtension(ext)
        let coverFile = coversDir.appendingPathComponent("\(key).\(safeExt)")
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

        if let size = (try? fileUrl.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           size > Self.maxLocalFileBytes {
            throw LocalBookImportError.unreadableFile
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
        for regex in Self.titleTagRegexes {
            name = regex.stringByReplacingMatches(
                in: name,
                options: [],
                range: NSRange(location: 0, length: name.utf16.count),
                withTemplate: "")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? rawName : trimmed
    }
}
