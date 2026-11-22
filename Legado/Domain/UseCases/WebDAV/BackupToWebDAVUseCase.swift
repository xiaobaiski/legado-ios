import Foundation

/// 备份至 WebDAV 云端存储用例（支持按进度/规则/本地书籍文件独立选择性同步）
public final class BackupToWebDAVUseCase: @unchecked Sendable {
    private let bookRepository: BookRepository
    private let sourceRepository: BookSourceRepository
    private let bookmarkRepository: BookmarkRepository?
    private let bookCacheRepository: BookCacheRepository?
    private let webDAVClient: WebDAVClient
    private let replaceRuleStore: ReplaceRuleStore
    private let txtTocRuleStore: TxtTocRuleStore
    private let readRecordStore: ReadRecordStore
    private let readerConfigExporter: @Sendable () -> String?

    public init(
        bookRepository: BookRepository,
        sourceRepository: BookSourceRepository,
        bookmarkRepository: BookmarkRepository? = nil,
        bookCacheRepository: BookCacheRepository? = nil,
        webDAVClient: WebDAVClient = .shared,
        replaceRuleStore: ReplaceRuleStore = .shared,
        txtTocRuleStore: TxtTocRuleStore = .shared,
        readRecordStore: ReadRecordStore = .shared,
        readerConfigExporter: @escaping @Sendable () -> String? = { ReaderConfigStore.exportJSON() }) {
        self.bookRepository = bookRepository
        self.sourceRepository = sourceRepository
        self.bookmarkRepository = bookmarkRepository
        self.bookCacheRepository = bookCacheRepository
        self.webDAVClient = webDAVClient
        self.replaceRuleStore = replaceRuleStore
        self.txtTocRuleStore = txtTocRuleStore
        self.readRecordStore = readRecordStore
        self.readerConfigExporter = readerConfigExporter
    }

    /// 生成完整备份数据包 Bundle
    public func generateBackupBundle() async throws -> WebDAVBackupBundle {
        let books = try await bookRepository.getBookshelf()
        let sources = try await sourceRepository.fetchSources()
        let replaceRules = replaceRuleStore.loadRules()
        let txtTocRules = txtTocRuleStore.loadRules()
        let readRecords = readRecordStore.allRecordsSorted()
        let bookmarks = try await loadBookmarks()
        let configJson = readerConfigExporter()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.1"

        return WebDAVBackupBundle(
            version: 2,
            backupTime: Date(),
            appVersion: appVersion,
            books: books,
            sources: sources,
            replaceRules: replaceRules,
            txtTocRules: txtTocRules,
            readRecords: readRecords,
            readerConfigJson: configJson,
            bookmarks: bookmarks)
    }

    /// 导出为 JSON 数据
    public func exportBackupJsonData(bundle: WebDAVBackupBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    /// 执行云端备份（默认使用配置中的同步选项）
    public func execute(config: WebDAVConfig) async throws -> WebDAVBackupSummary {
        try await execute(config: config, options: config.syncOptions)
    }

    /// 按指定选择项执行选择性云端备份
    public func execute(
        config: WebDAVConfig,
        options: WebDAVSyncOptions) async throws -> WebDAVBackupSummary {
        guard options.hasAnySelection else {
            throw WebDAVError.serverError(statusCode: 400, message: "请至少选择一项需要备份的内容")
        }

        let remoteBundle = options == .all ? nil : await fetchExistingRemoteBundle(config: config)
        let localBooks = try await bookRepository.getBookshelf()
        let uploadedFiles = options.syncBookFiles
            ? try await uploadBookArchives(books: localBooks, config: config)
            : (entries: [WebDAVBookFileEntry](), uploadedBytes: 0)

        let bundle = try await buildMergedBundle(
            localBooks: localBooks,
            options: options,
            remoteBundle: remoteBundle,
            uploadedEntries: uploadedFiles.entries)
        let data = try exportBackupJsonData(bundle: bundle)

        try await webDAVClient.upload(
            data: data,
            filename: "legado_backup.json",
            config: config)

        return makeSummary(
            bundle: bundle,
            options: options,
            jsonSize: data.count,
            archiveBytes: uploadedFiles.uploadedBytes,
            uploadedBookFileCount: uploadedFiles.entries.count)
    }
}

// MARK: - Private Helpers

private extension BackupToWebDAVUseCase {
    func loadBookmarks() async throws -> [Bookmark] {
        guard let bookmarkRepository else { return [] }
        return try await bookmarkRepository.getAllBookmarks()
    }

    func fetchExistingRemoteBundle(config: WebDAVConfig) async -> WebDAVBackupBundle? {
        guard let data = try? await webDAVClient.download(filename: "legado_backup.json", config: config) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WebDAVBackupBundle.self, from: data)
    }

    func buildMergedBundle(
        localBooks: [Book],
        options: WebDAVSyncOptions,
        remoteBundle: WebDAVBackupBundle?,
        uploadedEntries: [WebDAVBookFileEntry]) async throws -> WebDAVBackupBundle {
        let books = options.syncProgress ? localBooks : (remoteBundle?.books ?? [])
        let sources = options.syncProgress
            ? try await sourceRepository.fetchSources()
            : (remoteBundle?.sources ?? [])
        let readRecords = options.syncProgress
            ? readRecordStore.allRecordsSorted()
            : remoteBundle?.readRecords
        let bookmarks = options.syncProgress
            ? try await loadBookmarks()
            : remoteBundle?.bookmarks

        let replaceRules = options.syncRules
            ? replaceRuleStore.loadRules()
            : (remoteBundle?.replaceRules ?? [])
        let txtTocRules = options.syncRules
            ? txtTocRuleStore.loadRules()
            : remoteBundle?.txtTocRules
        let configJson = options.syncRules
            ? readerConfigExporter()
            : remoteBundle?.readerConfigJson

        let bookFiles = options.syncBookFiles
            ? mergeBookFileEntries(uploaded: uploadedEntries, existing: remoteBundle?.bookFiles)
            : remoteBundle?.bookFiles
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.1"

        return WebDAVBackupBundle(
            version: 2,
            backupTime: Date(),
            appVersion: appVersion,
            books: books,
            sources: sources,
            replaceRules: replaceRules,
            txtTocRules: txtTocRules,
            readRecords: readRecords,
            readerConfigJson: configJson,
            bookmarks: bookmarks,
            bookFiles: bookFiles)
    }

