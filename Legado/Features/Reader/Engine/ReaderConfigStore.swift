import Foundation

/// 阅读配置本地持久化存储 (UserDefaults + 内存热缓存，消除高频触感/排版读取的重复 JSON 反序列化)
public enum ReaderConfigStore {
    public static let storageKey = "legado_reader_config_v1"
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cachedStandardConfig: ReaderConfig?

    public static func load(defaults: UserDefaults = .standard) -> ReaderConfig {
        let isStandard = defaults === UserDefaults.standard
        if isStandard {
            cacheLock.lock()
            if let cached = cachedStandardConfig {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()
        }

        let decoded: ReaderConfig
        if let data = defaults.data(forKey: storageKey),
           let config = try? JSONDecoder().decode(ReaderConfig.self, from: data) {
            decoded = config
        } else {
            decoded = .defaultConfig
        }

        if isStandard {
            cacheLock.lock()
            cachedStandardConfig = decoded
            cacheLock.unlock()
        }
        return decoded
    }

    public static func save(_ config: ReaderConfig, defaults: UserDefaults = .standard) {
        if defaults === UserDefaults.standard {
            cacheLock.lock()
            cachedStandardConfig = config
            cacheLock.unlock()
        }
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: storageKey)
        }
    }

    @discardableResult
    public static func reset(defaults: UserDefaults = .standard) -> ReaderConfig {
        if defaults === UserDefaults.standard {
            cacheLock.lock()
            cachedStandardConfig = .defaultConfig
            cacheLock.unlock()
        }
        defaults.removeObject(forKey: storageKey)
        return .defaultConfig
    }

    /// 全局震动开关快捷读取（直接命中内存缓存，零磁盘/JSON 开销）
    public static var isHapticEnabled: Bool {
        load().isHapticEnabled
    }
}
