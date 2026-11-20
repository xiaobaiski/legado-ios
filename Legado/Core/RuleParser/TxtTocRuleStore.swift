import Foundation

/// 本地 TXT 目录分章规则持久化管理器（兼容 Legado Android `txtTocRule.json` 导入导出）
public final class TxtTocRuleStore: @unchecked Sendable {
    public static let shared = TxtTocRuleStore()

    private let storageUrl: URL
    private let lock = NSLock()
    private var cachedRules: [TxtTocRule]?

    public init(storageUrl: URL? = nil) {
        if let storageUrl {
            self.storageUrl = storageUrl
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let rulesDir = docs.appendingPathComponent("Rules", isDirectory: true)
            try? FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
            self.storageUrl = rulesDir.appendingPathComponent("txt_toc_rules.json")
        }
    }

    public func loadRules() -> [TxtTocRule] {
        lock.lock()
        defer { lock.unlock() }

        if let cachedRules {
            return cachedRules
        }

        let loaded: [TxtTocRule]
        if FileManager.default.fileExists(atPath: storageUrl.path),
           let data = try? Data(contentsOf: storageUrl),
           let rules = try? JSONDecoder().decode([TxtTocRule].self, from: data),
           !rules.isEmpty {
            loaded = rules.sorted { $0.serialNumber < $1.serialNumber }
        } else {
            loaded = TxtTocRule.defaultRules
        }
        cachedRules = loaded
        return loaded
    }

    public func enabledRules() -> [TxtTocRule] {
        loadRules().filter { $0.enable && $0.isValid }
    }

    public func saveRules(_ rules: [TxtTocRule]) {
        lock.lock()
        defer { lock.unlock() }

        let sorted = rules.sorted { $0.serialNumber < $1.serialNumber }
        cachedRules = sorted.isEmpty ? nil : sorted

        let parent = storageUrl.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(sorted) {
            try? data.write(to: storageUrl, options: .atomic)
        }
    }

    public func upsert(_ rule: TxtTocRule) -> [TxtTocRule] {
        var rules = loadRules()
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        } else {
            var next = rule
            next.serialNumber = (rules.map(\.serialNumber).max() ?? -1) + 1
            rules.append(next)
        }
        saveRules(rules)
        return rules
    }

    public func delete(id: Int64) -> [TxtTocRule] {
        var rules = loadRules()
        rules.removeAll { $0.id == id }
        saveRules(rules)
        return rules
    }

    public func toggleEnabled(id: Int64) -> [TxtTocRule] {
        var rules = loadRules()
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].enable.toggle()
            saveRules(rules)
        }
        return rules
    }

    @discardableResult
    public func resetToDefaults() -> [TxtTocRule] {
        let defaults = TxtTocRule.defaultRules
        saveRules(defaults)
        return defaults
    }

    /// 导入标准 Legado Android `txtTocRule.json`（支持数组或单条对象）
    public func importLegadoJSON(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let incoming: [TxtTocRule]
        if let array = try? decoder.decode([TxtTocRule].self, from: data) {
            incoming = array
        } else if let single = try? decoder.decode(TxtTocRule.self, from: data) {
            incoming = [single]
        } else {
            throw NSError(
                domain: "TxtTocRuleStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法解析 TXT 目录规则 JSON，请确认为 Legado 标准格式"])
        }

        let validIncoming = incoming.filter { !$0.rule.isEmpty }
        guard !validIncoming.isEmpty else { return 0 }

        var existing = loadRules()
        var count = 0
        for item in validIncoming {
            if let idx = existing.firstIndex(where: { $0.id == item.id || $0.name == item.name }) {
                existing[idx] = item
            } else {
                existing.append(item)
            }
            count += 1
        }
        saveRules(existing)
        return count
    }

    public func exportLegadoJSON() -> String {
        let rules = loadRules()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(rules),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}
