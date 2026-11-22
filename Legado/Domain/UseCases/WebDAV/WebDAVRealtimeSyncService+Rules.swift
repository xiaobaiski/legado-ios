import Foundation

// MARK: - 规则与阅读排版配置双向实时同步（rules_sync.json）

extension WebDAVRealtimeSyncService {
    var localRulesUpdatedAt: Date {
        get {
            let raw = rulesTimestampDefaults.double(forKey: Self.rulesTimestampKey)
            return raw > 0 ? Date(timeIntervalSince1970: raw) : .distantPast
        }
        set {
            rulesTimestampDefaults.set(newValue.timeIntervalSince1970, forKey: Self.rulesTimestampKey)
        }
    }

    /// 安排防抖后的规则与排版配置实时上传（不会污染或覆盖云端 legado_backup.json 的书架进度）
    public func scheduleRulesPush(debounceSeconds: TimeInterval = 3.0) {
        guard let config = activeConfig(), config.syncOptions.realtimeSyncRules else { return }
        localRulesUpdatedAt = Date()
        hasPendingRulesPush = true

        rulesDebounceTask?.cancel()
        rulesDebounceTask = Task { [weak self] in
            if debounceSeconds > 0 {
                let nanos = UInt64(debounceSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
            guard let self, !Task.isCancelled else { return }
            self.startRulesDrainIfNeeded(useBackgroundTask: false)
        }
    }

    /// 退入后台时立即冲洗待同步的规则与排版变更
    public func flushPendingRulesPush() {
        rulesDebounceTask?.cancel()
        rulesDebounceTask = nil
        guard hasPendingRulesPush || activeRulesPushTask != nil else { return }
        guard let config = activeConfig(), config.syncOptions.realtimeSyncRules else { return }

        if activeRulesPushTask != nil {
            ensureRulesBackgroundTask()
            return
        }
        _ = config
        startRulesDrainIfNeeded(useBackgroundTask: true)
    }

    /// 从云端拉取最新的规则与排版配置并按时间戳覆盖本地（唤醒或书架刷新时按需触发）
    @discardableResult
    public func pullLatestRulesIfNeeded(force: Bool = false) async -> Bool {
        guard let config = activeConfig(), config.syncOptions.realtimeSyncRules else {
            return false
        }
        guard !hasPendingRulesPush, activeRulesPushTask == nil else {
            return false
        }
        if !force {
            guard Date().timeIntervalSince(lastRulesPullAt) >= globalPullCooldown else {
                return false
            }
        }

        beginSyncCycle()
        defer { endSyncCycle() }

        let remoteBundle: WebDAVRulesBundle?
        do {
            remoteBundle = try await fetchRemoteRulesBundleStrict(config: config)
        } catch {
            recordSyncFailure(error)
            return false
        }

        lastRulesPullAt = Date()
        guard let remote = remoteBundle else {
            clearSyncError()
            return false
        }

        guard remote.updatedAt.timeIntervalSince(localRulesUpdatedAt) > 0.5 else {
            clearSyncError()
            return false
        }

        applyRemoteRulesBundle(remote)
        localRulesUpdatedAt = remote.updatedAt
        recordSyncSuccess("已同步规则与排版配置")
        onRulesUpdated()
        return true
    }

    private func startRulesDrainIfNeeded(useBackgroundTask: Bool) {
        if useBackgroundTask {
            ensureRulesBackgroundTask()
        }
        guard activeRulesPushTask == nil else { return }

        activeRulesPushTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.activeRulesPushTask = nil
                self.activeRulesEndTask?()
                self.activeRulesEndTask = nil
            }
            await self.drainPendingRulesPush()
        }
    }

    private func ensureRulesBackgroundTask() {
        guard activeRulesEndTask == nil, let starter = backgroundTaskProvider else { return }
        activeRulesEndTask = starter { [weak self] in
            self?.activeRulesPushTask?.cancel()
        }
    }

    private func drainPendingRulesPush() async {
        beginSyncCycle()
        defer { endSyncCycle() }

        while !Task.isCancelled, hasPendingRulesPush {
            guard let config = activeConfig(), config.syncOptions.realtimeSyncRules else {
                hasPendingRulesPush = false
                return
            }

            hasPendingRulesPush = false
            let timestamp = localRulesUpdatedAt == .distantPast ? Date() : localRulesUpdatedAt
            let payload = WebDAVRulesBundle(
                updatedAt: timestamp,
                replaceRules: replaceRuleStore.loadRules(),
                txtTocRules: txtTocRuleStore.loadRules(),
                readerConfigJson: readerConfigExporter())

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(payload)
                try await webDAVClient.upload(
                    data: data,
                    filename: Self.rulesFileName,
                    config: config,
                    ensureDirectory: false)
                recordSyncSuccess("已上传规则与排版配置")
            } catch {
                hasPendingRulesPush = true
                recordSyncFailure(error)
                break
            }
        }
    }

    private func fetchRemoteRulesBundleStrict(config: WebDAVConfig) async throws -> WebDAVRulesBundle? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try await webDAVClient.download(filename: Self.rulesFileName, config: config)
            guard let bundle = try? decoder.decode(WebDAVRulesBundle.self, from: data) else {
                throw WebDAVError.serverError(statusCode: 500, message: "云端规则同步文件解析失败")
            }
            return bundle
        } catch WebDAVError.notFound {
            // 兼容尚未使用过规则实时同步、仅执行过手动备份的旧设备
        }

        do {
            let backupData = try await webDAVClient.download(filename: Self.fallbackBackupFileName, config: config)
            guard let backup = try? decoder.decode(WebDAVBackupBundle.self, from: backupData) else {
                throw WebDAVError.serverError(statusCode: 500, message: "云端备份文件解析失败")
            }
            return WebDAVRulesBundle(
                updatedAt: backup.backupTime,
                replaceRules: backup.replaceRules,
                txtTocRules: backup.txtTocRules ?? [],
                readerConfigJson: backup.readerConfigJson)
        } catch WebDAVError.notFound {
            return nil
        }
    }

    private func applyRemoteRulesBundle(_ remote: WebDAVRulesBundle) {
        if !remote.replaceRules.isEmpty {
            replaceRuleStore.saveRules(remote.replaceRules)
        }
        if !remote.txtTocRules.isEmpty {
            txtTocRuleStore.saveRules(remote.txtTocRules)
        }
        if let configJson = remote.readerConfigJson, !configJson.isEmpty {
            readerConfigImporter(configJson)
        }
    }
}
