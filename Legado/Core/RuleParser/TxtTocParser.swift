import Foundation

/// 本地 TXT 章节智能解析实体
public struct ParsedTxtChapter: Equatable, Sendable {
    public let title: String
    public let content: String
    public let index: Int

    public init(title: String, content: String, index: Int) {
        self.title = title
        self.content = content
        self.index = index
    }
}

/// 本地 TXT 小说智能目录与正则分卷解析引擎（对标 Legado Android `TextFile.kt` 多规则优选算法）
public enum TxtTocParser {
    /// 默认通用章节标题正则表达式 (对标 Legado Android 官方 txtTocRule)
    public static let defaultChapterPattern =
        "^[ \\t　]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|" +
        "第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}" +
        "(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张)|回|话)).{0,40}$"

    /// 自动从启用中的 Legado `TxtTocRule` 列表中为当前文本选出最精准的目录规则
    public static func selectBestRule(
        for text: String,
        rules: [TxtTocRule]? = nil) -> TxtTocRule? {
        let candidateRules = (rules ?? TxtTocRuleStore.shared.enabledRules())
            .filter { $0.enable && $0.isValid }
        guard !candidateRules.isEmpty else { return nil }

        // 取前 260K 字符采样评估匹配度（O(260k) 有界切片，避免对整本小说做 O(N) count 扫描）
        let sample = String(text.prefix(260_000))
        let nsSample = sample as NSString
        let fullRange = NSRange(location: 0, length: nsSample.length)

        var bestCount = 0
        var bestRule: TxtTocRule?
        var firstMatchedRule: TxtTocRule?

        for tocRule in candidateRules {
            let (validChapters, shortNoise) = scoreRule(tocRule, in: sample, fullRange: fullRange)
            guard validChapters > 0 else { continue }
            if firstMatchedRule == nil {
                firstMatchedRule = tocRule
            }

            // 与 Legado 评分逻辑对齐：有效章节数至少为误判短行 3 倍，且需超过历史最优规则至少 2 章
            if validChapters >= shortNoise * 3 && validChapters > bestCount + 2 {
                bestCount = validChapters
                bestRule = tocRule
                if bestCount > 70 {
                    break
                }
            }
        }

        return bestRule ?? firstMatchedRule
    }

    private static func scoreRule(
        _ tocRule: TxtTocRule,
        in sample: String,
        fullRange: NSRange) -> (valid: Int, noise: Int) {
        guard let regex = try? NSRegularExpression(
            pattern: tocRule.rule,
            options: [.anchorsMatchLines]) else {
            return (0, 0)
        }
        let matches = regex.matches(in: sample, options: [], range: fullRange)
        var lastEnd = 0
        var validChapters = 0
        var shortNoise = 0

        for match in matches {
            let gap = match.range.location - lastEnd
            if lastEnd == 0 || gap > 100 {
                validChapters += 1
                lastEnd = match.range.location + match.range.length
            } else {
                shortNoise += 1
            }
        }
        return (validChapters, shortNoise)
    }

    /// 解析全文并智能切分为章节单元（支持自定义正则或 Legado 多规则自动优选）
    public static func parse(
        text: String,
        customPattern: String? = nil,
        rules: [TxtTocRule]? = nil) -> [ParsedTxtChapter] {
        let chosenPattern: String
        if let customPattern, !customPattern.isEmpty {
            chosenPattern = customPattern
        } else if let best = selectBestRule(for: text, rules: rules) {
            chosenPattern = best.rule
        } else {
            chosenPattern = defaultChapterPattern
        }

        guard let regex = try? NSRegularExpression(pattern: chosenPattern, options: [.anchorsMatchLines]) else {
            return fallbackChunkSplit(text: text)
        }

        let rawChapters = splitByRegex(text: text, regex: regex)
        if rawChapters.isEmpty {
            return fallbackChunkSplit(text: text)
        }
        return mergeEmptyVolumeHeaders(rawChapters)
    }

    private static func splitByRegex(text: String, regex: NSRegularExpression) -> [ParsedTxtChapter] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return [] }

        var chapters: [ParsedTxtChapter] = []
        chapters.reserveCapacity(matches.count)

        var currentTitle: String?
        var contentStart = 0
        var lastLineLocation = -1
        var chapterIndex = 0

        for match in matches {
            let safeLoc = min(match.range.location, max(nsText.length - 1, 0))
            let safeLen = min(match.range.length, max(nsText.length - safeLoc, 0))
            let lineRange = nsText.lineRange(for: NSRange(location: safeLoc, length: safeLen))
            guard lineRange.location != lastLineLocation else { continue }

            let title = nsText.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            lastLineLocation = lineRange.location

            let bodyLen = max(lineRange.location - contentStart, 0)
            let body = bodyLen > 0
                ? nsText.substring(with: NSRange(location: contentStart, length: bodyLen))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            if let prevTitle = currentTitle {
                chapters.append(ParsedTxtChapter(title: prevTitle, content: body, index: chapterIndex))
                chapterIndex += 1
            } else if !body.isEmpty {
                chapters.append(ParsedTxtChapter(title: "前言", content: body, index: chapterIndex))
                chapterIndex += 1
            }

            currentTitle = title
            contentStart = lineRange.location + lineRange.length
        }

        if let title = currentTitle {
            let tailLen = max(nsText.length - contentStart, 0)
            let tail = tailLen > 0
                ? nsText.substring(with: NSRange(location: contentStart, length: tailLen))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            chapters.append(ParsedTxtChapter(title: title, content: tail, index: chapterIndex))
        }
        return chapters
    }

    /// 合并连续出现的空卷标题（如“第一卷 崛起”紧跟“第一章 初遇”），防止生成无正文空章节
    private static func mergeEmptyVolumeHeaders(_ raw: [ParsedTxtChapter]) -> [ParsedTxtChapter] {
        var merged: [ParsedTxtChapter] = []
        var pendingPrefix: String?

        for item in raw {
            let bodyEmpty = item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if bodyEmpty {
                pendingPrefix = pendingPrefix.map { "\($0) · \(item.title)" } ?? item.title
                continue
            }
            let finalTitle = pendingPrefix.map { "\($0) · \(item.title)" } ?? item.title
            pendingPrefix = nil
            merged.append(ParsedTxtChapter(
                title: finalTitle,
                content: item.content,
                index: merged.count))
        }

        if merged.isEmpty {
            return raw.enumerated().map { idx, item in
                ParsedTxtChapter(title: item.title, content: item.content, index: idx)
            }
        }
        return merged
    }

    /// 保底分卷：按每 4000 字符切分为连续小节
    private static func fallbackChunkSplit(text: String) -> [ParsedTxtChapter] {
        let chunkSize = 4000
        var chapters: [ParsedTxtChapter] = []
        var currentIndex = text.startIndex
        var partIndex = 1

        while currentIndex < text.endIndex {
            let nextIndex = text.index(currentIndex, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[currentIndex ..< nextIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chapters.append(ParsedTxtChapter(
                    title: "第 \(partIndex) 节",
                    content: chunk,
                    index: partIndex - 1))
                partIndex += 1
            }
            currentIndex = nextIndex
        }

        if chapters.isEmpty {
            chapters.append(ParsedTxtChapter(title: "正文", content: text, index: 0))
        }

        return chapters
    }
}
