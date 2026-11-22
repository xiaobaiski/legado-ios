import Combine
import Foundation

public typealias RealtimeBackgroundTaskStarter =
    @MainActor (@escaping @MainActor () -> Void) -> (@MainActor () -> Void)

/// WebDAV 可选实时自动同步服务：默认仅在用户已保存完整 WebDAV 配置且启用实时同步时激活
@MainActor
public final class WebDAVRealtimeSyncService: ObservableObject {
    static let progressFileName = "reading_progress.json"
    static let fallbackBackupFileName = "legado_backup.json"
    static let rulesFileName = "rules_sync.json"
    static let rulesTimestampKey = "legado_webdav_rules_updated_at"

    @Published public private(set) var status = WebDAVRealtimeSyncStatus()

    let bookRepository: BookRepository
    let backupUseCase: BackupToWebDAVUseCase
    let webDAVClient: WebDAVClient
    let replaceRuleStore: ReplaceRuleStore
    let txtTocRuleStore: TxtTocRuleStore
    let readerConfigExporter: @Sendable () -> String?
    let readerConfigImporter: @Sendable (String) -> Void
    let rulesTimestampDefaults: UserDefaults
    let configProvider: @Sendable () -> WebDAVConfig?
    let backgroundTaskProvider: RealtimeBackgroundTaskStarter?

    public var onBookshelfUpdated: @MainActor () -> Void
    public var onRulesUpdated: @MainActor () -> Void

    private var pendingBooks: [String: Book] = [:]
    private var lastGlobalPullAt: Date = .distantPast
    var lastRulesPullAt: Date = .distantPast
    let globalPullCooldown: TimeInterval = 10
    private var activeSyncCount = 0

    nonisolated(unsafe) private var progressDebounceTask: Task<Void, Never>?
    nonisolated(unsafe) var activeProgressPushTask: Task<Void, Never>?
    private var activeProgressEndTask: (@MainActor () -> Void)?

    nonisolated(unsafe) var rulesDebounceTask: Task<Void, Never>?
    nonisolated(unsafe) var activeRulesPushTask: Task<Void, Never>?
    var activeRulesEndTask: (@MainActor () -> Void)?
    var hasPendingRulesPush = false

    public init(
        bookRepository: BookRepository,
        backupUseCase: BackupToWebDAVUseCase,
        webDAVClient: WebDAVClient = .shared,
        replaceRuleStore: ReplaceRuleStore = .shared,
        txtTocRuleStore: TxtTocRuleStore = .shared,
        readerConfigExporter: @escaping @Sendable () -> String? = { ReaderConfigStore.exportJSON() },
        readerConfigImporter: @escaping @Sendable (String) -> Void = { _ = ReaderConfigStore.importJSON($0) },
        rulesTimestampDefaults: UserDefaults = .standard,
        configProvider: @escaping @Sendable () -> WebDAVConfig? = {
            WebDAVConfigStore.loadSavedIfConfigured()
        },
        backgroundTaskProvider: RealtimeBackgroundTaskStarter? = nil,
        onBookshelfUpdated: @escaping @MainActor () -> Void = {},
        onRulesUpdated: @escaping @MainActor () -> Void = {}) {
        self.bookRepository = bookRepository
        self.backupUseCase = backupUseCase
        self.webDAVClient = webDAVClient
        self.replaceRuleStore = replaceRuleStore
        self.txtTocRuleStore = txtTocRuleStore
        self.readerConfigExporter = readerConfigExporter
        self.readerConfigImporter = readerConfigImporter
        self.rulesTimestampDefaults = rulesTimestampDefaults
        self.configProvider = configProvider
        self.backgroundTaskProvider = backgroundTaskProvider
        self.onBookshelfUpdated = onBookshelfUpdated
        self.onRulesUpdated = onRulesUpdated
    }

    deinit {
        progressDebounceTask?.cancel()
        activeProgressPushTask?.cancel()
        rulesDebounceTask?.cancel()
        activeRulesPushTask?.cancel()
    }

