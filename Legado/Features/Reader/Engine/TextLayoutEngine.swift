import CoreText
import Foundation
import UIKit

/// 基于 CoreText 的高性能非阻塞分页排版引擎
public final class TextLayoutEngine: Sendable {
    public static let shared = TextLayoutEngine()

    public init() {}

    /// 规范化章节文本（繁简转换 + 按用户配置统一段首缩进与空行）
    public func normalizeContent(_ content: String, config: ReaderConfig) -> String {
        let converted = config.chineseConversion.convert(content)
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
        config: ReaderConfig) -> [ReaderPage] {
        guard !content.isEmpty else {
            return [
                ReaderPage(
                    pageIndex: 0,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapterTitle,
                    textRange: NSRange(location: 0, length: 0),
                    contentText: "本章内容为空"),
            ]
        }

        let normalized = normalizeContent(content, config: config)
        let renderRect = contentRenderRect(for: bounds, config: config)
        let attrString = createAttributedString(
            title: chapterTitle,
            content: normalized,
            config: config)

        let pages = slicePages(
            attrString: attrString,
            chapterTitle: chapterTitle,
            chapterIndex: chapterIndex,
            renderRect: renderRect)

        if pages.isEmpty {
            return [
                ReaderPage(
                    pageIndex: 0,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapterTitle,
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

    /// 计算除去上下左右安全内边距的实际排版矩阵
    public func contentRenderRect(for bounds: CGRect, config: ReaderConfig) -> CGRect {
        let renderWidth = max(bounds.width - config.horizontalMargin * 2, 100)
        let renderHeight = max(bounds.height - config.topMargin - config.bottomMargin - 16, 100)
        return CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight)
    }

    /// 构造具备中文段落特征的排版富文本（分页与 CoreText 页面绘制共用，保证像素级一致）
    public func createAttributedString(
        title _: String = "",
        content: String,
        config: ReaderConfig,
        highlightedSentence: String? = nil) -> NSAttributedString {
        let font = config.fontFamily.uiFont(size: config.fontSize, isBold: config.isBoldFont)
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
