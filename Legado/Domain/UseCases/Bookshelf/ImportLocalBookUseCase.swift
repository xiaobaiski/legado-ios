import Foundation

/// 本地书籍导入错误定义
public enum LocalBookImportError: LocalizedError, Sendable {
    case unsupportedFormat(String)
    case unreadableFile
    case emptyContent

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            return "暂不支持 .\(ext) 格式，请选择 TXT 文本文件"

        case .unreadableFile:
            return "无法读取所选文件，请确认文件已下载到本地"

        case .emptyContent:
            return "文件内容为空，无法解析章节"
        }
    }
}

/// 本地书籍导入用例 (支持 TXT 智能分卷解析与持久化)
public final class ImportLocalBookUseCase: Sendable {
    private static let supportedExtensions: Set<String> = ["", "txt", "text", "md", "log"]

    private let bookRepository: BookRepository
    private let bookCacheRepository: BookCacheRepository

    public init(
        bookRepository: BookRepository,
        bookCacheRepository: BookCacheRepository) {
        self.bookRepository = bookRepository
        self.bookCacheRepository = bookCacheRepository
    }

    /// 导入本地文件至书架
    public func execute(fileUrl: URL) async throws -> Book {
        let ext = fileUrl.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw LocalBookImportError.unsupportedFormat(ext)
        }

        let fileData = try readSecurityScopedFile(at: fileUrl)
        let rawFileName = fileUrl.deletingPathExtension().lastPathComponent
        let cleanedTitle = cleanBookTitle(rawFileName)

        // 字符编码自适应探测 (UTF-8 / UTF-16 / GBK / Big5)
        let content = CharsetDetector.decode(data: fileData)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalBookImportError.emptyContent
        }

        // 智能正则切分章节
        let parsedChapters = TxtTocParser.parse(text: content)
        guard !parsedChapters.isEmpty else {
            throw LocalBookImportError.emptyContent
        }

        let bookUrl = "local://\(UUID().uuidString)"
        let wordCountText = formatWordCount(content.count)
        let book = Book(
            bookUrl: bookUrl,
            tocUrl: bookUrl,
            origin: "local",
            originName: "本地书籍",
            name: cleanedTitle,
            author: "本地导入",
            latestChapterTitle: parsedChapters.last?.title,
            durChapterTitle: parsedChapters.first?.title,
            durChapterIndex: 0,
            durChapterTime: Int64(Date().timeIntervalSince1970 * 1000),
            wordCount: wordCountText,
            totalChapterNum: parsedChapters.count)

        let chapters = parsedChapters.map { parsed in
            Chapter(
                url: "\(bookUrl)/\(parsed.index)",
                title: parsed.title,
                bookUrl: bookUrl,
                index: parsed.index)
        }

        // 持久化各章节内容至磁盘离线缓存
        for parsed in parsedChapters {
            try bookCacheRepository.saveChapterContent(
                bookUrl: bookUrl,
                index: parsed.index,
                content: parsed.content)
        }

        // 持久化目录与书籍信息
        try await bookRepository.saveChapters(chapters, for: bookUrl)
        try await bookRepository.saveBook(book)

        return book
    }

    private func readSecurityScopedFile(at fileUrl: URL) throws -> Data {
        let isAccessing = fileUrl.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                fileUrl.stopAccessingSecurityScopedResource()
            }
        }

        var coordinatorError: NSError?
        var readResult: Result<Data, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: fileUrl, options: [], error: &coordinatorError) { coordinatedUrl in
            do {
                readResult = .success(try Data(contentsOf: coordinatedUrl))
            } catch {
                readResult = .failure(error)
            }
        }

        if let coordinatorError {
            throw coordinatorError
        }
        guard let readResult else {
            throw LocalBookImportError.unreadableFile
        }
        return try readResult.get()
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