    /// 安排防抖后的实时阅读进度上传（切页、切章后触发，不会取消已在途的上传）
    public func scheduleProgressPush(book: Book, debounceSeconds: TimeInterval = 2.5) {
        guard let config = activeConfig(), config.syncOptions.realtimeSyncProgress else { return }
        let key = WebDAVSyncHelper.progressIdentityKey(
            name: book.name,
            author: book.author,
            bookUrl: book.bookUrl)
        pendingBooks[key] = book

        progressDebounceTask?.cancel()
        progressDebounceTask = Task { [weak self] in
            if debounceSeconds > 0 {
                let nanos = UInt64(debounceSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
            guard let self, !Task.isCancelled else { return }
            self.startProgressDrainIfNeeded(useBackgroundTask: false)
        }
    }

    /// 退出阅读或退入后台时立即冲洗待同步进度（含后台保活保护）
    public func flushPendingProgressPush() {
        progressDebounceTask?.cancel()
        progressDebounceTask = nil
        guard !pendingBooks.isEmpty || activeProgressPushTask != nil else { return }
        guard let config = activeConfig(), config.syncOptions.realtimeSyncProgress else { return }

        if activeProgressPushTask != nil {
            ensureProgressBackgroundTask()
            return
        }
        _ = config
        startProgressDrainIfNeeded(useBackgroundTask: true)
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

        beginSyncCycle()
        defer { endSyncCycle() }

        let remoteItems: [WebDAVBookProgress]
        do {
            remoteItems = try await fetchRemoteProgressItemsStrict(config: config, allowBackupFallback: true)
        } catch {
            recordSyncFailure(error)
            return nil
        }

        if targetBook == nil {
            lastGlobalPullAt = Date()
        }
        guard !remoteItems.isEmpty else {
            clearSyncError()
            return nil
        }

        guard let localBooks = try? await bookRepository.getBookshelf() else { return nil }
        let updatedBooks = await applyRemoteProgressItems(remoteItems, to: localBooks)

        if !updatedBooks.isEmpty {
            recordSyncSuccess("已拉取 \(updatedBooks.count) 本书最新进度")
            onBookshelfUpdated()
        } else {
            clearSyncError()
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
}

// MARK: - 串行进度推送队列与内部状态管理

extension WebDAVRealtimeSyncService {
    func activeConfig() -> WebDAVConfig? {
        guard let config = configProvider(),
              config.isValid,
              config.syncOptions.autoSyncEnabled else {
            return nil
        }
        return config
    }

    func beginSyncCycle() {
        activeSyncCount += 1
        status.isSyncing = true
    }

    func endSyncCycle() {
        activeSyncCount = max(0, activeSyncCount - 1)
        status.isSyncing = activeSyncCount > 0
    }

    func clearSyncError() {
        status.lastErrorMessage = nil
    }

    func recordSyncSuccess(_ summary: String) {
        status.lastSyncAt = Date()
        status.lastSyncSummary = summary
        status.lastErrorMessage = nil
    }

    func recordSyncFailure(_ error: Error) {
        status.lastErrorMessage = error.localizedDescription
    }

    func fetchRemoteProgressItemsStrict(
        config: WebDAVConfig,
        allowBackupFallback: Bool) async throws -> [WebDAVBookProgress] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let progressData = try await webDAVClient.download(filename: Self.progressFileName, config: config)
            guard let bundle = try? decoder.decode(WebDAVProgressBundle.self, from: progressData) else {
                throw WebDAVError.serverError(statusCode: 500, message: "云端进度索引解析失败")
            }
            return bundle.items
        } catch WebDAVError.notFound {
            guard allowBackupFallback else { return [] }
        }

        do {
            let backupData = try await webDAVClient.download(filename: Self.fallbackBackupFileName, config: config)
            guard let backup = try? decoder.decode(WebDAVBackupBundle.self, from: backupData) else {
                throw WebDAVError.serverError(statusCode: 500, message: "云端备份文件解析失败")
            }
            return backup.books.map(WebDAVBookProgress.init(from:))
        } catch WebDAVError.notFound {
            return []
        }
    }

    private func applyRemoteProgressItems(
        _ remoteItems: [WebDAVBookProgress],
        to localBooks: [Book]) async -> [Book] {
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
        return updatedBooks
    }

    private func startProgressDrainIfNeeded(useBackgroundTask: Bool) {
        if useBackgroundTask {
            ensureProgressBackgroundTask()
        }
        guard activeProgressPushTask == nil else { return }

        activeProgressPushTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.activeProgressPushTask = nil
                self.activeProgressEndTask?()
                self.activeProgressEndTask = nil
            }
            await self.drainPendingProgressQueue()
        }
    }

    private func ensureProgressBackgroundTask() {
        guard activeProgressEndTask == nil, let starter = backgroundTaskProvider else { return }
        activeProgressEndTask = starter { [weak self] in
            self?.activeProgressPushTask?.cancel()
        }
    }

    private func drainPendingProgressQueue() async {
        beginSyncCycle()
        defer { endSyncCycle() }

        while !Task.isCancelled, !pendingBooks.isEmpty {
            guard let config = activeConfig(), config.syncOptions.realtimeSyncProgress else {
                pendingBooks.removeAll()
                return
            }

            let booksToPush = Array(pendingBooks.values)
            pendingBooks.removeAll()

            do {
                try await uploadMergedProgressBatch(booksToPush, config: config)
                recordSyncSuccess("已同步阅读进度（\(booksToPush.count) 本）")
            } catch {
                requeueFailedBooks(booksToPush)
                recordSyncFailure(error)
                break
            }
        }
    }

    private func uploadMergedProgressBatch(_ booksToPush: [Book], config: WebDAVConfig) async throws {
        let remoteItems = try await fetchRemoteProgressItemsStrict(config: config, allowBackupFallback: false)
        let localItems = booksToPush.map(WebDAVBookProgress.init(from:))
        let merged = WebDAVSyncHelper.mergeProgressBundles(localItems: localItems, remoteItems: remoteItems)
        let payload = WebDAVProgressBundle(updatedAt: Date(), items: merged)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        try await webDAVClient.upload(
            data: data,
            filename: Self.progressFileName,
            config: config,
            ensureDirectory: false)
    }

    private func requeueFailedBooks(_ books: [Book]) {
        for book in books {
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
