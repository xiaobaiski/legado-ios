import Foundation

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

    public init(
        version: Int = 1,
        backupTime: Date = Date(),
        appVersion: String = "1.0.1",
        books: [Book] = [],
        sources: [BookSource] = [],
        replaceRules: [ReplaceRule] = [],
        txtTocRules: [TxtTocRule]? = nil,
        readRecords: [ReadRecord]? = nil,
        readerConfigJson: String? = nil) {
        self.version = version
        self.backupTime = backupTime
        self.appVersion = appVersion
        self.books = books
        self.sources = sources
        self.replaceRules = replaceRules
        self.txtTocRules = txtTocRules
        self.readRecords = readRecords
        self.readerConfigJson = readerConfigJson
    }
}
