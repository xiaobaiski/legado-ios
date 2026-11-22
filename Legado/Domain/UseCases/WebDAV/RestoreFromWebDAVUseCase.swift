import Foundation

/// 从 WebDAV 云端还原数据用例（还原书架进度、净化规则、TXT 目录规则、阅读统计与排版偏好）
public final class RestoreFromWebDAVUseCase: @unchecked Sendable {
    private let bookRepository: BookRepository
    private let sourceRepository: BookSourceRepository
    private let webDAVClient: WebDAVClient
    private let replaceRuleStore: ReplaceRuleStore
    private let txtTocRuleStore: TxtTocRuleStore
    private let readRecordStore: ReadRecordStore
    private let readerConfigImporter: @Sendable (String) -> Void

    public init(
        bookRepository: BookRepository,
        sourceRepository: BookSourceRepository,
        webDAVClient: WebDAVClient = .shared,
        replaceRuleStore: ReplaceRuleStore = .shared,
        txtTocRuleStore: TxtTocRuleStore = .shared,
        readRecordStore: ReadRecordStore = .shared,
        readerConfigImporter: @escaping @Sendable (String) -> Void = { _ = ReaderConfigStore.importJSON($0) }) {
        self.bookRepository = bookRepository
        self.sourceRepository = sourceRepository
        self.webDAVClient = webDAVClient
        self.replaceRuleStore = replaceRuleStore
        self.txtTocRuleStore = txtTocRuleStore
        self.readRecordStore = readRecordStore
        self.readerConfigImporter = readerConfigImporter
    }

    /// 执行云端还原
    public func execute(config: WebDAVConfig) async throws -> WebDAVBackupSummary {
        let data = try await webDAVClient.download(
            filename: "legado_backup.json",
            config: config)

        return try await restore(from: data)
    }

    /// 从备份 JSON 二进制数据恢复至本地存储
    public func restore(from bundleData: Data) async throws -> WebDAVBackupSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(WebDAVBackupBundle.self, from: bundleData)

        // 兼容还原内置/历史书源
        if !bundle.sources.isEmpty {
            try await sourceRepository.saveSources(bundle.sources)
        }

        // 还原书架与阅读进度
        for book in bundle.books {
            try await bookRepository.saveBook(book)
        }

        // 还原替换净化规则与 TXT 目录规则
        if !bundle.replaceRules.isEmpty {
            replaceRuleStore.saveRules(bundle.replaceRules)
        }
        if let txtRules = bundle.txtTocRules, !txtRules.isEmpty {
            txtTocRuleStore.saveRules(txtRules)
        }

        // 合并还原阅读时长统计与排版配置
        if let records = bundle.readRecords, !records.isEmpty {
            readRecordStore.mergeRecords(records)
        }
        if let configJson = bundle.readerConfigJson, !configJson.isEmpty {
            readerConfigImporter(configJson)
        }

        let totalRuleCount = bundle.replaceRules.count + (bundle.txtTocRules?.count ?? 0)
        return WebDAVBackupSummary(
            bookCount: bundle.books.count,
            sourceCount: bundle.sources.count,
            dataSizeBytes: bundleData.count,
            backupDate: bundle.backupTime,
            ruleCount: totalRuleCount)
    }
}
