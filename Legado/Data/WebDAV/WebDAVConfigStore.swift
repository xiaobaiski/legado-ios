import Foundation

/// WebDAV 配置持久化读取器（严格区分“用户主动配置”与“仅预设占位”，避免未配置时在后台触发网络请求）
public enum WebDAVConfigStore {
    public static let storageKey = "legado_webdav_config"
    public static let defaultTemplateServerUrl = "https://dav.jianguoyun.com/dav/"
    private static let passwordAccount = "webdav_primary_password"

    /// 用于设置页编辑展示：若尚未保存配置，则返回坚果云模板供用户填写
    public static func loadForEditing(
        defaults: UserDefaults = .standard,
        secretStore: WebDAVSecretStore? = nil) -> WebDAVConfig {
        let resolvedStore = resolveSecretStore(secretStore, defaults: defaults)
        if let saved = loadRawSaved(defaults: defaults, secretStore: resolvedStore) {
            return saved
        }
        return WebDAVConfig(
            serverUrl: defaultTemplateServerUrl,
            remoteDirectory: "/Legado/")
    }

    /// 仅当用户确实配置了可用 WebDAV 账号或完整的自定义服务器时返回配置；否则返回 nil（防止未配置或输入中途静默请求）
    public static func loadSavedIfConfigured(
        defaults: UserDefaults = .standard,
        secretStore: WebDAVSecretStore? = nil) -> WebDAVConfig? {
        let resolvedStore = resolveSecretStore(secretStore, defaults: defaults)
        guard let saved = loadRawSaved(defaults: defaults, secretStore: resolvedStore),
              isEffectivelyConfigured(saved) else {
            return nil
        }
        return saved
    }

    /// 校验配置是否已满足自动后台同步前置条件（过滤未填写认证的默认坚果云模板与输入中的不完整主机名）
    public static func isEffectivelyConfigured(_ config: WebDAVConfig) -> Bool {
        guard config.isValid, let url = WebDAVClient.normalizeBaseUrl(config.serverUrl) else {
            return false
        }
        let host = url.host?.lowercased() ?? ""
        let isValidHostFormat = host.contains(".") || host == "localhost" || host.contains(":")
        guard isValidHostFormat else {
            return false
        }
        let normalizedTemplate = WebDAVClient.normalizeBaseUrl(defaultTemplateServerUrl)?.absoluteString
        let isJianguoyun = url.absoluteString == normalizedTemplate || host.hasSuffix("jianguoyun.com")
        if isJianguoyun, !config.hasCredentials {
            return false
        }
        return true
    }

    public static func save(
        _ config: WebDAVConfig,
        defaults: UserDefaults = .standard,
        secretStore: WebDAVSecretStore? = nil) {
        let resolvedStore = resolveSecretStore(secretStore, defaults: defaults)
        var configToPersist = config
        if let resolvedStore {
            if config.password.isEmpty {
                resolvedStore.deletePassword(account: passwordAccount)
            } else if resolvedStore.savePassword(config.password, account: passwordAccount) {
                configToPersist.password = ""
            }
        }
        if let data = try? JSONEncoder().encode(configToPersist) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func resolveSecretStore(
        _ explicit: WebDAVSecretStore?,
        defaults: UserDefaults) -> WebDAVSecretStore? {
        if let explicit {
            return explicit
        }
        return defaults === UserDefaults.standard ? WebDAVKeychainStore.shared : nil
    }

    private static func loadRawSaved(
        defaults: UserDefaults,
        secretStore: WebDAVSecretStore?) -> WebDAVConfig? {
        guard let data = defaults.data(forKey: storageKey),
              var config = try? JSONDecoder().decode(WebDAVConfig.self, from: data) else {
            return nil
        }
        if let secretStore {
            if !config.password.isEmpty {
                // 兼容迁移旧版 UserDefaults 中的明文密码至 Keychain 并立即擦除明文
                if secretStore.savePassword(config.password, account: passwordAccount) {
                    var scrubbed = config
                    scrubbed.password = ""
                    if let scrubbedData = try? JSONEncoder().encode(scrubbed) {
                        defaults.set(scrubbedData, forKey: storageKey)
                    }
                }
            } else if let keychainPassword = secretStore.loadPassword(account: passwordAccount),
                      !keychainPassword.isEmpty {
                config.password = keychainPassword
            }
        }
        return config
    }
}
