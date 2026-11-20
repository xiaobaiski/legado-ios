import Foundation

/// 系统设置 ViewModel (MVI 状态中枢)
@MainActor
public final class SettingsViewModel: BaseMVIViewModel<SettingsState, SettingsIntent, SettingsEffect> {
    private let webDAVClient: WebDAVClient
    private let backupUseCase: BackupToWebDAVUseCase
    private let restoreUseCase: RestoreFromWebDAVUseCase
    private let manageBookCacheUseCase: ManageBookCacheUseCase?

    private static let webDAVConfigKey = "legado_webdav_config"

    public init(
        webDAVClient: WebDAVClient = .shared,
        backupUseCase: BackupToWebDAVUseCase,
        restoreUseCase: RestoreFromWebDAVUseCase,
        manageBookCacheUseCase: ManageBookCacheUseCase? = nil) {
        self.webDAVClient = webDAVClient
        self.backupUseCase = backupUseCase
        self.restoreUseCase = restoreUseCase
        self.manageBookCacheUseCase = manageBookCacheUseCase

        let savedConfig = SettingsViewModel.loadSavedWebDAVConfig()
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
        case .updateWebDAVServer, .updateWebDAVUsername, .updateWebDAVPassword, .updateWebDAVDirectory:
            handleConfigIntent(intent)

        case .testWebDAVConnection, .backupToWebDAV, .restoreFromWebDAV:
            handleSyncIntent(intent)

        case .updateSpeechRate, .updateSpeechPitch, .refreshCacheSize, .clearAllCache,
             .refreshReaderConfig, .updateReaderConfig, .resetReaderConfig,
             .importLocalFonts, .selectLocalFont, .deleteLocalFont, .clearNotice:
            handleGeneralIntent(intent)
        }
    }

    private func handleConfigIntent(_ intent: SettingsIntent) {
        switch intent {
        case let .updateWebDAVServer(val):
            updateState { $0.webDAVConfig.serverUrl = val }
            saveCurrentConfig()

        case let .updateWebDAVUsername(val):
            updateState { $0.webDAVConfig.username = val }
            saveCurrentConfig()

        case let .updateWebDAVPassword(val):
            updateState { $0.webDAVConfig.password = val }
            saveCurrentConfig()

        case let .updateWebDAVDirectory(val):
            updateState { $0.webDAVConfig.remoteDirectory = val }
            saveCurrentConfig()

        default:
            break
        }
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

        case .refreshReaderConfig:
            updateState {
                $0.readerConfig = ReaderConfigStore.load()
                $0.importedFonts = LocalFontManager.shared.listImportedFonts()
            }

        case let .updateReaderConfig(config):
            updateState { $0.readerConfig = config }
            ReaderConfigStore.save(config)
            if config.isHapticEnabled {
                emitEffect(.hapticFeedback)
            }

        case .resetReaderConfig:
            let defaults = ReaderConfigStore.reset()
            updateState { $0.readerConfig = defaults }
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
            emitEffect(.showToast("已切换阅读字体为「\(font.displayName)」"))
            emitEffect(.hapticFeedback)

        case let .deleteLocalFont(font):
            handleDeleteLocalFont(font)

        case .clearNotice:
            updateState {
                $0.errorMessage = nil
                $0.successMessage = nil
            }

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
            }
            emitEffect(.showToast("已删除字体「\(font.displayName)」"))
            emitEffect(.hapticFeedback)
        } catch {
            emitEffect(.showToast("删除字体失败: \(error.localizedDescription)"))
        }
    }

    private func runConnectionTest() {
        guard state.webDAVConfig.isValid else {
            emitEffect(.showToast("请填写完整的 WebDAV 服务器地址与凭证"))
            return
        }

        updateState { $0.isTestingConnection = true }
        let config = state.webDAVConfig

        Task {
            do {
                _ = try await webDAVClient.testConnection(config: config)
                self.updateState { state in
                    state.isTestingConnection = false
                    state.successMessage = "WebDAV 服务器连接成功！"
                }
                self.emitEffect(.showToast("WebDAV 认证通过，连接成功"))
                self.emitEffect(.hapticFeedback)
            } catch {
                self.updateState { state in
                    state.isTestingConnection = false
                    state.errorMessage = error.localizedDescription
                }
                self.emitEffect(.showToast("连接失败: \(error.localizedDescription)"))
            }
        }
    }

    private func runBackup() {
        guard state.webDAVConfig.isValid else {
            emitEffect(.showToast("请先配置并测试 WebDAV 连接"))
            return
        }

        updateState { $0.isBackingUp = true }
        let config = state.webDAVConfig

        Task {
            do {
                let summary = try await backupUseCase.execute(config: config)
                self.updateState { state in
                    state.isBackingUp = false
                    state.lastBackupSummary = summary
                    state.successMessage = "云端备份成功！"
                }
                let msg = "已备份 \(summary.bookCount) 本书与 \(summary.sourceCount) 个书源 (\(summary.dataSizeBytes / 1024) KB)"
                self.emitEffect(.showToast(msg))
                self.emitEffect(.hapticFeedback)
            } catch {
                self.updateState { state in
                    state.isBackingUp = false
                    state.errorMessage = error.localizedDescription
                }
                self.emitEffect(.showToast("备份失败: \(error.localizedDescription)"))
            }
        }
    }

    private func runRestore() {
        guard state.webDAVConfig.isValid else {
            emitEffect(.showToast("请先配置并测试 WebDAV 连接"))
            return
        }

        updateState { $0.isRestoring = true }
        let config = state.webDAVConfig

        Task {
            do {
                let summary = try await restoreUseCase.execute(config: config)
                self.updateState { state in
                    state.isRestoring = false
                    state.successMessage = "云端还原成功！"
                }
                let msg = "已恢复 \(summary.bookCount) 本书与 \(summary.sourceCount) 个书源"
                self.emitEffect(.showToast(msg))
                self.emitEffect(.hapticFeedback)
            } catch {
                self.updateState { state in
                    state.isRestoring = false
                    state.errorMessage = error.localizedDescription
                }
                self.emitEffect(.showToast("还原失败: \(error.localizedDescription)"))
            }
        }
    }

    private func saveCurrentConfig() {
        if let data = try? JSONEncoder().encode(state.webDAVConfig) {
            UserDefaults.standard.set(data, forKey: SettingsViewModel.webDAVConfigKey)
        }
    }

    private static func loadSavedWebDAVConfig() -> WebDAVConfig {
        guard let data = UserDefaults.standard.data(forKey: webDAVConfigKey),
              let config = try? JSONDecoder().decode(WebDAVConfig.self, from: data) else {
            return WebDAVConfig(
                serverUrl: "https://dav.jianguoyun.com/dav/",
                remoteDirectory: "/Legado/")
        }
        return config
    }
}
