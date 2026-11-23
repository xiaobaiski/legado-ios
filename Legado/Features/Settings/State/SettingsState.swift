import Foundation

/// 系统设置状态模型
public struct SettingsState: ViewState, Equatable, Sendable {
    public var webDAVConfig: WebDAVConfig
    public var isTestingConnection: Bool
    public var isBackingUp: Bool
    public var isRestoring: Bool
    public var lastBackupSummary: WebDAVBackupSummary?
    public var realtimeSyncStatus: WebDAVRealtimeSyncStatus
    public var cacheSizeBytes: Int64
    public var readerConfig: ReaderConfig
    public var importedFonts: [ImportedFont]
    public var errorMessage: String?
    public var successMessage: String?

    public init(
        webDAVConfig: WebDAVConfig = WebDAVConfig(),
        isTestingConnection: Bool = false,
        isBackingUp: Bool = false,
        isRestoring: Bool = false,
        lastBackupSummary: WebDAVBackupSummary? = nil,
        realtimeSyncStatus: WebDAVRealtimeSyncStatus = WebDAVRealtimeSyncStatus(),
        cacheSizeBytes: Int64 = 0,
        readerConfig: ReaderConfig = ReaderConfig.defaultConfig,
        importedFonts: [ImportedFont] = [],
        errorMessage: String? = nil,
        successMessage: String? = nil) {
        self.webDAVConfig = webDAVConfig
        self.isTestingConnection = isTestingConnection
        self.isBackingUp = isBackingUp
        self.isRestoring = isRestoring
        self.lastBackupSummary = lastBackupSummary
        self.realtimeSyncStatus = realtimeSyncStatus
        self.cacheSizeBytes = cacheSizeBytes
        self.readerConfig = readerConfig
        self.importedFonts = importedFonts
        self.errorMessage = errorMessage
        self.successMessage = successMessage
    }

    public var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file)
    }
}
