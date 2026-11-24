import CoreText
import Foundation
import UIKit

/// 基于 CoreText 的高性能非阻塞分页排版引擎（支持正文章节大标题排版、精确定位与 pixel-perfect 绘制）
public final class TextLayoutEngine: Sendable {
    public static let shared = TextLayoutEngine()
    public static let verticalCanvasPadding: CGFloat = 6
    private static let paragraphTrimChars = CharacterSet(charactersIn: " \t\u{3000}\u{00A0}\r")

    public init() {}

    /// 计算与 ReaderPageView 严格像素对齐的有效页眉高度
    public static func effectiveTopMargin(for config: ReaderConfig) -> CGFloat {
        let minHeader = max(config.tipConfig.tipFontSize + 11, 22)
        return config.showHeader ? max(config.topMargin, minHeader) : config.topMargin
    }

    /// 计算与 ReaderPageView 严格像素对齐的有效页脚高度
    public static func effectiveBottomMargin(for config: ReaderConfig) -> CGFloat {
        let minFooter = max(config.tipConfig.tipFontSize + 9, 20)
        return config.showFooter ? max(config.bottomMargin, minFooter) : config.bottomMargin
    }

    /// 规范化章节文本（Legado 去重标题 + 智能重分段 + 替换净化规则 + 繁简转换 + 统一段首缩进）
    public func normalizeContent(
        _ content: String,
        chapterTitle: String? = nil,
        bookName: String? = nil,
        bookOrigin: String? = nil,
        config: ReaderConfig) -> String {
        let purified = PurifyContentUseCase.shared.processContent(
            content,
            bookName: bookName,
            chapterTitle: chapterTitle,
            sourceUrl: bookOrigin,
            enableReplace: config.enableReplaceRule,
            removeSameTitle: config.removeSameTitle,
            reSegment: config.reSegment)

        let converted = config.chineseConversion.convert(purified)
        let indentPrefix = String(repeating: "\u{3000}", count: max(0, min(config.paragraphIndent, 4)))

        let paragraphs = converted
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: Self.paragraphTrimChars) }
            .filter { !$0.isEmpty }

        if paragraphs.isEmpty {
            return converted
        }
        return paragraphs.map { indentPrefix + $0 }.joined(separator: "\n")
    }

    /// 构造与分页坐标系完全一致的正文全文（供分页器与书内全文搜索共用）
    public func buildPaginatedFullText(
        chapterTitle: String,
        content: String,
        config: ReaderConfig,
        bookName: String? = nil,
        bookOrigin: String? = nil) -> (fullText: String, titlePrefixLength: Int, displayTitle: String) {
        let displayTitle = PurifyContentUseCase.shared.purifyTitle(
            chapterTitle,
            bookName: bookName,
            sourceUrl: bookOrigin,
            enableReplace: config.enableReplaceRule)
        let normalized = normalizeContent(
            content,
            chapterTitle: chapterTitle,
            bookName: bookName,
            bookOrigin: bookOrigin,
            config: config)
        let convertedTitle = config.chineseConversion.convert(displayTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let includeBodyTitle = config.titleStyle.alignment != .hidden && !convertedTitle.isEmpty
        let fullText = includeBodyTitle ? "\(convertedTitle)\n\(normalized)" : normalized
        let titlePrefixLength = includeBodyTitle ? ((convertedTitle + "\n") as NSString).length : 0
        return (fullText, titlePrefixLength, displayTitle)
    }

    /// 将整章文本依据屏幕可视区域和排版配置精确切割为多个 ReaderPage（首部按 `titleStyle` 渲染章节大标题）
    public func paginate(
        chapterTitle: String,
        content: String,
        chapterIndex: Int,
        bounds: CGRect,
        config: ReaderConfig,
        bookName: String? = nil,
        bookOrigin: String? = nil) -> [ReaderPage] {
        let built = buildPaginatedFullText(
            chapterTitle: chapterTitle,
            content: content,
            config: config,
            bookName: bookName,
            bookOrigin: bookOrigin)
        let displayTitle = built.displayTitle

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [
                ReaderPage(
                    pageIndex: 0,
                    chapterIndex: chapterIndex,
                    chapterTitle: displayTitle,
                    textRange: NSRange(location: 0, length: 0),
                    contentText: displayTitle.isEmpty ? "本章内容为空" : displayTitle),
            ]
        }

        let renderRect = contentRenderRect(for: bounds, config: config)
        let attrString = createAttributedString(
            content: built.fullText,
            config: config,
            titlePrefixLength: built.titlePrefixLength)
        let topOffset = (built.titlePrefixLength > 0 && config.titleStyle.alignment != .hidden)
            ? config.titleStyle.topSpacing
            : 0

        let pages = slicePages(
            attrString: attrString,
            chapterTitle: displayTitle,
            chapterIndex: chapterIndex,
            renderRect: renderRect,
            chapterTitlePrefixLength: built.titlePrefixLength,
            firstPageTopOffset: topOffset)

        if pages.isEmpty {
            return [
                ReaderPage(
                    pageIndex: 0,
                    chapterIndex: chapterIndex,
                    chapterTitle: displayTitle,
                    textRange: NSRange(location: 0, length: 0),
                    contentText: built.fullText),
            ]
        }
        return pages
    }

    private func slicePages(
        attrString: NSAttributedString,
        chapterTitle: String,
        chapterIndex: Int,
        renderRect: CGRect,
        chapterTitlePrefixLength: Int,
        firstPageTopOffset: CGFloat) -> [ReaderPage] {
        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        let path = CGPath(rect: renderRect, transform: nil)
        let firstHeight = max(renderRect.height - max(firstPageTopOffset, 0), 80)
        let firstPath = firstPageTopOffset > 0
            ? CGPath(rect: CGRect(x: 0, y: 0, width: renderRect.width, height: firstHeight), transform: nil)
            : path
        let nsText = attrString.string as NSString
        let totalLength = attrString.length

        var pages: [ReaderPage] = []
        var textPos = 0
        var pageIndex = 0

        while textPos < totalLength {
            let activePath = (textPos == 0) ? firstPath : path
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: textPos, length: 0), activePath, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length == 0 {
                break
            }

            let nsRange = NSRange(location: visibleRange.location, length: visibleRange.length)
            let pageTitlePrefix = max(0, min(chapterTitlePrefixLength - nsRange.location, nsRange.length))
            pages.append(ReaderPage(
                pageIndex: pageIndex,
                chapterIndex: chapterIndex,
                chapterTitle: chapterTitle,
                textRange: nsRange,
                contentText: nsText.substring(with: nsRange),
                titlePrefixLength: pageTitlePrefix))

            textPos += visibleRange.length
            pageIndex += 1
        }
        return pages
    }

    /// 计算除去上下左右边距的实际排版矩阵（严格按 leftMargin / rightMargin / topMargin / bottomMargin 像素级对齐）
    public func contentRenderRect(for bounds: CGRect, config: ReaderConfig) -> CGRect {
        let renderWidth: CGFloat
        if config.isDualPageActive(for: bounds) {
            let centerGutter: CGFloat = 32
            let singleColumnWidth = (bounds.width - centerGutter) / 2
            renderWidth = max(singleColumnWidth - config.leftMargin - config.rightMargin, 120)
        } else {
            renderWidth = max(bounds.width - config.leftMargin - config.rightMargin, 120)
        }
        let topReserve = Self.effectiveTopMargin(for: config)
        let bottomReserve = Self.effectiveBottomMargin(for: config)
        let renderHeight = max(bounds.height - topReserve - bottomReserve - Self.verticalCanvasPadding, 100)
        return CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight)
    }

    /// 构造具备中文段落特征与正文章节大标题的排版富文本（分页与 CoreText 页面绘制共用，保证像素级一致）
    public func createAttributedString(
        title _: String = "",
        content: String,
        config: ReaderConfig,
        titlePrefixLength: Int = 0) -> NSAttributedString {
        let font = config.resolvedUIFont()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = config.lineSpacing
        paragraphStyle.paragraphSpacing = config.paragraphSpacing
        paragraphStyle.alignment = config.isTextJustified ? .justified : .left
        paragraphStyle.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor(config.effectiveTextColor),
        ]
        if config.letterSpacing != 0 {
            attributes[.kern] = config.letterSpacing
        }

        let mutable = NSMutableAttributedString(string: content, attributes: attributes)

        let clampedTitleLen = min(max(titlePrefixLength, 0), mutable.length)
        if clampedTitleLen > 0, config.titleStyle.alignment != .hidden {
            let titleFont = config.resolvedUIFont(
                size: config.fontSize + config.titleStyle.sizeDelta,
                isBold: true)
            let titleParagraph = NSMutableParagraphStyle()
            titleParagraph.alignment = config.titleStyle.alignment == .center ? .center : .left
            titleParagraph.paragraphSpacingBefore = config.titleStyle.topSpacing
            titleParagraph.paragraphSpacing = config.titleStyle.bottomSpacing
            titleParagraph.lineSpacing = max(config.lineSpacing * 0.6, 4)

            mutable.addAttributes([
                .font: titleFont,
                .paragraphStyle: titleParagraph,
            ], range: NSRange(location: 0, length: clampedTitleLen))
        }
        return mutable
    }
}
