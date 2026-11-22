import Foundation

/// 从 WebDAV 云端还原数据用例（支持选择性还原并彻底避免生成无正文幽灵书）
public final class RestoreFromWebDAVUseCase: @unchecked Sendable {
    private let bookRepository: BookRepository
    private let sourceRepository: BookSourceRepository
    private let bookmarkRepository: BookmarkRepository?
    private let bookCacheRepository: BookCacheRepository?
    private let webDAVClient: WebDAVClient
    private let replaceRuleStore: ReplaceRuleStore
    private let txtTocRuleStore: TxtTocRuleStore
    private let readRecordStore: ReadRecordStore
    private let readerConfigImporter: @Sendable (String) -> Void

    public init(
        bookRepository: BookRepository,
        sourceRepository: BookSourceRepository,
        bookmarkRepository: BookmarkRepository? = nil,
        bookCacheRepository: BookCacheRepository? = nil,
        webDAVClient: WebDAVClient = .shared,
        replaceRuleStore: ReplaceRuleStore = .shared,
        txtTocRuleStore: TxtTocRuleStore = .shared,
        readRecordStore: ReadRecordStore = .shared,
        readerConfigImporter: @escaping @Sendable (String) -> Void = { _ = ReaderConfigStore.importJSON($0) }) {
        self.bookRepository = bookRepository
        self.sourceRepository = sourceRepository
        self.bookmarkRepository = bookmarkRepository
        self.bookCacheRepository = bookCacheRepository
        self.webDAVClient = webDAVClient
        self.replaceRuleStore = replaceRuleStore
        self.txtTocRuleStore = txtTocRuleStore
        self.readRecordStore = readRecordStore
        self.readerConfigImporter = readerConfigImporter
    }

    /// 执行云端还原（默认按配置选项还原）
    public func execute(config: WebDAVConfig) async throws -> WebDAVBackupSummary {
        try await execute(config: config, options: config.syncOptions)
    }

    /// 按指定同步选项从云端还原
    public func execute(
        config: WebDAVConfig,
        options: WebDAVSyncOptions) async throws -> WebDAVBackupSummary {
        guard options.hasAnySelection else {
            throw WebDAVError.serverError(statusCode: 400, message: "请至少选择一项需要恢复的内容")
        }

        let data = try await webDAVClient.download(filename: "legado_backup.json", config: config)
        let bundle = try decodeBundle(from: data)

        var archives: [WebDAVLocalBookArchive] = []
        var totalDownloadedBytes = data.count
        var failedFileCount = 0

        if options.syncBookFiles, let entries = bundle.bookFiles, !entries.isEmpty {
            for entry in entries {
                do {
                    let archiveData = try await webDAVClient.download(
                        subdirectories: ["books"],
                        filename: entry.archiveFileName,
                        config: config)
                    totalDownloadedBytes += archiveData.count
                    archives.append(try WebDAVLocalBookArchive.decompress(from: archiveData))
                } catch {
                    failedFileCount += 1
                }
            }
        }

        return try await applyRestore(
            bundle: bundle,
            archives: archives,
            totalBytes: totalDownloadedBytes,
            options: options,
            initialSkippedCount: failedFileCount)
    }

    /// 从备份 JSON 二进制数据恢复至本地存储（便捷测试与本地还原入口）
    public func restore(
        from bundleData: Data,
        options: WebDAVSyncOptions = .defaultSelection) async throws -> WebDAVBackupSummary {
        let bundle = try decodeBundle(from: bundleData)
        return try await applyRestore(
            bundle: bundle,
            archives: [],
            totalBytes: bundleData.count,
            options: options,
            initialSkippedCount: 0)
    }
}

// MARK: - Private Restore Pipeline

