import Foundation

/// 正文净化、重复标题去除、智能分段与替换规则引擎（对标 Legado Android `ContentProcessor` + `ContentHelp`）
public final class PurifyContentUseCase: @unchecked Sendable {
    public static let shared = PurifyContentUseCase()
    private let regexCache: NSCache<NSString, NSRegularExpression> = {
        let cache = NSCache<NSString, NSRegularExpression>()
        cache.countLimit = 128
        return cache
    }()

    /// 默认全局广告、防盗水印与排版清理规则（兼容 Legado ReplaceRule）
    public static let defaultRules: [ReplaceRule] = [
        ReplaceRule(
            id: "builtin-page-prompt",
            name: "过滤换页提示",
            group: "内置净化",
            pattern: "(本章未完|请点击下一[页章]继续阅读|未完待续|点击下一[页章]|第[0-9]+页/共[0-9]+页)",
            replacement: "",
            scopeTitle: false,
            scopeContent: true,
            isEnabled: true,
            isRegex: true,
            order: 0),
        ReplaceRule(
            id: "builtin-promo-url",
            name: "过滤广告推广网址",
            group: "内置净化",
            pattern: "((https?://)?([a-zA-Z0-9-]+\\.)+[a-zA-Z]{2,}(/[a-zA-Z0-9#?&._-]*)?)",
            replacement: "",
            scopeTitle: false,
            scopeContent: true,
            isEnabled: true,
            isRegex: true,
            order: 1),
        ReplaceRule(
            id: "builtin-watermark",
            name: "过滤阅读APP水印与防盗提示",
            group: "内置净化",
            pattern: "(笔趣阁.*?最快更新|首发.*?最新章节|最新最快更新|天才一秒记住|手机用户请浏览|请牢记.*?网址|请牢记本站|收藏本站|笔趣阁提醒您|求推荐票|求月票|请记住本书首发域名.*)",
            replacement: "",
            scopeTitle: false,
            scopeContent: true,
            isEnabled: true,
            isRegex: true,
            order: 2),
        ReplaceRule(
            id: "builtin-invisible-chars",
            name: "清理零宽与异常控制字符",
            group: "内置净化",
            pattern: "[\\u200B-\\u200F\\uFEFF\\u00AD]",
            replacement: "",
            scopeTitle: true,
            scopeContent: true,
            isEnabled: true,
            isRegex: true,
            order: 3),
    ]

    public init() {}

    /// 兼容旧版执行接口（默认规则 + 自定义规则）
    public func execute(
        content: String,
        sourceUrl: String? = nil,
        customRules: [ReplaceRule] = []) -> String {
        applyRules(
            to: content,
            rules: Self.defaultRules + customRules,
            isTitle: false,
            bookName: nil,
            sourceUrl: sourceUrl)
    }

    /// 净化章节标题（应用所有启用且作用于标题的替换规则）
    public func purifyTitle(
        _ title: String,
        bookName: String? = nil,
        sourceUrl: String? = nil,
        rules: [ReplaceRule]? = nil,
        enableReplace: Bool = true) -> String {
        guard enableReplace, !title.isEmpty else { return title }
        let activeRules = rules ?? ReplaceRuleStore.shared.loadRules()
        let cleaned = applyRules(
            to: title,
            rules: activeRules,
            isTitle: true,
            bookName: bookName,
            sourceUrl: sourceUrl)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? title : cleaned
    }

    /// 完整正文净化流水线（去重标题 -> 智能重分段 -> 替换净化规则）
    public func processContent(
        _ content: String,
        bookName: String? = nil,
        chapterTitle: String? = nil,
        sourceUrl: String? = nil,
        rules: [ReplaceRule]? = nil,
        enableReplace: Bool = true,
        removeSameTitle: Bool = true,
        reSegment: Bool = false) -> String {
        var result = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if removeSameTitle, let chapterTitle, !chapterTitle.isEmpty {
            result = stripDuplicateTitleLine(
                from: result,
                bookName: bookName ?? "",
                chapterTitle: chapterTitle)
        }

        if reSegment {
            result = smartReSegment(result, chapterTitle: chapterTitle ?? "")
        }

        if enableReplace {
            let activeRules = rules ?? ReplaceRuleStore.shared.loadRules()
            result = applyRules(
                to: result,
                rules: activeRules,
                isTitle: false,
                bookName: bookName,
                sourceUrl: sourceUrl)
        }

        return result
    }

