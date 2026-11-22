import Foundation

/// WebDAV 配置持久化读取器（严格区分“用户主动配置”与“仅预设占位”，避免未配置时在后台触发网络请求）
public enum WebDAVConfigStore {
    public static let storageKey = "legado_webdav_config"
    public static let defaultTemplateServerUrl = "https://dav.jianguoyun.com/dav/"

    /// 用于设置页编辑展示：若尚未保存配置，则返回坚果云模板供用户填写
    public static func loadForEditing(defaults: UserDefaults = .standard) -> WebDAVConfig {
        if let saved = loadRawSaved(defaults: defaults) {
            return saved
        }
        return WebDAVConfig(
            serverUrl: defaultTemplateServerUrl,
            remoteDirectory: "/Legado/")
    }

    /// 仅当用户确实配置了可用 WebDAV 账号或完整的自定义服务器时返回配置；否则返回 nil（防止未配置或输入中途静默请求）
    public static func loadSavedIfConfigured(defaults: UserDefaults = .standard) -> WebDAVConfig? {
        guard let saved = loadRawSaved(defaults: defaults), isEffectivelyConfigured(saved) else {
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
        if (url.absoluteString == normalizedTemplate || host.hasSuffix("jianguoyun.com")),
           !config.hasCredentials {
            return false
        }
        return true
    }

    public static func save(_ config: WebDAVConfig, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func loadRawSaved(defaults: UserDefaults) -> WebDAVConfig? {
        guard let data = defaults.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(WebDAVConfig.self, from: data) else {
            return nil
        }
        return config
    }
}
