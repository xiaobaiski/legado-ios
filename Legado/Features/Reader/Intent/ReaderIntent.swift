import Foundation
import UIKit

/// 阅读器用户离散交互意图
public enum ReaderIntent: ViewIntent, Equatable, Sendable {
    /// 载入并排版指定章节
    case loadChapter(Int)
    /// 下一页 (最后一页时自动进入下一章)
    case nextPage
    /// 上一页 (第一页时自动进入上一章末尾)
    case prevPage
    /// 跳转到当前章节特定页码
    case jumpToPage(Int)
    /// 切换 HUD 唤出/隐藏
    case toggleHUD
    /// 隐藏 HUD
    case hideHUD
    /// 打开目录抽屉
    case openToc
    /// 关闭目录抽屉
    case closeToc
    /// 打开排版与主题设置抽屉
    case openConfig
    /// 关闭排版设置
    case closeConfig
    /// 调整字号增减
    case changeFontSize(delta: CGFloat)
    /// 切换配色主题
    case selectTheme(ReaderTheme)
    /// 切换翻页动效模式
    case selectPageTurnMode(PageTurnMode)
    /// 批量更新完整排版/阅读配置并持久化
    case updateConfig(ReaderConfig)
    /// 恢复默认阅读排版配置
    case resetConfig
    /// 打开更多阅读设置抽屉
    case openMoreSettings
    /// 关闭更多阅读设置抽屉
    case closeMoreSettings
    /// 开关自动翻页
    case toggleAutoPage
    /// 调整自动翻页间隔（秒）
    case setAutoPageInterval(Double)
    /// 导入本地自定义字体文件 (TTF/OTF/TTC)
    case importFonts([URL])
    /// 选择已导入的自定义字体
    case selectCustomFont(ImportedFont)
    /// 删除已导入的自定义字体
    case deleteImportedFont(ImportedFont)
    /// 刷新本地字体列表
    case refreshImportedFonts
    /// 手动重新排版当前章节（例如修改替换净化规则后即时生效）
    case repaginate
    /// 屏幕尺寸尺寸更新重新排版
    case updateScreenBounds(CGRect)
    /// 切换书源并重载新目录与章节
    case switchSource(updatedBook: Book, newToc: [Chapter], matchedChapterIndex: Int)
    /// 跳转到指定章节及字符偏移位置 (用于全文搜索定位)
    case jumpToChapterAndOffset(chapterIndex: Int, matchOffset: Int)
    /// 切换当前页面书签状态 (添加或删除书签)
    case toggleBookmark
    /// 添加带笔记的书签
    case addBookmark(chapterIndex: Int, chapterPos: Int, chapterTitle: String, bookText: String, note: String)
    /// 删除指定书签
    case deleteBookmark(id: String)
    /// 刷新书签列表
    case loadBookmarks
}

/// 阅读器副作用
public enum ReaderEffect: ViewEffect, Equatable, Sendable {
    case showToast(String)
    case hapticFeedback
    case navigateBack
}
