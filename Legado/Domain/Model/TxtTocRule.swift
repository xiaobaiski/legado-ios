import Foundation

/// 本地 TXT 目录分章正则规则（完全兼容 Legado Android `txtTocRule.json` 格式）
public struct TxtTocRule: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64
    public var name: String
    public var rule: String
    public var example: String?
    public var serialNumber: Int
    public var enable: Bool

    public init(
        id: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        name: String,
        rule: String,
        example: String? = nil,
        serialNumber: Int = 0,
        enable: Bool = true) {
        self.id = id
        self.name = name
        self.rule = rule
        self.example = example
        self.serialNumber = serialNumber
        self.enable = enable
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case rule
        case example
        case serialNumber
        case enable
        case isEnabled
    }

    private static let fallbackIdLock = NSLock()
    private nonisolated(unsafe) static var lastFallbackId: Int64 = 0

    private static func nextFallbackId() -> Int64 {
        fallbackIdLock.lock()
        defer { fallbackIdLock.unlock() }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let next = max(nowMs, lastFallbackId + 1)
        lastFallbackId = next
        return next
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int64.self, forKey: .id) {
            self.id = intId
        } else if let strId = try? container.decode(String.self, forKey: .id), let parsed = Int64(strId) {
            self.id = parsed
        } else {
            self.id = Self.nextFallbackId()
        }
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.rule = try container.decodeIfPresent(String.self, forKey: .rule) ?? ""
        self.example = try container.decodeIfPresent(String.self, forKey: .example)
        self.serialNumber = try container.decodeIfPresent(Int.self, forKey: .serialNumber) ?? 0
        self.enable = try container.decodeIfPresent(Bool.self, forKey: .enable)
            ?? (try container.decodeIfPresent(Bool.self, forKey: .isEnabled))
            ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(rule, forKey: .rule)
        try container.encodeIfPresent(example, forKey: .example)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encode(enable, forKey: .enable)
    }

    public var isValid: Bool {
        guard !rule.isEmpty else { return false }
        return (try? NSRegularExpression(pattern: rule, options: [.anchorsMatchLines])) != nil
    }

    /// 内置官方 Legado Android 默认 TXT 目录规则集（同步自 LegadoTeam/legado `txtTocRule.json`）
    public static let defaultRules: [TxtTocRule] = [
        TxtTocRule(
            id: -1,
            name: "目录(标准章节/卷/回)",
            rule: "^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|" +
                "第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}" +
                "(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|话|篇(?!张))).{0,36}$",
            example: "第一章 标准的章节标题",
            serialNumber: 0,
            enable: true),
        TxtTocRule(
            id: -2,
            name: "目录(含前言/简介)",
            rule: "^[ 　\\t]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|" +
                "第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}" +
                "(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|篇(?!张))).{0,36}$",
            example: "简介 / 第一章 宿命之始",
            serialNumber: 1,
            enable: false),
        TxtTocRule(
            id: -8,
            name: "数字 分隔符 标题名称",
            rule: "^[ 　\\t]{0,4}\\d{1,5}[:：,.， 、_—\\-].{1,30}$",
            example: "1、章节标题 / 001. 序幕",
            serialNumber: 2,
            enable: true),
        TxtTocRule(
            id: -9,
            name: "大写数字 分隔符 标题名称",
            rule: "^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|" +
                "[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?)[ 、_—\\-].{1,30}$",
            example: "一、初入江湖 / 二十四章 风起",
            serialNumber: 3,
            enable: true),
        TxtTocRule(
            id: -11,
            name: "正文 标题/序号",
            rule: "^[ 　\\t]{0,4}正文[ 　]{1,4}.{0,24}$",
            example: "正文 第一回 风云再起",
            serialNumber: 4,
            enable: true),
        TxtTocRule(
            id: -12,
            name: "Chapter / Section / Part 英文序号",
            rule: "^[ 　\\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO][.、]|[Ee]pisode|" +
                "(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\\s{0,4}\\d{1,4}.{0,30}$",
            example: "Chapter 1 The Beginning",
            serialNumber: 5,
            enable: true),
        TxtTocRule(
            id: -14,
            name: "特殊符号 序号 标题",
            rule: "^[ 　\\t]{0,4}[【〔〖「『〈［\\[](?:第|[Cc]hapter)" +
                "[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,24}$",
            example: "【第一章】初露锋芒",
            serialNumber: 6,
            enable: true),
        TxtTocRule(
            id: -16,
            name: "特殊符号 标题(星标)",
            rule: "^[ 　\\t]{0,4}(?:[☆★✦✧].{1,30}|序章|楔子|终章|后记|尾声|番外)[ 　]{0,4}$",
            example: "☆、晋江格式章节标题",
            serialNumber: 7,
            enable: true),
        TxtTocRule(
            id: -17,
            name: "章/卷 序号 标题",
            rule: "^[ \\t　]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|" +
                "[卷章][\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 　]{0,4}.{0,30}$",
            example: "卷五 开源盛世",
            serialNumber: 8,
            enable: true),
        TxtTocRule(
            id: -21,
            name: "书名 括号 序号",
            rule: "^[一-龥]{1,20}[ 　\\t]{0,4}[(（][\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ 　\\t]{0,4}$",
            example: "标题名称(12)",
            serialNumber: 9,
            enable: true),
        TxtTocRule(
            id: -22,
            name: "书名 序号",
            rule: "^[一-龥]{1,20}[ 　\\t]{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[ 　\\t]{0,4}$",
            example: "标题名称 124",
            serialNumber: 10,
            enable: true),
        TxtTocRule(
            id: -24,
            name: "字数分割 分节阅读",
            rule: "^[ 　\\t]{0,4}(?:.{0,15}分[页节章段]阅读[-_ ]|" +
                "第\\s{0,4}[\\d零一二两三四五六七八九十百千万]{1,6}\\s{0,4}[页节]).{0,30}$",
            example: "分节阅读 1 / 第一页",
            serialNumber: 11,
            enable: true),
        TxtTocRule(
            id: -5,
            name: "纯数字标题(备用)",
            rule: "^[ 　\\t]{0,4}\\d{1,5}\\.?[ 　\\t]{0,4}$",
            example: "12",
            serialNumber: 12,
            enable: false),
        TxtTocRule(
            id: -25,
            name: "激进通用规则(备用)",
            rule: "^.{0,6}(?:[引楔]子|正文(?!完|结)|[引序前]言|[序终]章|扉页|[上中下][部篇卷]|卷首语|后记|尾声|番外|={2,4}|" +
                "第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}" +
                "(?:章|节(?!课)|卷|页[、 　]|集(?![合和])|部(?![分是门落])|篇(?!张))).{0,40}$",
            example: "适配非常规格式章节",
            serialNumber: 13,
            enable: false),
    ]
}
