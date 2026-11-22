import Foundation

/// 系统设置 ViewModel (MVI 状态中枢)
@MainActor
public final class SettingsViewModel: BaseMVIViewModel<SettingsState, SettingsIntent, SettingsEffect> {
    private let webDAVClient: WebDAVClient
    private let backupUseCase: BackupToWebDAVUseCase
    private let restoreUseCase: RestoreFromWebDAVUseCase
    private let manageBookCacheUseCase: ManageBookCacheUseCase?
    private let realtimeSyncService: WebDAVRealtimeSyncService?
    private let onBookshelfUpdated: (@MainActor () -> Void)?

    public init(
        webDAVClient: WebDAVClient = .shared,
        backupUseCase: BackupToWebDAVUseCase,
        restoreUseCase: RestoreFromWebDAVUseCase,
        manageBookCacheUseCase: ManageBookCacheUseCase? = nil,
        realtimeSyncService: WebDAVRealtimeSyncService? = nil,
        onBookshelfUpdated: (@MainActor () -> Void)? = nil) {
        self.webDAVClient = webDAVClient
        self.backupUseCase = backupUseCase
        self.restoreUseCase = restoreUseCase
        self.manageBookCacheUseCase = manageBookCacheUseCase
        self.realtimeSyncService = realtimeSyncService
        self.onBookshelfUpdated = onBookshelfUpdated

        let savedConfig = WebDAVConfigStore.loadForEditing()
        let initialSpeechRate = TTSPlayer.shared.speechRate
        let initialSpeechPitch = TTSPlayer.shared.speechPitch
        let initialCacheSize = manageBookCacheUseCase?.calculateTotalCacheSize() ?? 0

        super.init(initialState: SettingsState(
            webDAVConfig: savedConfig,
            speechRate: initialSpeechRate,
            speechPitch: initialSpeechPitch,
            cacheSizeBytes: initialCacheSize,
            readerConfig: ReaderConfigStore.load(),
            importedFonts: LocalFontManager.shared.listImportedFonts()))
    }

    override public func send(_ intent: SettingsIntent) {
        switch intent {
        case .updateWebDAVServer, .updateWebDAVUsername, .updateWebDAVPassword,
             .updateWebDAVDirectory, .updateWebDAVAllowInsecureCert, .updateWebDAVSyncOptions:
            handleConfigIntent(intent)

        case .testWebDAVConnection, .backupToWebDAV, .restoreFromWebDAV:
            handleSyncIntent(intent)

        case .updateSpeechRate, .updateSpeechPitch, .refreshCacheSize, .clearAllCache, .clearNotice:
            handleGeneralIntent(intent)

        case .refreshReaderConfig, .updateReaderConfig, .resetReaderConfig,
             .importLocalFonts, .selectLocalFont, .deleteLocalFont:
            handleReaderAndFontIntent(intent)
        }
    }

    private func handleConfigIntent(_ intent: SettingsIntent) {
        switch intent {
        case let .updateWebDAVServer(val):
            mutateWebDAVConfig { $0.serverUrl = val }

        case let .updateWebDAVUsername(val):
            mutateWebDAVConfig { $0.username = val }

        case let .updateWebDAVPassword(val):
            mutateWebDAVConfig { $0.password = val }

        case let .updateWebDAVDirectory(val):
            mutateWebDAVConfig { $0.remoteDirectory = val }

        case let .updateWebDAVAllowInsecureCert(allowed):
            mutateWebDAVConfig { $0.allowInsecureCertificate = allowed }

        case let .updateWebDAVSyncOptions(options):
            mutateWebDAVConfig { $0.syncOptions = options }

        default:
            break
        }
    }

