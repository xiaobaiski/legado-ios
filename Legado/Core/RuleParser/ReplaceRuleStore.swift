import Foundation

/// 正文与标题替换净化规则持久化管理器（兼容 Legado Android `replaceRule.json` 导入导出）
public final class ReplaceRuleStore: @unchecked Sendable {
    public static let shared = ReplaceRuleStore()

    private let storageUrl: URL
    private let lock = NSLock()

    public init(storageUrl: URL? = nil) {
        if let storageUrl {
            self.storageUrl = storageUrl
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let rulesDir = docs.appendingPathComponent("Rules", isDirectory: true)
            try? FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
            self.storageUrl = rulesDir.appendingPathComponent("replace_rules.json")
        }
    }

    public func loadRules() -> [ReplaceRule] {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: storageUrl.path),
              let data = try? Data(contentsOf: storageUrl),
              let rules = try? JSONDecoder().decode([ReplaceRule].self, from: data) else {
            return PurifyContentUseCase.defaultRules
        }
        return rules.sorted { $0.order < $1.order }
    }

    public func saveRules(_ rules: [ReplaceRule]) {
        lock.lock()
        defer { lock.unlock() }

        let parent = storageUrl.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(rules) {
            try? data.write(to: storageUrl, options: .atomic)
        }
    }

    public func upsert(_ rule: ReplaceRule) -> [ReplaceRule] {
        var rules = loadRules()
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        } else {
            var next = rule
            next.order = (rules.map(\.order).max() ?? -1) + 1
            rules.append(next)
        }
        saveRules(rules)
        return rules
    }

    public func delete(id: String) -> [ReplaceRule] {
        var rules = loadRules()
        rules.removeAll { $0.id == id }
        saveRules(rules)
        return rules
    }

    public func toggleEnabled(id: String) -> [ReplaceRule] {
        var rules = loadRules()
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].isEnabled.toggle()
            saveRules(rules)
        }
        return rules
    }

    @discardableResult
    public func resetToDefaults() -> [ReplaceRule] {
        let defaults = PurifyContentUseCase.defaultRules
        saveRules(defaults)
        return defaults
    }

    /// 导入标准 Legado Android 替换净化规则 JSON（支持数组或单条对象）
    public func importLegadoJSON(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let incoming: [ReplaceRule]
        if let array = try? decoder.decode([ReplaceRule].self, from: data) {
            incoming = array
        } else if let single = try? decoder.decode(ReplaceRule.self, from: data) {
            incoming = [single]
        } else {
            throw NSError(
                domain: "ReplaceRuleStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法解析替换规则 JSON，请确认为 Legado 标准格式"])
        }

        let validIncoming = incoming.filter { !$0.pattern.isEmpty }
        guard !validIncoming.isEmpty else { return 0 }

        var existing = loadRules()
        var addedOrUpdated = 0
        for item in validIncoming {
            if let idx = existing.firstIndex(where: {
                $0.id == item.id || ($0.name == item.name && $0.pattern == item.pattern)
            }) {
                existing[idx] = item
            } else {
                existing.append(item)
            }
            addedOrUpdated += 1
        }
        saveRules(existing)
        return addedOrUpdated
    }

    /// 导出标准 Legado Android 兼容 JSON 字符串
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