    /// 去除正文首行与章节标题重复的行（对标 Legado Android `sameTitleLineMatcher`）
    public func stripDuplicateTitleLine(
        from content: String,
        bookName: String,
        chapterTitle: String) -> String {
        let titleParts = chapterTitle
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !titleParts.isEmpty else { return content }

        let escapedTitle = titleParts
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "\\s*")
        let prefixGroup = bookName.isEmpty
            ? "[\\s\\p{P}]*"
            : "(?:[\\s\\p{P}]|\(NSRegularExpression.escapedPattern(for: bookName)))*"
        let pattern = "^\(prefixGroup)\(escapedTitle)[\\t\\p{Zs}]*(?:\\n\\s*|$)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return content
        }
        let fullRange = NSRange(location: 0, length: (content as NSString).length)
        if let match = regex.firstMatch(in: content, options: [], range: fullRange),
           match.range.location == 0 {
            return (content as NSString).substring(from: match.range.length)
        }
        return content
    }

    /// 智能段落重排（对标 Legado Android `ContentHelp.reSegment`：黏合误断行 + 规范对话引号分段）
    public func smartReSegment(_ content: String, chapterTitle: String) -> String {
        let sentenceEnders = CharacterSet(charactersIn: "。？！?!~…")
        let closingQuotes = CharacterSet(charactersIn: "”\"』」’")

        var normalized = content
            .replacingOccurrences(of: "&quot;", with: "“")
            .replacingOccurrences(of: "[:：]['\"‘”“]+", with: "：“", options: .regularExpression)
            .replacingOccurrences(of: "[\"”“]+\\s*[\"”“][\\s\"”“]*", with: "”\n“", options: .regularExpression)

        let rawLines = normalized.components(separatedBy: .newlines)
        var mergedLines: [String] = []
        var buffer = ""

        for rawLine in rawLines {
            let cleaned = rawLine
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\u{3000}\u{00A0}"))
            guard !cleaned.isEmpty else { continue }
            if mergedLines.isEmpty && buffer.isEmpty && cleaned == chapterTitle.trimmingCharacters(in: .whitespaces) {
                continue
            }

            if buffer.isEmpty {
                buffer = cleaned
            } else {
                let endsParagraph = Self.lineEndsSentence(
                    buffer,
                    sentenceEnders: sentenceEnders,
                    closingQuotes: closingQuotes)
                if endsParagraph {
                    mergedLines.append(buffer)
                    buffer = cleaned
                } else {
                    buffer += cleaned
                }
            }
        }
        if !buffer.isEmpty {
            mergedLines.append(buffer)
        }

        normalized = mergedLines.joined(separator: "\n")
            .replacingOccurrences(
                of: "[\"”“]+(？|。|！|\\?|!|~)[\"”“]+",
                with: "”$1\n“",
                options: .regularExpression)
            .replacingOccurrences(
                of: "[\"”“]+(？|。|！|\\?|!|~)([^\"”“\\n])",
                with: "”$1\n$2",
                options: .regularExpression)
            .replacingOccurrences(of: "([问说喊唱叫骂道着答])[。\\.]", with: "$1。\n", options: .regularExpression)
            .replacingOccurrences(of: "[:：][”“\"\\s]+", with: "：“", options: .regularExpression)
            .replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lineEndsSentence(
        _ line: String,
        sentenceEnders: CharacterSet,
        closingQuotes: CharacterSet) -> Bool {
        guard let lastScalar = line.unicodeScalars.last else { return true }
        if sentenceEnders.contains(lastScalar) {
            return true
        }
        if closingQuotes.contains(lastScalar) {
            let scalars = Array(line.unicodeScalars)
            if scalars.count >= 2 && sentenceEnders.contains(scalars[scalars.count - 2]) {
                return true
            }
        }
        return false
    }

    private func applyRules(
        to text: String,
        rules: [ReplaceRule],
        isTitle: Bool,
        bookName: String?,
        sourceUrl: String?) -> String {
        var result = text
        let activeRules = rules
            .sorted { $0.order < $1.order }
            .filter { rule in
                guard rule.isEnabled, rule.isValid else { return false }
                if isTitle && !rule.scopeTitle { return false }
                if !isTitle && !rule.scopeContent { return false }
                return rule.matches(bookName: bookName, sourceUrl: sourceUrl)
            }

        for rule in activeRules {
            if rule.isRegex {
                guard let regex = cachedRegex(pattern: rule.pattern, caseSensitive: rule.isCaseSensitive) else {
                    continue
                }
                let nsRange = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: nsRange,
                    withTemplate: rule.replacement)
            } else {
                let options: NSString.CompareOptions = rule.isCaseSensitive ? [] : [.caseInsensitive]
                result = result.replacingOccurrences(
                    of: rule.pattern,
                    with: rule.replacement,
                    options: options)
            }
        }
        return result
    }

    private func cachedRegex(pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
        let key = "\(caseSensitive ? "1" : "0"):\(pattern)" as NSString
        if let cached = regexCache.object(forKey: key) {
            return cached
        }
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        regexCache.setObject(compiled, forKey: key)
        return compiled
    }
}
