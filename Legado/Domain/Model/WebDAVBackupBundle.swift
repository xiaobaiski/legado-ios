import Foundation

/// WebDAV 选择性同步选项（进度/书签、规则/排版、本地书籍文件与可选实时同步）
public struct WebDAVSyncOptions: Codable, Equatable, Sendable {
    /// 同步阅读进度、书架记录与书签
    public var syncProgress: Bool
    /// 同步净化规则、TXT 目录规则与阅读排版配置
    public var syncRules: Bool
    /// 同步本地导入书籍文件（章节目录、正文与本地封面，压缩归档）
    public var syncBookFiles: Bool
    /// 启用后台/阅读时可选实时自动同步
    public var autoSyncEnabled: Bool
    /// 实时同步阅读进度（默认开启，仅在已配置 WebDAV 时生效）
    public var realtimeSyncProgress: Bool
    /// 实时同步净化规则与排版设置（默认关闭）
    public var realtimeSyncRules: Bool

    public static let defaultSelection = WebDAVSyncOptions(
        syncProgress: true,
        syncRules: true,
        syncBookFiles: true,
        autoSyncEnabled: true,
        realtimeSyncProgress: true,
        realtimeSyncRules: false)

    public static let all = defaultSelection

    public var hasAnySelection: Bool {
        syncProgress || syncRules || syncBookFiles
    }

    enum CodingKeys: String, CodingKey {
        case syncProgress
        case syncRules
        case syncBookFiles
        case autoSyncEnabled
        case realtimeSyncProgress
        case realtimeSyncRules
    }

    public init(
        syncProgress: Bool = true,
        syncRules: Bool = true,
        syncBookFiles: Bool = true,
        autoSyncEnabled: Bool = true,
        realtimeSyncProgress: Bool = true,
        realtimeSyncRules: Bool = false) {
        self.syncProgress = syncProgress
        self.syncRules = syncRules
        self.syncBookFiles = syncBookFiles
        self.autoSyncEnabled = autoSyncEnabled
        self.realtimeSyncProgress = realtimeSyncProgress
        self.realtimeSyncRules = realtimeSyncRules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncProgress = try container.decodeIfPresent(Bool.self, forKey: .syncProgress) ?? true
        syncRules = try container.decodeIfPresent(Bool.self, forKey: .syncRules) ?? true
        syncBookFiles = try container.decodeIfPresent(Bool.self, forKey: .syncBookFiles) ?? true
        autoSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? true
        realtimeSyncProgress = try container.decodeIfPresent(Bool.self, forKey: .realtimeSyncProgress) ?? true
        realtimeSyncRules = try container.decodeIfPresent(Bool.self, forKey: .realtimeSyncRules) ?? false
    }
}

/// 轻量级单本书实时阅读进度快照
public struct WebDAVBookProgress: Codable, Equatable, Sendable {
    public let bookUrl: String
    public let name: String
    public let author: String
    public let durChapterIndex: Int
    public let durChapterPos: Int
    public let durChapterTitle: String?
    public let durChapterTime: Int64
    public let totalChapterNum: Int

    public init(
        bookUrl: String,
        name: String,
        author: String,
        durChapterIndex: Int,
        durChapterPos: Int,
        durChapterTitle: String?,
        durChapterTime: Int64,
        totalChapterNum: Int = 0) {
        self.bookUrl = bookUrl
        self.name = name
        self.author = author
        self.durChapterIndex = durChapterIndex
        self.durChapterPos = durChapterPos
        self.durChapterTitle = durChapterTitle
        self.durChapterTime = durChapterTime
        self.totalChapterNum = totalChapterNum
    }

    public init(from book: Book) {
        self.bookUrl = book.bookUrl
        self.name = book.name
        self.author = book.author
        self.durChapterIndex = book.durChapterIndex
        self.durChapterPos = book.durChapterPos
        self.durChapterTitle = book.durChapterTitle
        self.durChapterTime = book.durChapterTime
        self.totalChapterNum = book.totalChapterNum
    }
}

/// WebDAV 轻量级实时阅读进度汇总文件（`reading_progress.json`）
public struct WebDAVProgressBundle: Codable, Equatable, Sendable {
    public let version: Int
    public let updatedAt: Date
    public let items: [WebDAVBookProgress]

    public init(
        version: Int = 1,
        updatedAt: Date = Date(),
        items: [WebDAVBookProgress] = []) {
        self.version = version
        self.updatedAt = updatedAt
        self.items = items
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
        appVersion: String = "1.2.0",
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
