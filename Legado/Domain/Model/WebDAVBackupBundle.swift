import Foundation

/// WebDAV 选择性同步选项（进度/书签、规则/排版、本地书籍文件）
public struct WebDAVSyncOptions: Codable, Equatable, Sendable {
    /// 同步阅读进度、书架记录与书签
    public var syncProgress: Bool
    /// 同步净化规则、TXT 目录规则与阅读排版配置
    public var syncRules: Bool
    /// 同步本地导入书籍文件（章节目录、正文与本地封面，压缩归档）
    public var syncBookFiles: Bool

    public static let defaultSelection = WebDAVSyncOptions(
        syncProgress: true,
        syncRules: true,
        syncBookFiles: true)

    public static let all = defaultSelection

    public var hasAnySelection: Bool {
        syncProgress || syncRules || syncBookFiles
    }

    enum CodingKeys: String, CodingKey {
        case syncProgress
        case syncRules
        case syncBookFiles
    }

    public init(
        syncProgress: Bool = true,
        syncRules: Bool = true,
        syncBookFiles: Bool = true) {
        self.syncProgress = syncProgress
        self.syncRules = syncRules
        self.syncBookFiles = syncBookFiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncProgress = try container.decodeIfPresent(Bool.self, forKey: .syncProgress) ?? true
        syncRules = try container.decodeIfPresent(Bool.self, forKey: .syncRules) ?? true
        syncBookFiles = try container.decodeIfPresent(Bool.self, forKey: .syncBookFiles) ?? true
    }
}

/// 远程已归档本地书籍索引条目
public struct WebDAVBookFileEntry: Codable, Equatable, Sendable {
    public let bookUrl: String
    public let name: String
    public let author: String
    public let archiveFileName: String
    public let chapterCount: Int
    public let updatedAt: Int64

    public init(
        bookUrl: String,
        name: String,
        author: String,
        archiveFileName: String,
        chapterCount: Int,
        updatedAt: Int64) {
        self.bookUrl = bookUrl
        self.name = name
        self.author = author
        self.archiveFileName = archiveFileName
        self.chapterCount = chapterCount
        self.updatedAt = updatedAt
    }
}

/// 单章归档正文条目
public struct WebDAVArchivedChapter: Codable, Sendable {
    public let index: Int
    public let content: String

    public init(index: Int, content: String) {
        self.index = index
        self.content = content
    }
}

/// 单本本地书籍独立压缩包（zlib 压缩，存于 WebDAV 远端 `books/<key>.legadobook`）
public struct WebDAVLocalBookArchive: Codable, Sendable {
    public let book: Book
    public let chapters: [Chapter]
    public let chapterContents: [WebDAVArchivedChapter]
    public let coverImageData: Data?
    public let coverFileExtension: String?

    public init(
        book: Book,
        chapters: [Chapter],
        chapterContents: [WebDAVArchivedChapter],
        coverImageData: Data? = nil,
        coverFileExtension: String? = nil) {
        self.book = book
        self.chapters = chapters
        self.chapterContents = chapterContents
        self.coverImageData = coverImageData
        self.coverFileExtension = coverFileExtension
    }

    /// 序列化并用 zlib 压缩，大幅降低 WebDAV 传输体积
    public func compressedData() throws -> Data {
        let rawData = try JSONEncoder().encode(self)
        return try (rawData as NSData).compressed(using: .zlib) as Data
    }

    /// 解压并反序列化本地书籍归档
    public static func decompress(from data: Data) throws -> WebDAVLocalBookArchive {
        if let rawData = try? (data as NSData).decompressed(using: .zlib) as Data,
           let decoded = try? JSONDecoder().decode(WebDAVLocalBookArchive.self, from: rawData) {
            return decoded
        }
        return try JSONDecoder().decode(WebDAVLocalBookArchive.self, from: data)
    }
}

/// WebDAV 完整云端备份包结构
public struct WebDAVBackupBundle: Codable, Sendable {
    public let version: Int
    public let backupTime: Date
    public let appVersion: String
    public let books: [Book]
    public let sources: [BookSource]
    public let replaceRules: [ReplaceRule]
    public let txtTocRules: [TxtTocRule]?
    public let readRecords: [ReadRecord]?
    public let readerConfigJson: String?
    public let bookmarks: [Bookmark]?
    public let bookFiles: [WebDAVBookFileEntry]?

    public init(
        version: Int = 2,
        backupTime: Date = Date(),
        appVersion: String = "1.1.1",
        books: [Book] = [],
        sources: [BookSource] = [],
        replaceRules: [ReplaceRule] = [],
        txtTocRules: [TxtTocRule]? = nil,
        readRecords: [ReadRecord]? = nil,
        readerConfigJson: String? = nil,
        bookmarks: [Bookmark]? = nil,
        bookFiles: [WebDAVBookFileEntry]? = nil) {
        self.version = version
        self.backupTime = backupTime
        self.appVersion = appVersion
        self.books = books
        self.sources = sources
        self.replaceRules = replaceRules
        self.txtTocRules = txtTocRules
        self.readRecords = readRecords
        self.readerConfigJson = readerConfigJson
        self.bookmarks = bookmarks
        self.bookFiles = bookFiles
    }
}
