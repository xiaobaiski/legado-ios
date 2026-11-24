import Foundation

/// 正文与标题净化替换规则领域模型（完全兼容 Legado Android `ReplaceRule` JSON 格式）
public struct ReplaceRule: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    /// 规则名称
    public var name: String
    /// 分组标签（可选，逗号分隔）
    public var group: String?
    /// 匹配模式（正则或纯文本）
    public var pattern: String
    /// 替换目标字符串（默认为空字符串，即移除匹配内容）
    public var replacement: String
    /// 作用范围（Legado 规范：逗号分隔书名或书源 URL；为空/nil 表示全局生效）
    public var scope: String?
    /// 是否作用于章节标题
    public var scopeTitle: Bool
    /// 是否作用于章节正文
    public var scopeContent: Bool
    /// 排除范围（逗号分隔书名或书源 URL）
    public var excludeScope: String?
    /// 是否启用
    public var isEnabled: Bool
    /// 是否使用正则表达式（false 表示纯文本替换）
    public var isRegex: Bool
    /// 是否区分大小写（仅扩展兼容，默认 false）
    public var isCaseSensitive: Bool
    /// 正则匹配超时毫秒数（兼容 Legado 字段，默认 3000）
    public var timeoutMillisecond: Int64
    /// 规则排序序号
    public var order: Int

    /// 兼容旧接口字段名（映射到 `scope`）
    public var scopeSourceUrl: String? {
        get { scope }
        set { scope = newValue }
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        group: String? = nil,
        pattern: String,
        replacement: String = "",
        scope: String? = nil,
        scopeTitle: Bool = false,
        scopeContent: Bool = true,
        excludeScope: String? = nil,
        isEnabled: Bool = true,
        isRegex: Bool = true,
        isCaseSensitive: Bool = false,
        timeoutMillisecond: Int64 = 3000,
        order: Int = 0) {
        self.id = id
        self.name = name
        self.group = group
        self.pattern = pattern
        self.replacement = replacement
        self.scope = scope
        self.scopeTitle = scopeTitle
        self.scopeContent = scopeContent
        self.excludeScope = excludeScope
        self.isEnabled = isEnabled
        self.isRegex = isRegex
        self.isCaseSensitive = isCaseSensitive
        self.timeoutMillisecond = timeoutMillisecond
        self.order = order
    }

    /// 兼容旧调用签名（`scopeSourceUrl:`）
    public init(
        id: String = UUID().uuidString,
        name: String,
        pattern: String,
        replacement: String = "",
        scopeSourceUrl: String?,
        isEnabled: Bool = true,
        isCaseSensitive: Bool = false) {
        self.init(
            id: id,
            name: name,
            pattern: pattern,
            replacement: replacement,
            scope: scopeSourceUrl,
            scopeTitle: false,
            scopeContent: true,
            excludeScope: nil,
            isEnabled: isEnabled,
            isRegex: true,
            isCaseSensitive: isCaseSensitive)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case group
        case pattern
        case replacement
        case scope
        case scopeSourceUrl
        case scopeTitle
        case scopeContent
        case excludeScope
        case isEnabled
        case isRegex
        case isCaseSensitive
        case timeoutMillisecond
        case order
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let strId = try? container.decode(String.self, forKey: .id), !strId.isEmpty {
            self.id = strId
        } else if let intId = try? container.decode(Int64.self, forKey: .id) {
            self.id = String(intId)
        } else {
            self.id = UUID().uuidString
        }
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.group = try container.decodeIfPresent(String.self, forKey: .group)
        self.pattern = try container.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        self.replacement = try container.decodeIfPresent(String.self, forKey: .replacement) ?? ""
        let decodedScope = try container.decodeIfPresent(String.self, forKey: .scope)
            ?? (try container.decodeIfPresent(String.self, forKey: .scopeSourceUrl))
        self.scope = decodedScope?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            ? nil
            : decodedScope
        self.scopeTitle = try container.decodeIfPresent(Bool.self, forKey: .scopeTitle) ?? false
        self.scopeContent = try container.decodeIfPresent(Bool.self, forKey: .scopeContent) ?? true
        let decodedExclude = try container.decodeIfPresent(String.self, forKey: .excludeScope)
        self.excludeScope = decodedExclude?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            ? nil
            : decodedExclude
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isRegex = try container.decodeIfPresent(Bool.self, forKey: .isRegex) ?? true
        self.isCaseSensitive = try container.decodeIfPresent(Bool.self, forKey: .isCaseSensitive) ?? false
        self.timeoutMillisecond = try container.decodeIfPresent(Int64.self, forKey: .timeoutMillisecond) ?? 3000
        self.order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let numericId = Int64(id) {
            try container.encode(numericId, forKey: .id)
        } else {
            try container.encode(id, forKey: .id)
        }
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(replacement, forKey: .replacement)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encode(scopeTitle, forKey: .scopeTitle)
        try container.encode(scopeContent, forKey: .scopeContent)
        try container.encodeIfPresent(excludeScope, forKey: .excludeScope)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isRegex, forKey: .isRegex)
        try container.encode(isCaseSensitive, forKey: .isCaseSensitive)
        try container.encode(timeoutMillisecond, forKey: .timeoutMillisecond)
        try container.encode(order, forKey: .order)
    }

    /// 校验规则合法性（与 Legado Android ReplaceRule.isValid() 对齐）
    public var isValid: Bool {
        guard !pattern.isEmpty, scopeContent || scopeTitle else { return false }
        if isRegex {
            if pattern.hasSuffix("|") && !pattern.hasSuffix("\\|") {
                return false
            }
            guard (try? NSRegularExpression(pattern: pattern)) != nil else {
                return false
            }
        }
        return true
    }

    /// 判断规则是否适用于指定书籍与书源
    public func matches(bookName: String?, sourceUrl: String?) -> Bool {
        if let exclude = excludeScope, !exclude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let excludeTokens = Self.splitScopeTokens(exclude)
            if Self.tokensMatch(excludeTokens, bookName: bookName, sourceUrl: sourceUrl) {
                return false
            }
        }
        guard let include = scope, !include.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        let includeTokens = Self.splitScopeTokens(include)
        return Self.tokensMatch(includeTokens, bookName: bookName, sourceUrl: sourceUrl)
    }

    private static let scopeSeparators = CharacterSet(charactersIn: ",，;\n")

    private static func splitScopeTokens(_ raw: String) -> [String] {
        raw.components(separatedBy: scopeSeparators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func tokensMatch(_ tokens: [String], bookName: String?, sourceUrl: String?) -> Bool {
        for token in tokens {
            if let bookName, !bookName.isEmpty,
               bookName == token || bookName.localizedCaseInsensitiveContains(token) {
                return true
            }
            if let sourceUrl, !sourceUrl.isEmpty,
               sourceUrl == token || sourceUrl.localizedCaseInsensitiveContains(token) {
                return true
            }
        }
        return false
    }
}
