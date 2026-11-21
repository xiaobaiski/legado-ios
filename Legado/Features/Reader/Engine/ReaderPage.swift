import Foundation
import UIKit

/// 单页 CoreText 排版结果实体
public struct ReaderPage: Identifiable, Equatable, Sendable {
    public var id: String {
        "\(chapterIndex)_\(pageIndex)"
    }

    public let pageIndex: Int
    public let chapterIndex: Int
    public let chapterTitle: String
    public let textRange: NSRange
    public let contentText: String
    /// 本页开头属于正文章节大标题的 UTF-16 字符数（通常仅第 0 页非 0，用于精确应用标题字号与间距）
    public let titlePrefixLength: Int

    public init(
        pageIndex: Int,
        chapterIndex: Int,
        chapterTitle: String,
        textRange: NSRange,
        contentText: String,
        titlePrefixLength: Int = 0) {
        self.pageIndex = pageIndex
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.textRange = textRange
        self.contentText = contentText
        self.titlePrefixLength = titlePrefixLength
    }
}
