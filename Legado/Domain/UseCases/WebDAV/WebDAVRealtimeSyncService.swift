import Foundation

/// WebDAV 可选实时自动同步服务：默认仅在用户已保存 WebDAV 配置且启用实时同步时激活
@MainActor
public final class WebDAVRealtimeSyncService {
    private static let progressFileName = "reading_progress.json"
    private static let fallbackBackupFileName = "legado_backup.json"

    private let bookRepository: BookRepository
    private let backupUseCase: BackupToWebDAVUseCase
    private let webDAVClient: WebDAVClient
    private let configProvider: @Sendable () -> WebDAVConfig?
    public var onBookshelfUpdated: @MainActor () -> Void

    private var pendingBooks: [String: Book] = [:]
    private var lastGlobalPullAt: Date = .distantPast
    private let globalPullCooldown: TimeInterval = 10

    nonisolated(unsafe) private var pushTask: Task<Void, Never>?
    nonisolated(unsafe) private var rulesPushTask: Task<Void, Never>?

    public init(
        bookRepository: BookRepository,
        backupUseCase: BackupToWebDAVUseCase,
        webDAVClient: WebDAVClient = .shared,
        configProvider: @escaping @Sendable () -> WebDAVConfig? = {
            WebDAVConfigStore.loadSavedIfConfigured()
        },
        onBookshelfUpdated: @escaping @MainActor () -> Void = {}) {
        self.bookRepository = bookRepository
        self.backupUseCase = backupUseCase
        self.webDAVClient = webDAVClient
        self.configProvider = configProvider
        self.onBookshelfUpdated = onBookshelfUpdated
    }

    deinit {
        pushTask?.cancel()
        rulesPushTask?.cancel()
    }

    /// 安排防抖后的实时阅读进度上传（切页、切章后触发）
    public func scheduleProgressPush(book: Book, debounceSeconds: TimeInterval = 2.5) {
        guard let config = activeConfig(), config.syncOptions.realtimeSyncProgress else { return }
        let key = WebDAVSyncHelper.progressIdentityKey(
            name: book.name,
            author: book.author,
            bookUrl: book.bookUrl)
        pendingBooks[key] = book

        pushTask?.cancel()
        pushTask = Task { [weak self] in
            if debounceSeconds > 0 {
                let nanos = UInt64(debounceSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
            guard let self, !Task.isCancelled else { return }
            await self.performPendingProgressPush(config: config)
        }
    }

    /// 退出阅读或退入后台时立即冲洗待同步进度
    public func flushPendingProgressPush() {
        guard !pendingBooks.isEmpty,
              let config = activeConfig(),
              config.syncOptions.realtimeSyncProgress else {
            return
        }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            guard let self else { return }
            await self.performPendingProgressPush(config: config)
        }
    }

    /// 安排防抖后的规则与排版配置实时上传
    public func scheduleRulesPush(debounceSeconds: TimeInterval = 3.0) {
        guard let config = activeConfig(), config.syncOptions.realtimeSyncRules else { return }
        rulesPushTask?.cancel()
        rulesPushTask = Task { [weak self] in
            if debounceSeconds > 0 {
                let nanos = UInt64(debounceSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
            guard let self, !Task.isCancelled else { return }
            let rulesOnly = WebDAVSyncOptions(
                syncProgress: false,
                syncRules: true,
                syncBookFiles: false,
                autoSyncEnabled: config.syncOptions.autoSyncEnabled,
                realtimeSyncProgress: config.syncOptions.realtimeSyncProgress,
                realtimeSyncRules: config.syncOptions.realtimeSyncRules)
            _ = try? await self.backupUseCase.execute(config: config, options: rulesOnly)
        }
    }

    /// 从云端拉取最新阅读进度并合并到本地书库（打开书籍或回前台时按需触发）
    @discardableResult
    public func pullLatestProgressIfNeeded(for targetBook: Book? = nil, force: Bool = false) async -> Book? {
        guard let config = activeConfig(), config.syncOptions.realtimeSyncProgress else {
            return nil
        }
        if targetBook == nil && !force {
            guard Date().timeIntervalSince(lastGlobalPullAt) >= globalPullCooldown else {
                return nil
            }
        }

        let remoteItems = await fetchRemoteProgressItems(config: config)
        if targetBook == nil {
            lastGlobalPullAt = Date()
        }
        guard !remoteItems.isEmpty else { return nil }

        guard let localBooks = try? await bookRepository.getBookshelf() else {
            return nil
        }

        var updatedBooks: [Book] = []
        for item in remoteItems {
            guard let localMatch = WebDAVSyncHelper.findMatchingBook(
                name: item.name,
                author: item.author,
                bookUrl: item.bookUrl,
                in: localBooks),
                  let merged = WebDAVSyncHelper.mergeProgressItem(item, into: localMatch, preferRemote: false) else {
                continue
            }
            try? await bookRepository.saveBook(merged)
            updatedBooks.append(merged)
        }

        if !updatedBooks.isEmpty {
            onBookshelfUpdated()
        }

        guard let targetBook else { return nil }
        return updatedBooks.first {
            WebDAVSyncHelper.findMatchingBook(
                name: $0.name,
                author: $0.author,
                bookUrl: $0.bookUrl,
                in: [targetBook]) != nil
        }
    }

    // MARK: - Private

    private func activeConfig() -> WebDAVConfig? {
        guard let config = configProvider(),
              config.isValid,
              config.syncOptions.autoSyncEnabled else {
            return nil
        }
        return config
    }

    private func performPendingProgressPush(config: WebDAVConfig) async {
        let booksToPush = Array(pendingBooks.values)
        guard !booksToPush.isEmpty else { return }
        pendingBooks.removeAll()

        let remoteItems = await fetchRemoteProgressItems(config: config, allowBackupFallback: false)
        let localItems = booksToPush.map(WebDAVBookProgress.init(from:))
        let merged = WebDAVSyncHelper.mergeProgressBundles(localItems: localItems, remoteItems: remoteItems)
        let payload = WebDAVProgressBundle(updatedAt: Date(), items: merged)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }

        do {
            try await webDAVClient.upload(
                data: data,
                filename: Self.progressFileName,
                config: config)
        } catch {
            // 网络暂时不可用时放回队列等待下次推送
            for book in booksToPush {
                let key = WebDAVSyncHelper.progressIdentityKey(
                    name: book.name,
                    author: book.author,
                    bookUrl: book.bookUrl)
                if pendingBooks[key] == nil {
                    pendingBooks[key] = book
                }
            }
        }
    }

    private func fetchRemoteProgressItems(
        config: WebDAVConfig,
        allowBackupFallback: Bool = true) async -> [WebDAVBookProgress] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let progressData = try? await webDAVClient.download(filename: Self.progressFileName, config: config),
           let progressBundle = try? decoder.decode(WebDAVProgressBundle.self, from: progressData) {
            return progressBundle.items
        }
        guard allowBackupFallback,
              let backupData = try? await webDAVClient.download(filename: Self.fallbackBackupFileName, config: config),
              let backupBundle = try? decoder.decode(WebDAVBackupBundle.self, from: backupData) else {
            return []
        }
        return backupBundle.books.map(WebDAVBookProgress.init(from:))
    }
}
