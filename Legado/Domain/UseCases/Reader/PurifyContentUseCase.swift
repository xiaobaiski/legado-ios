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
            pattern: "((?:https?://|www\\.)[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}(?:/[a-zA-Z0-9#?&._=%-]*)?|" +
                "\\b[a-zA-Z0-9-]+\\.(?:com|cn|net|org|cc|me|io|vip|xyz|top|la|info|tv|tw|hk|uk)" +
                "(?:/[a-zA-Z0-9#?&._=%-]*)?\\b)",
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

        let cacheKey = "dup:\(pattern)" as NSString
        let compiledRegex: NSRegularExpression
        if let cached = regexCache.object(forKey: cacheKey) {
            compiledRegex = cached
        } else if let created = try? NSRegularExpression(pattern: pattern, options: []) {
            regexCache.setObject(created, forKey: cacheKey)
            compiledRegex = created
        } else {
            return content
        }
        let fullRange = NSRange(location: 0, length: (content as NSString).length)
        if let match = compiledRegex.firstMatch(in: content, options: [], range: fullRange),
           match.range.location == 0 {
            return (content as NSString).substring(from: match.range.length)
        }
        return content
    }

    /// 智能段落重排（对标 Legado Android `ContentHelp.reSegment`：黏合误断行 + 规范对话引号分段）
    public func smartReSegment(_ content: String, chapterTitle: String) -> String {
        var normalized = content.replacingOccurrences(of: "&quot;", with: "“")
        normalized = ReSegmentRules.applyPrePass(to: normalized)

        let rawLines = normalized.components(separatedBy: .newlines)
        var mergedLines: [String] = []
        mergedLines.reserveCapacity(rawLines.count / 2 + 1)
        var buffer = ""
        let trimmedChapterTitle = chapterTitle.trimmingCharacters(in: .whitespaces)

        for rawLine in rawLines {
            let cleaned = rawLine.trimmingCharacters(in: ReSegmentRules.trimCharset)
            guard !cleaned.isEmpty else { continue }
            if mergedLines.isEmpty && buffer.isEmpty && cleaned == trimmedChapterTitle {
                continue
            }

            if buffer.isEmpty {
                buffer = cleaned
            } else if ReSegmentRules.lineEndsSentence(buffer) {
                mergedLines.append(buffer)
                buffer = cleaned
            } else {
                buffer += cleaned
            }
        }
        if !buffer.isEmpty {
            mergedLines.append(buffer)
        }

        normalized = ReSegmentRules.applyPostPass(to: mergedLines.joined(separator: "\n"))
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyRules(
        to text: String,
        rules: [ReplaceRule],
        isTitle: Bool,
        bookName: String?,
        sourceUrl: String?) -> String {
        var result = text
        let orderedRules = rulesAlreadySorted(rules) ? rules : rules.sorted { $0.order < $1.order }
        let activeRules = orderedRules.filter { rule in
            guard rule.isEnabled, !rule.pattern.isEmpty else { return false }
            if rule.isRegex, rule.pattern.hasSuffix("|"), !rule.pattern.hasSuffix("\\|") {
                return false
            }
            if isTitle && !rule.scopeTitle { return false }
            if !isTitle && !rule.scopeContent { return false }
            return rule.matches(bookName: bookName, sourceUrl: sourceUrl)
        }

        for rule in activeRules {
            if rule.isRegex {
                guard let regex = cachedRegex(pattern: rule.pattern, caseSensitive: rule.isCaseSensitive) else {
                    continue
                }
                result = replaceRegexWithTimeout(
                    in: result,
                    regex: regex,
                    replacement: rule.replacement,
                    timeoutMs: rule.timeoutMillisecond)
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

    private func replaceRegexWithTimeout(
        in text: String,
        regex: NSRegularExpression,
        replacement: String,
        timeoutMs: Int64) -> String {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let deadline = timeoutMs > 0
            ? Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
            : nil
        let output = NSMutableString()
        var lastLocation = 0
        var timedOut = false

        regex.enumerateMatches(in: text, options: [.reportProgress], range: fullRange) { match, _, stop in
            if let deadline, Date() > deadline {
                timedOut = true
                stop.pointee = true
                return
            }
            guard let match else { return }
            let range = match.range
            if range.location >= lastLocation {
                let prefixRange = NSRange(location: lastLocation, length: range.location - lastLocation)
                output.append(nsText.substring(with: prefixRange))
                output.append(regex.replacementString(for: match, in: text, offset: 0, template: replacement))
                lastLocation = range.location + range.length
            }
        }
        if timedOut {
            return text
        }
        if lastLocation == 0 {
            return text
        }
        if lastLocation < nsText.length {
            output.append(nsText.substring(from: lastLocation))
        }
        return output as String
    }

    private func rulesAlreadySorted(_ rules: [ReplaceRule]) -> Bool {
        guard rules.count > 1 else { return true }
        for index in 1 ..< rules.count where rules[index].order < rules[index - 1].order {
            return false
        }
        return true
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

/// 预编译智能分段正则规则集（进程级复用，避免每章重复编译正与分配临时标量数组）
private enum ReSegmentRules {
    static let trimCharset = CharacterSet(charactersIn: " \t\u{3000}\u{00A0}")
    static let sentenceEnders = CharacterSet(charactersIn: "。？！?!~…")
    static let closingQuotes = CharacterSet(charactersIn: "”\"』」’")

    private static let quoteColon = try? NSRegularExpression(pattern: "[:：]['\"‘”“]+")
    private static let quoteNewline = try? NSRegularExpression(pattern: "[\"”“]+\\s*[\"”“][\\s\"”“]*")
    private static let quotePunctQuote = try? NSRegularExpression(pattern: "[\"”“]+(？|。|！|\\?|!|~)[\"”“]+")
    private static let quotePunctText = try? NSRegularExpression(pattern: "[\"”“]+(？|。|！|\\?|!|~)([^\"”“\\n])")
    private static let dialogueBreak = try? NSRegularExpression(pattern: "([问说喊唱叫骂道着答])[。\\.]")
    private static let colonSpaces = try? NSRegularExpression(pattern: "[:：][”“\"\\s]+")
    private static let multiNewline = try? NSRegularExpression(pattern: "\\n{2,}")

    static func applyPrePass(to text: String) -> String {
        var result = replace(quoteColon, in: text, template: "：“")
        result = replace(quoteNewline, in: result, template: "”\n“")
        return result
    }

    static func applyPostPass(to text: String) -> String {
        var result = replace(quotePunctQuote, in: text, template: "”$1\n“")
        result = replace(quotePunctText, in: result, template: "”$1\n$2")
        result = replace(dialogueBreak, in: result, template: "$1。\n")
        result = replace(colonSpaces, in: result, template: "：“")
        return replace(multiNewline, in: result, template: "\n")
    }

    static func lineEndsSentence(_ line: String) -> Bool {
        let scalars = line.unicodeScalars
        guard !scalars.isEmpty else { return true }
        let lastIndex = scalars.index(before: scalars.endIndex)
        let lastScalar = scalars[lastIndex]
        if sentenceEnders.contains(lastScalar) {
            return true
        }
        if closingQuotes.contains(lastScalar), lastIndex > scalars.startIndex {
            let previousIndex = scalars.index(before: lastIndex)
            return sentenceEnders.contains(scalars[previousIndex])
        }
        return false
    }

    private static func replace(
        _ regex: NSRegularExpression?,
        in text: String,
        template: String) -> String {
        guard let regex else { return text }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: fullRange, withTemplate: template)
    }
}
