import Foundation

// MARK: - 阅读器排版配置持久化与自动翻页扩展

extension ReaderViewModel {
    func handleExtendedConfigIntent(_ intent: ReaderIntent) {
        switch intent {
        case let .updateConfig(newConfig):
            applyNewConfig(newConfig)

        case .resetConfig:
            let defaults = ReaderConfigStore.reset()
            applyNewConfig(defaults)
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
            break
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
            emitEffect(.showToast("已开启自动翻页（每 \(Int(state.config.autoPageIntervalSeconds)) 秒）"))
        }
        emitHapticIfEnabled()
    }

    func restartAutoPageTimer() {
        autoPageTask?.cancel()
        autoPageTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = max(self.state.config.autoPageIntervalSeconds, 3.0)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, self.state.isAutoPaging else { return }
                if self.state.isHUDVisible || self.state.isMoreSettingsVisible || self.state.isTocSheetVisible {
                    continue
                }
                let isLastPageOfBook = self.state.currentChapterIndex + 1 >= self.state.chapters.count &&
                    self.state.currentPageIndex + 1 >= self.state.pages.count
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
}
