import CoreText
import Foundation
import UIKit

/// 基于 CoreText 的高性能非阻塞分页排版引擎
public final class TextLayoutEngine: Sendable {
    public static let shared = TextLayoutEngine()
    public static let verticalCanvasPadding: CGFloat = 6

    public init() {}

    /// 计算与 ReaderPageView 严格像素对齐的有效页眉高度
    public static func effectiveTopMargin(for config: ReaderConfig) -> CGFloat {
        config.showHeader ? max(config.topMargin, 22) : config.topMargin
    }

    /// 计算与 ReaderPageView 严格像素对齐的有效页脚高度
    public static func effectiveBottomMargin(for config: ReaderConfig) -> CGFloat {
        config.showFooter ? max(config.bottomMargin, 20) : config.bottomMargin
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
        let trimChars = CharacterSet(charactersIn: " \t\u{3000}\u{00A0}\r")

        let paragraphs = converted
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: trimChars) }
            .filter { !$0.isEmpty }

        if paragraphs.isEmpty {
            return converted
        }
        return paragraphs.map { indentPrefix + $0 }.joined(separator: "\n")
    }

    /// 将整章文本依据屏幕可视区域和排版配置精确切割为多个 ReaderPage
    public func paginate(
        chapterTitle: String,
        content: String,
        chapterIndex: Int,
        bounds: CGRect,
        config: ReaderConfig,
        bookName: String? = nil,
        bookOrigin: String? = nil) -> [ReaderPage] {
        let displayTitle = PurifyContentUseCase.shared.purifyTitle(
            chapterTitle,
            bookName: bookName,
            sourceUrl: bookOrigin,
            enableReplace: config.enableReplaceRule)

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

        let normalized = normalizeContent(
            content,
            chapterTitle: chapterTitle,
            bookName: bookName,
            bookOrigin: bookOrigin,
            config: config)
        let renderRect = contentRenderRect(for: bounds, config: config)
        let attrString = createAttributedString(
            title: displayTitle,
            content: normalized,
            config: config)

        let pages = slicePages(
            attrString: attrString,
            chapterTitle: displayTitle,
            chapterIndex: chapterIndex,
            renderRect: renderRect)

        if pages.isEmpty {
            return [
                ReaderPage(
                    pageIndex: 0,
                    chapterIndex: chapterIndex,
                    chapterTitle: displayTitle,
                    textRange: NSRange(location: 0, length: 0),
                    contentText: normalized),
            ]
        }
        return pages
    }

    private func slicePages(
        attrString: NSAttributedString,
        chapterTitle: String,
        chapterIndex: Int,
        renderRect: CGRect) -> [ReaderPage] {
        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        let path = CGPath(rect: renderRect, transform: nil)
        let nsText = attrString.string as NSString
        let totalLength = attrString.length

        var pages: [ReaderPage] = []
        var textPos = 0
        var pageIndex = 0

        while textPos < totalLength {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: textPos, length: 0), path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length == 0 {
                break
            }

            let nsRange = NSRange(location: visibleRange.location, length: visibleRange.length)
            pages.append(ReaderPage(
                pageIndex: pageIndex,
                chapterIndex: chapterIndex,
                chapterTitle: chapterTitle,
                textRange: nsRange,
                contentText: nsText.substring(with: nsRange)))

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

    /// 构造具备中文段落特征的排版富文本（分页与 CoreText 页面绘制共用，保证像素级一致）
    public func createAttributedString(
        title _: String = "",
        content: String,
        config: ReaderConfig,
        highlightedSentence: String? = nil) -> NSAttributedString {
        let font = config.resolvedUIFont()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = config.lineSpacing
        paragraphStyle.paragraphSpacing = config.paragraphSpacing
        paragraphStyle.alignment = config.isTextJustified ? .justified : .left
        paragraphStyle.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor(config.theme.textColor),
        ]
        if config.letterSpacing != 0 {
            attributes[.kern] = config.letterSpacing
        }

        let mutable = NSMutableAttributedString(string: content, attributes: attributes)
        if let target = highlightedSentence, !target.isEmpty {
            let range = (content as NSString).range(of: target)
            if range.location != NSNotFound {
                mutable.addAttributes([
                    .backgroundColor: UIColor.tintColor.withAlphaComponent(0.18),
                    .foregroundColor: UIColor.tintColor,
                ], range: range)
            }
        }
        return mutable
    }
}