private extension RestoreFromWebDAVUseCase {
    func decodeBundle(from data: Data) throws -> WebDAVBackupBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WebDAVBackupBundle.self, from: data)
    }

    func applyRestore(
        bundle: WebDAVBackupBundle,
        archives: [WebDAVLocalBookArchive],
        totalBytes: Int,
        options: WebDAVSyncOptions,
        initialSkippedCount: Int) async throws -> WebDAVBackupSummary {
        var localBooks = try await bookRepository.getBookshelf()
        var restoredBookFileCount = 0
        var handledArchiveUrls = Set<String>()

        if options.syncBookFiles {
            for archive in archives {
                let targetUrl = try await restoreBookArchive(
                    archive,
                    localBooks: &localBooks,
                    applyProgress: options.syncProgress)
                handledArchiveUrls.insert(archive.book.bookUrl)
                handledArchiveUrls.insert(targetUrl)
                restoredBookFileCount += 1
            }
        }

        var restoredBookCount = 0
        var restoredSourceCount = 0
        var restoredBookmarkCount = 0
        var skippedCount = initialSkippedCount

        if options.syncProgress {
            let result = try await restoreProgressAndMetadata(
                bundle: bundle,
                localBooks: &localBooks,
                handledArchiveUrls: handledArchiveUrls)
            restoredBookCount = result.books
            restoredSourceCount = result.sources
            restoredBookmarkCount = result.bookmarks
            skippedCount += result.skipped
        }

        let restoredRuleCount = options.syncRules ? restoreRulesAndConfig(bundle: bundle) : 0

        return WebDAVBackupSummary(
            bookCount: restoredBookCount,
            sourceCount: restoredSourceCount,
            dataSizeBytes: totalBytes,
            backupDate: bundle.backupTime,
            ruleCount: restoredRuleCount,
            bookmarkCount: restoredBookmarkCount,
            bookFileCount: restoredBookFileCount,
            skippedBookCount: skippedCount)
    }

    func restoreBookArchive(
        _ archive: WebDAVLocalBookArchive,
        localBooks: inout [Book],
        applyProgress: Bool) async throws -> String {
        let existing = WebDAVSyncHelper.findMatchingBook(
            name: archive.book.name,
            author: archive.book.author,
            bookUrl: archive.book.bookUrl,
            in: localBooks)
        let targetUrl = existing?.bookUrl ?? archive.book.bookUrl

        try await writeArchivedChapters(archive, targetBookUrl: targetUrl)

        var targetBook = resolveArchivedBookModel(
            archive: archive,
            existing: existing,
            applyProgress: applyProgress,
            targetUrl: targetUrl)

        if targetBook.totalChapterNum == 0 || !archive.chapters.isEmpty {
            targetBook.totalChapterNum = max(archive.chapters.count, targetBook.totalChapterNum)
        }
        if targetBook.latestChapterTitle == nil {
            targetBook.latestChapterTitle = archive.chapters.last?.title
        }

        try await bookRepository.saveBook(targetBook)
        if let idx = localBooks.firstIndex(where: { $0.bookUrl == targetBook.bookUrl }) {
            localBooks[idx] = targetBook
        } else {
            localBooks.append(targetBook)
        }
        return targetUrl
    }

    func resolveArchivedBookModel(
        archive: WebDAVLocalBookArchive,
        existing: Book?,
        applyProgress: Bool,
        targetUrl: String) -> Book {
        var targetBook: Book
        if let existing {
            targetBook = applyProgress
                ? WebDAVSyncHelper.mergeRemoteProgress(remote: archive.book, into: existing)
                : existing
        } else {
            targetBook = archive.book
            if !applyProgress {
                targetBook.durChapterIndex = 0
                targetBook.durChapterPos = 0
                targetBook.durChapterTitle = archive.chapters.first?.title
                targetBook.durChapterTime = 0
            }
        }
        if targetBook.coverUrl == nil || targetBook.coverUrl?.hasPrefix("file://") == true,
           let coverData = archive.coverImageData,
           let restoredCover = WebDAVSyncHelper.saveRestoredCoverData(
               coverData,
               fileExtension: archive.coverFileExtension,
               seed: targetUrl) {
            targetBook.coverUrl = restoredCover
        }
        return targetBook
    }

    func writeArchivedChapters(
        _ archive: WebDAVLocalBookArchive,
        targetBookUrl: String) async throws {
        let remappedChapters = archive.chapters.map { chapter in
            var copy = chapter
            copy.bookUrl = targetBookUrl
            copy.isCached = true
            return copy
        }
        if !remappedChapters.isEmpty {
            try await bookRepository.saveChapters(remappedChapters, for: targetBookUrl)
        }
        guard let cacheRepo = bookCacheRepository else { return }
        for item in archive.chapterContents {
            try cacheRepo.saveChapterContent(bookUrl: targetBookUrl, index: item.index, content: item.content)
        }
    }

    func restoreProgressAndMetadata(
        bundle: WebDAVBackupBundle,
        localBooks: inout [Book],
        handledArchiveUrls: Set<String>) async throws -> ProgressRestoreResult {
        if !bundle.sources.isEmpty {
            try await sourceRepository.saveSources(bundle.sources)
        }

        let syncResult = try await syncRemoteBooks(
            bundle.books,
            localBooks: &localBooks,
            handledArchiveUrls: handledArchiveUrls)

        if let records = bundle.readRecords, !records.isEmpty {
            readRecordStore.mergeRecords(records)
        }

        let bookmarkCount = try await restoreBookmarks(
            bundle.bookmarks,
            localBooks: localBooks,
            skippedUrls: syncResult.skippedUrls)

        return ProgressRestoreResult(
            books: syncResult.synced,
            sources: bundle.sources.count,
            bookmarks: bookmarkCount,
            skipped: syncResult.skipped)
    }

    func syncRemoteBooks(
        _ remoteBooks: [Book],
        localBooks: inout [Book],
        handledArchiveUrls: Set<String>) async throws -> BookSyncResult {
        var syncedBooks = 0
        var skippedBooks = 0
        var skippedUrls = Set<String>()

        for remoteBook in remoteBooks {
            if handledArchiveUrls.contains(remoteBook.bookUrl) {
                syncedBooks += 1
                continue
            }
            if let existing = WebDAVSyncHelper.findMatchingBook(
                name: remoteBook.name,
                author: remoteBook.author,
                bookUrl: remoteBook.bookUrl,
                in: localBooks) {
                let merged = WebDAVSyncHelper.mergeRemoteProgress(remote: remoteBook, into: existing)
                try await bookRepository.saveBook(merged)
                if let idx = localBooks.firstIndex(where: { $0.bookUrl == merged.bookUrl }) {
                    localBooks[idx] = merged
                }
                syncedBooks += 1
                continue
            }
            if WebDAVSyncHelper.isLocalImportedBook(remoteBook),
               bookCacheRepository?.getCachedChapterIndices(bookUrl: remoteBook.bookUrl).isEmpty != false {
                skippedBooks += 1
                skippedUrls.insert(remoteBook.bookUrl)
                continue
            }

            try await bookRepository.saveBook(remoteBook)
            localBooks.append(remoteBook)
            syncedBooks += 1
        }
        return BookSyncResult(synced: syncedBooks, skipped: skippedBooks, skippedUrls: skippedUrls)
    }

    func restoreBookmarks(
        _ bookmarks: [Bookmark]?,
        localBooks: [Book],
        skippedUrls: Set<String>) async throws -> Int {
        guard let bookmarkRepository, let bookmarks, !bookmarks.isEmpty else { return 0 }
        var restored = 0
        for bookmark in bookmarks where !skippedUrls.contains(bookmark.bookUrl) {
            let matched = WebDAVSyncHelper.findMatchingBook(
                name: bookmark.bookName,
                author: bookmark.bookAuthor,
                bookUrl: bookmark.bookUrl,
                in: localBooks)
            guard matched != nil || !bookmark.bookUrl.hasPrefix("local://") else { continue }
            let targetUrl = matched?.bookUrl ?? bookmark.bookUrl
            let mapped = Bookmark(
                time: bookmark.time,
                bookName: bookmark.bookName,
                bookAuthor: bookmark.bookAuthor,
                bookUrl: targetUrl,
                chapterIndex: bookmark.chapterIndex,
                chapterPos: bookmark.chapterPos,
                chapterName: bookmark.chapterName,
                bookText: bookmark.bookText,
                content: bookmark.content)
            try await bookmarkRepository.saveBookmark(mapped)
            restored += 1
        }
        return restored
    }

    func restoreRulesAndConfig(bundle: WebDAVBackupBundle) -> Int {
        if !bundle.replaceRules.isEmpty {
            replaceRuleStore.saveRules(bundle.replaceRules)
        }
        if let txtRules = bundle.txtTocRules, !txtRules.isEmpty {
            txtTocRuleStore.saveRules(txtRules)
        }
        if let configJson = bundle.readerConfigJson, !configJson.isEmpty {
            readerConfigImporter(configJson)
        }
        return bundle.replaceRules.count + (bundle.txtTocRules?.count ?? 0)
    }
}

private struct ProgressRestoreResult {
    let books: Int
    let sources: Int
    let bookmarks: Int
    let skipped: Int
}

private struct BookSyncResult {
    let synced: Int
    let skipped: Int
    let skippedUrls: Set<String>
}