    func mergeBookFileEntries(
        uploaded: [WebDAVBookFileEntry],
        existing: [WebDAVBookFileEntry]?) -> [WebDAVBookFileEntry] {
        var map: [String: WebDAVBookFileEntry] = [:]
        for item in existing ?? [] {
            map[item.archiveFileName] = item
        }
        for item in uploaded {
            map[item.archiveFileName] = item
        }
        return map.values.sorted { $0.archiveFileName < $1.archiveFileName }
    }

    func uploadBookArchives(
        books: [Book],
        config: WebDAVConfig) async throws -> (entries: [WebDAVBookFileEntry], uploadedBytes: Int) {
        guard let cacheRepo = bookCacheRepository else { return ([], 0) }

        var entries: [WebDAVBookFileEntry] = []
        var totalBytes = 0

        for book in books where WebDAVSyncHelper.isLocalImportedBook(book) {
            let chapters = try await bookRepository.getChapters(for: book.bookUrl)
            let archivedContents = collectArchivedChapters(
                bookUrl: book.bookUrl,
                chapters: chapters,
                cacheRepo: cacheRepo)
            guard !archivedContents.isEmpty else { continue }

            let cover = WebDAVSyncHelper.loadLocalCoverData(from: book.coverUrl)
            let archive = WebDAVLocalBookArchive(
                book: book,
                chapters: chapters,
                chapterContents: archivedContents,
                coverImageData: cover?.data,
                coverFileExtension: cover?.ext)
            let compressed = try archive.compressedData()
            let fileName = WebDAVSyncHelper.archiveFileName(
                name: book.name,
                author: book.author,
                bookUrl: book.bookUrl)

            try await webDAVClient.upload(
                data: compressed,
                subdirectories: ["books"],
                filename: fileName,
                contentType: "application/octet-stream",
                config: config)

            totalBytes += compressed.count
            entries.append(WebDAVBookFileEntry(
                bookUrl: book.bookUrl,
                name: book.name,
                author: book.author,
                archiveFileName: fileName,
                chapterCount: chapters.count,
                updatedAt: Int64(Date().timeIntervalSince1970 * 1000)))
        }
        return (entries, totalBytes)
    }

    func collectArchivedChapters(
        bookUrl: String,
        chapters: [Chapter],
        cacheRepo: BookCacheRepository) -> [WebDAVArchivedChapter] {
        let cachedIndices = cacheRepo.getCachedChapterIndices(bookUrl: bookUrl)
        let targetIndices = chapters.isEmpty
            ? cachedIndices.sorted()
            : Array(Set(chapters.map(\.index)).union(cachedIndices)).sorted()

        var result: [WebDAVArchivedChapter] = []
        result.reserveCapacity(targetIndices.count)
        for index in targetIndices {
            if let text = cacheRepo.getCachedChapterContent(bookUrl: bookUrl, index: index), !text.isEmpty {
                result.append(WebDAVArchivedChapter(index: index, content: text))
            }
        }
        return result
    }

    func makeSummary(
        bundle: WebDAVBackupBundle,
        options: WebDAVSyncOptions,
        jsonSize: Int,
        archiveBytes: Int,
        uploadedBookFileCount: Int) -> WebDAVBackupSummary {
        let totalRuleCount = options.syncRules
            ? bundle.replaceRules.count + (bundle.txtTocRules?.count ?? 0)
            : 0
        return WebDAVBackupSummary(
            bookCount: options.syncProgress ? bundle.books.count : 0,
            sourceCount: options.syncProgress ? bundle.sources.count : 0,
            dataSizeBytes: jsonSize + archiveBytes,
            backupDate: bundle.backupTime,
            ruleCount: totalRuleCount,
            bookmarkCount: options.syncProgress ? (bundle.bookmarks?.count ?? 0) : 0,
            bookFileCount: uploadedBookFileCount)
    }
}

/// 备份与恢复摘要信息
public struct WebDAVBackupSummary: Sendable, Equatable {
    public let bookCount: Int
    public let sourceCount: Int
    public let dataSizeBytes: Int
    public let backupDate: Date
    public let ruleCount: Int
    public let bookmarkCount: Int
    public let bookFileCount: Int
    public let skippedBookCount: Int

    public init(
        bookCount: Int,
        sourceCount: Int,
        dataSizeBytes: Int,
        backupDate: Date,
        ruleCount: Int = 0,
        bookmarkCount: Int = 0,
        bookFileCount: Int = 0,
        skippedBookCount: Int = 0) {
        self.bookCount = bookCount
        self.sourceCount = sourceCount
        self.dataSizeBytes = dataSizeBytes
        self.backupDate = backupDate
        self.ruleCount = ruleCount
        self.bookmarkCount = bookmarkCount
        self.bookFileCount = bookFileCount
        self.skippedBookCount = skippedBookCount
    }
}