    private func mutateWebDAVConfig(_ mutate: (inout WebDAVConfig) -> Void) {
        updateState {
            mutate(&$0.webDAVConfig)
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        saveCurrentConfig()
    }

    private func handleSyncIntent(_ intent: SettingsIntent) {
        switch intent {
        case .testWebDAVConnection:
            runConnectionTest()

        case .backupToWebDAV:
            runBackup()

        case .restoreFromWebDAV:
            runRestore()

        default:
            break
        }
    }

    private func handleGeneralIntent(_ intent: SettingsIntent) {
        switch intent {
        case let .updateSpeechRate(rate):
            updateState { $0.speechRate = rate }
            TTSPlayer.shared.speechRate = rate

        case let .updateSpeechPitch(pitch):
            updateState { $0.speechPitch = pitch }
            TTSPlayer.shared.speechPitch = pitch

        case .refreshCacheSize:
            let size = manageBookCacheUseCase?.calculateTotalCacheSize() ?? 0
            updateState { $0.cacheSizeBytes = size }

        case .clearAllCache:
            try? manageBookCacheUseCase?.clearAllCache()
            let size = manageBookCacheUseCase?.calculateTotalCacheSize() ?? 0
            updateState { $0.cacheSizeBytes = size }
            emitEffect(.showToast("已清理所有离线正文缓存"))
            emitEffect(.hapticFeedback)

        case .clearNotice:
            updateState {
                $0.errorMessage = nil
                $0.successMessage = nil
            }

        default:
            break
        }
    }

    private func handleReaderAndFontIntent(_ intent: SettingsIntent) {
        switch intent {
        case .refreshReaderConfig:
            updateState {
                $0.readerConfig = ReaderConfigStore.load()
                $0.importedFonts = LocalFontManager.shared.listImportedFonts()
                $0.speechRate = TTSPlayer.shared.speechRate
                $0.speechPitch = TTSPlayer.shared.speechPitch
            }

        case let .updateReaderConfig(config):
            updateState { $0.readerConfig = config }
            ReaderConfigStore.save(config)
            realtimeSyncService?.scheduleRulesPush()
            if config.isHapticEnabled {
                emitEffect(.hapticFeedback)
            }

        case .resetReaderConfig:
            let defaults = ReaderConfigStore.reset()
            updateState { $0.readerConfig = defaults }
            realtimeSyncService?.scheduleRulesPush()
            emitEffect(.showToast("已恢复默认阅读排版与偏好"))
            emitEffect(.hapticFeedback)

        case let .importLocalFonts(urls):
            handleImportLocalFonts(urls: urls)

        case let .selectLocalFont(font):
            var updated = state.readerConfig
            updated.customFontName = font.postScriptName
            updated.customFontDisplayName = font.displayName
            updateState { $0.readerConfig = updated }
            ReaderConfigStore.save(updated)
            realtimeSyncService?.scheduleRulesPush()
            emitEffect(.showToast("已切换阅读字体为「\(font.displayName)」"))
            emitEffect(.hapticFeedback)

        case let .deleteLocalFont(font):
            handleDeleteLocalFont(font)

        default:
            break
        }
    }

    private func handleImportLocalFonts(urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                var imported: [ImportedFont] = []
                var lastError: Error?
                for url in urls {
                    do {
                        let font = try LocalFontManager.shared.importFont(from: url)
                        imported.append(font)
                    } catch {
                        lastError = error
                    }
                }
                let allFonts = LocalFontManager.shared.listImportedFonts()
                return (imported, allFonts, lastError)
            }.value

            updateState { $0.importedFonts = result.1 }
            if let first = result.0.first {
                var updated = state.readerConfig
                updated.customFontName = first.postScriptName
                updated.customFontDisplayName = first.displayName
                updateState { $0.readerConfig = updated }
                ReaderConfigStore.save(updated)
                let msg = result.0.count == 1
                    ? "已导入并应用字体「\(first.displayName)」"
                    : "成功导入 \(result.0.count) 款本地字体"
                emitEffect(.showToast(msg))
                emitEffect(.hapticFeedback)
            } else if let lastError = result.2 {
                emitEffect(.showToast("字体导入失败: \(lastError.localizedDescription)"))
            }
        }
    }

    private func handleDeleteLocalFont(_ font: ImportedFont) {
        do {
            try LocalFontManager.shared.deleteFont(font)
            let updatedFonts = LocalFontManager.shared.listImportedFonts()
            updateState { $0.importedFonts = updatedFonts }
            if state.readerConfig.customFontName == font.postScriptName {
                var updated = state.readerConfig
                updated.customFontName = nil
                updated.customFontDisplayName = nil
                updateState { $0.readerConfig = updated }
                ReaderConfigStore.save(updated)
                realtimeSyncService?.scheduleRulesPush()
            }
            emitEffect(.showToast("已删除字体「\(font.displayName)」"))
            emitEffect(.hapticFeedback)
        } catch {
            emitEffect(.showToast("删除字体失败: \(error.localizedDescription)"))
        }
    }
}

// MARK: - WebDAV 同步与配置持久化

