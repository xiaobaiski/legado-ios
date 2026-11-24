import Foundation

// MARK: - 阅读器排版配置持久化与自动翻页扩展

extension ReaderViewModel {
    func handleExtendedConfigIntent(_ intent: ReaderIntent) {
        switch intent {
        case let .updateConfig(newConfig):
            let prevMode = state.config.autoPageMode
            let oldConfig = state.config
            let isDiscreteToggle = oldConfig.theme != newConfig.theme
                || oldConfig.pageTurnMode != newConfig.pageTurnMode
                || oldConfig.fontWeight != newConfig.fontWeight
                || oldConfig.paragraphIndent != newConfig.paragraphIndent
                || oldConfig.isTextJustified != newConfig.isTextJustified
                || oldConfig.followSystemBrightness != newConfig.followSystemBrightness
                || oldConfig.isHapticEnabled != newConfig.isHapticEnabled
            applyNewConfig(newConfig, triggerHaptic: isDiscreteToggle)
            if state.isAutoPaging && prevMode != newConfig.autoPageMode {
                restartAutoPageTimer()
            }

        case .resetConfig:
            let defaults = ReaderConfigStore.reset()
            applyNewConfig(defaults, triggerHaptic: true)
            emitEffect(.showToast("已恢复默认阅读排版"))

        case .openMoreSettings:
            updateState {
                $0.isHUDVisible = false
                $0.isConfigSheetVisible = false
                $0.isMoreSettingsVisible = true
            }
            emitHapticIfEnabled()

        case .closeMoreSettings:
            updateState { $0.isMoreSettingsVisible = false }

        case .toggleAutoPage:
            toggleAutoPageMode()

        case let .setAutoPageInterval(seconds):
            let clamped = min(max(seconds, 3.0), 30.0)
            var updated = state.config
            updated.autoPageIntervalSeconds = clamped
            applyNewConfig(updated, triggerHaptic: false)
            if state.isAutoPaging {
                restartAutoPageTimer()
            }

        default:
            handleFontIntent(intent)
        }
    }

    private func handleFontIntent(_ intent: ReaderIntent) {
        switch intent {
        case let .importFonts(urls):
            handleImportFonts(urls: urls)

        case let .selectCustomFont(font):
            var updated = state.config
            updated.customFontName = font.postScriptName
            updated.customFontDisplayName = font.displayName
            applyNewConfig(updated, triggerHaptic: true)

        case let .deleteImportedFont(font):
            handleDeleteImportedFont(font)

        case .refreshImportedFonts:
            let fonts = LocalFontManager.shared.listImportedFonts()
            updateState { $0.importedFonts = fonts }

        case .repaginate:
            repaginateCurrentChapter()

        default:
            break
        }
    }

    func handleImportFonts(urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                var imported: [ImportedFont] = []
                var lastError: Error?
                for url in urls {
                    do {
                        let fonts = try LocalFontManager.shared.importFonts(from: url)
                        imported.append(contentsOf: fonts)
                    } catch {
                        lastError = error
                    }
                }
                let allFonts = LocalFontManager.shared.listImportedFonts()
                return (imported, allFonts, lastError)
            }.value

            guard let self else { return }
            self.updateState { $0.importedFonts = result.1 }

            if let first = result.0.first {
                var updated = self.state.config
                updated.customFontName = first.postScriptName
                updated.customFontDisplayName = first.displayName
                self.applyNewConfig(updated, triggerHaptic: true)
                let msg = result.0.count == 1
                    ? "已导入并应用字体「\(first.displayName)」"
                    : "成功导入 \(result.0.count) 款本地字体"
                self.emitEffect(.showToast(msg))
            } else if let lastError = result.2 {
                self.emitEffect(.showToast("字体导入失败: \(lastError.localizedDescription)"))
            }
        }
    }

    func handleDeleteImportedFont(_ font: ImportedFont) {
        do {
            let removedNames = try LocalFontManager.shared.deleteFont(font)
            let updatedFonts = LocalFontManager.shared.listImportedFonts()
            updateState { $0.importedFonts = updatedFonts }
            if let active = state.config.customFontName, removedNames.contains(active) {
                var updated = state.config
                updated.customFontName = nil
                updated.customFontDisplayName = nil
                applyNewConfig(updated, triggerHaptic: true)
            }
            emitEffect(.showToast("已删除字体「\(font.displayName)」"))
            emitHapticIfEnabled()
        } catch {
            emitEffect(.showToast("删除字体失败: \(error.localizedDescription)"))
        }
    }

    func toggleAutoPageMode() {
        if state.isAutoPaging {
            stopAutoPageTimer()
            emitEffect(.showToast("已停止自动翻页"))
        } else {
            updateState {
                $0.isAutoPaging = true
                $0.isHUDVisible = false
                $0.isConfigSheetVisible = false
                $0.isMoreSettingsVisible = false
            }
            restartAutoPageTimer()
            let usesSmoothScroll = state.config.autoPageMode == .smoothScroll
                || state.config.pageTurnMode == .scroll
            let msg = usesSmoothScroll
                ? "已开启上下滚动自动翻页（速度 \(Int(state.config.autoScrollSpeed))）"
                : "已开启定时自动翻页（每 \(Int(state.config.autoPageIntervalSeconds)) 秒）"
            emitEffect(.showToast(msg))
        }
        emitHapticIfEnabled()
    }

    func restartAutoPageTimer() {
        autoPageTask?.cancel()
        autoPageTask = nil
        // 上下滚动模式由 AutoScrollReaderView 内部 CADisplayLink 60/120Hz 驱动，无需定时翻页任务
        if state.config.autoPageMode == .smoothScroll || state.config.pageTurnMode == .scroll {
            return
        }
        autoPageTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = max(self.state.config.autoPageIntervalSeconds, 3.0)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, self.state.isAutoPaging else { return }
                if self.state.isHUDVisible || self.state.isMoreSettingsVisible || self.state.isTocSheetVisible {
                    continue
                }
                let step = self.state.config.isDualPageActive(for: self.state.screenBounds) ? 2 : 1
                let aligned = step == 2
                    ? (self.state.currentPageIndex - self.state.currentPageIndex % 2)
                    : self.state.currentPageIndex
                let isLastPageOfBook = self.state.currentChapterIndex + 1 >= self.state.chapters.count &&
                    aligned + step >= self.state.pages.count
                if isLastPageOfBook {
                    self.stopAutoPageTimer()
                    self.emitEffect(.showToast("已自动阅读至全书末尾"))
                    return
                }
                self.send(.nextPage)
            }
        }
    }

    func stopAutoPageTimer() {
        autoPageTask?.cancel()
        autoPageTask = nil
        if state.isAutoPaging {
            updateState { $0.isAutoPaging = false }
        }
    }

    func handleAppDidBecomeActive() {
        startRealtimeProgressPull(for: state.book)
    }

    func notifyRulesChanged() {
        realtimeSyncService?.noteLocalRulesModified()
        realtimeSyncService?.scheduleRulesPush()
        repaginateCurrentChapter()
    }

    func reloadExternalReaderConfig() {
        let latest = ReaderConfigStore.load()
        if latest != state.config {
            updateState { $0.config = latest }
        }
        repaginateCurrentChapter()
    }
}
