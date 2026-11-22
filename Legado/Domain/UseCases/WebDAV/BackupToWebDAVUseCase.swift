import Foundation

/// 备份至 WebDAV 云端存储用例（完整打包书架进度、净化规则、TXT 目录规则、阅读统计与排版偏好）
public final class BackupToWebDAVUseCase: @unchecked Sendable {
    private let bookRepository: BookRepository
    private let sourceRepository: BookSourceRepository
    private let webDAVClient: WebDAVClient
    private let replaceRuleStore: ReplaceRuleStore
    private let txtTocRuleStore: TxtTocRuleStore
    private let readRecordStore: ReadRecordStore
    private let readerConfigExporter: @Sendable () -> String?

    public init(
        bookRepository: BookRepository,
        sourceRepository: BookSourceRepository,
        webDAVClient: WebDAVClient = .shared,
        replaceRuleStore: ReplaceRuleStore = .shared,
        txtTocRuleStore: TxtTocRuleStore = .shared,
        readRecordStore: ReadRecordStore = .shared,
        readerConfigExporter: @escaping @Sendable () -> String? = { ReaderConfigStore.exportJSON() }) {
        self.bookRepository = bookRepository
        self.sourceRepository = sourceRepository
        self.webDAVClient = webDAVClient
        self.replaceRuleStore = replaceRuleStore
        self.txtTocRuleStore = txtTocRuleStore
        self.readRecordStore = readRecordStore
        self.readerConfigExporter = readerConfigExporter
    }

    /// 生成备份数据包 Bundle
    public func generateBackupBundle() async throws -> WebDAVBackupBundle {
        let books = try await bookRepository.getBookshelf()
        let sources = try await sourceRepository.fetchSources()
        let replaceRules = replaceRuleStore.loadRules()
        let txtTocRules = txtTocRuleStore.loadRules()
        let readRecords = readRecordStore.allRecordsSorted()
        let configJson = readerConfigExporter()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"

        return WebDAVBackupBundle(
            version: 2,
            backupTime: Date(),
            appVersion: appVersion,
            books: books,
            sources: sources,
            replaceRules: replaceRules,
            txtTocRules: txtTocRules,
            readRecords: readRecords,
            readerConfigJson: configJson)
    }

    /// 导出为 JSON 数据
    public func exportBackupJsonData(bundle: WebDAVBackupBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    /// 执行云端备份
    public func execute(config: WebDAVConfig) async throws -> WebDAVBackupSummary {
        let bundle = try await generateBackupBundle()
        let data = try exportBackupJsonData(bundle: bundle)

        try await webDAVClient.upload(
            data: data,
            filename: "legado_backup.json",
            config: config)

        let totalRuleCount = bundle.replaceRules.count + (bundle.txtTocRules?.count ?? 0)
        return WebDAVBackupSummary(
            bookCount: bundle.books.count,
            sourceCount: bundle.sources.count,
            dataSizeBytes: data.count,
            backupDate: bundle.backupTime,
            ruleCount: totalRuleCount)
    }
}

/// 备份摘要信息
public struct WebDAVBackupSummary: Sendable, Equatable {
    public let bookCount: Int
    public let sourceCount: Int
    public let dataSizeBytes: Int
    public let backupDate: Date
    public let ruleCount: Int

    public init(
        bookCount: Int,
        sourceCount: Int,
        dataSizeBytes: Int,
        backupDate: Date,
        ruleCount: Int = 0) {
        self.bookCount = bookCount
        self.sourceCount = sourceCount
        self.dataSizeBytes = dataSizeBytes
        self.backupDate = backupDate
        self.ruleCount = ruleCount
    }
}