private extension SettingsViewModel {
    func runConnectionTest() {
        runWebDAVTask(
            setBusy: { $0.isTestingConnection = $1 },
            failurePrefix: "连接失败",
            operation: { config in
                _ = try await self.webDAVClient.testConnection(config: config)
                self.updateState {
                    $0.errorMessage = nil
                    $0.successMessage = "WebDAV 服务器连接成功，认证通过！"
                }
                self.emitEffect(.showToast("WebDAV 认证通过，连接成功"))
            })
    }

    func runBackup() {
        let options = state.webDAVConfig.syncOptions
        guard validateSyncOptions(options) else { return }

        runWebDAVTask(
            setBusy: { $0.isBackingUp = $1 },
            failurePrefix: "备份失败",
            operation: { [weak self] config in
                guard let self else { return }
                let summary = try await self.backupUseCase.execute(config: config, options: options)
                let msg = Self.formatSyncSummary(summary, options: options, isRestore: false)
                self.updateState {
                    $0.lastBackupSummary = summary
                    $0.errorMessage = nil
                    $0.successMessage = "云端备份成功：\(msg)"
                }
                self.emitEffect(.showToast(msg))
            })
    }

    func runRestore() {
        let options = state.webDAVConfig.syncOptions
        guard validateSyncOptions(options) else { return }

        runWebDAVTask(
            setBusy: { $0.isRestoring = $1 },
            failurePrefix: "还原失败",
            operation: { [weak self] config in
                guard let self else { return }
                let summary = try await self.restoreUseCase.execute(config: config, options: options)
                let msg = Self.formatSyncSummary(summary, options: options, isRestore: true)
                self.updateState {
                    $0.lastBackupSummary = summary
                    $0.errorMessage = nil
                    $0.successMessage = "云端还原成功：\(msg)"
                }
                if options.syncRules {
                    self.send(.refreshReaderConfig)
                }
                if options.syncProgress || options.syncBookFiles {
                    self.onBookshelfUpdated?()
                }
                self.emitEffect(.showToast(msg))
            })
    }

    private func validateSyncOptions(_ options: WebDAVSyncOptions) -> Bool {
        guard options.hasAnySelection else {
            let msg = "请至少选择一项需要同步的内容"
            updateState {
                $0.errorMessage = msg
                $0.successMessage = nil
            }
            emitEffect(.showToast(msg))
            return false
        }
        return true
    }

    private static func formatSyncSummary(
        _ summary: WebDAVBackupSummary,
        options: WebDAVSyncOptions,
        isRestore: Bool) -> String {
        var parts: [String] = []
        if options.syncProgress {
            parts.append("\(summary.bookCount) 本书进度")
            if summary.bookmarkCount > 0 {
                parts.append("\(summary.bookmarkCount) 条书签")
            }
        }
        if options.syncRules {
            parts.append("\(summary.ruleCount) 条规则与排版")
        }
        if options.syncBookFiles {
            parts.append("\(summary.bookFileCount) 本本地书籍文件")
        }
        let sizeKB = max(summary.dataSizeBytes / 1024, 1)
        var text = parts.joined(separator: "、") + " (\(sizeKB) KB)"
        if isRestore, summary.skippedBookCount > 0 {
            text += "；已跳过 \(summary.skippedBookCount) 本缺失文件的本地书籍"
        }
        return text
    }

    func runWebDAVTask(
        setBusy: @escaping (inout SettingsState, Bool) -> Void,
        failurePrefix: String,
        operation: @escaping @MainActor (WebDAVConfig) async throws -> Void) {
        guard state.webDAVConfig.isValid else {
            let msg = "请输入有效的 WebDAV 服务器地址"
            updateState {
                $0.errorMessage = msg
                $0.successMessage = nil
            }
            emitEffect(.showToast(msg))
            return
        }

        updateState {
            setBusy(&$0, true)
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        let config = state.webDAVConfig

        Task { [weak self] in
            do {
                try await operation(config)
                guard let self else { return }
                self.updateState { setBusy(&$0, false) }
                self.emitEffect(.hapticFeedback)
            } catch {
                guard let self else { return }
                self.updateState {
                    setBusy(&$0, false)
                    $0.successMessage = nil
                    $0.errorMessage = error.localizedDescription
                }
                self.emitEffect(.showToast("\(failurePrefix): \(error.localizedDescription)"))
            }
        }
    }

    func saveCurrentConfig() {
        WebDAVConfigStore.save(state.webDAVConfig)
    }

    static func loadSavedWebDAVConfig() -> WebDAVConfig {
        WebDAVConfigStore.loadForEditing()
    }
}
