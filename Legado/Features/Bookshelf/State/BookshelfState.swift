import Foundation

/// 书架布局模式 (宫格封面 vs 详尽列表)
public enum BookshelfLayoutMode: String, CaseIterable, Codable, Sendable {
    case grid = "宫格"
    case list = "列表"

    public static let storageKey = "legado_bookshelf_layout_mode"
}

/// 书架排序方式
public enum BookshelfSortOrder: String, CaseIterable, Identifiable, Codable, Sendable {
    case recent = "最近阅读"
    case title = "书名排序"
    case progress = "阅读进度"

    public static let storageKey = "legado_bookshelf_sort_order"

    public var id: String {
        rawValue
    }
}

/// 书架模块单一不可变状态
public struct BookshelfState: ViewState, Equatable {
    public var isLoading: Bool
    public var books: [Book]
    public var selectedGroup: String
    public var groups: [String]
    public var customGroups: [BookGroup]
    public var layoutMode: BookshelfLayoutMode
    public var sortOrder: BookshelfSortOrder
    public var isBatchMode: Bool
    public var selectedBookUrls: Set<String>
    public var isRefreshingUpdates: Bool
    public var isImporting: Bool
    public var updatedBookUrls: Set<String>
    public var searchText: String

    public init(
        isLoading: Bool = false,
        books: [Book] = [],
        selectedGroup: String = "全部",
        groups: [String] = ["全部", "在读", "未读", "完结"],
        customGroups: [BookGroup] = [],
        layoutMode: BookshelfLayoutMode = .grid,
        sortOrder: BookshelfSortOrder = .recent,
        isBatchMode: Bool = false,
        selectedBookUrls: Set<String> = [],
        isRefreshingUpdates: Bool = false,
        isImporting: Bool = false,
        updatedBookUrls: Set<String> = [],
        searchText: String = "") {
        self.isLoading = isLoading
        self.books = books
        self.selectedGroup = selectedGroup
        self.groups = groups
        self.customGroups = customGroups
        self.layoutMode = layoutMode
        self.sortOrder = sortOrder
        self.isBatchMode = isBatchMode
        self.selectedBookUrls = selectedBookUrls
        self.isRefreshingUpdates = isRefreshingUpdates
        self.isImporting = isImporting
        self.updatedBookUrls = updatedBookUrls
        self.searchText = searchText
    }

    /// 最近一次打开阅读的书籍（优先定位真正产生过阅读进度的书籍，避免未读新书抢占入口）
    public var recentReadingBook: Book? {
        let activelyRead = books.filter {
            $0.durChapterTime > 0 && ($0.durChapterIndex > 0 || $0.durChapterPos > 0)
        }
        if let latest = activelyRead.max(by: { $0.durChapterTime < $1.durChapterTime }) {
            return latest
        }
        return books
            .filter { $0.durChapterTime > 0 }
            .max { $0.durChapterTime < $1.durChapterTime }
    }

    /// 根据当前分组、搜索关键词与排序方式过滤排序后的书籍列表
    public var filteredBooks: [Book] {
        var list = books

        if selectedGroup == "在读" {
            list = list.filter { $0.durChapterIndex > 0 || $0.durChapterPos > 0 }
        } else if selectedGroup == "未读" {
            list = list.filter { $0.durChapterIndex == 0 && $0.durChapterPos == 0 }
        } else if selectedGroup == "完结" {
            list = list.filter { $0.kind?.contains("完结") == true }
        } else if selectedGroup != "全部" {
            list = list.filter { $0.groupName == selectedGroup }
        }

        if !searchText.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                    $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOrder {
        case .recent:
            list.sort {
                if $0.durChapterTime != $1.durChapterTime {
                    return $0.durChapterTime > $1.durChapterTime
                }
                if $0.latestChapterTime != $1.latestChapterTime {
                    return $0.latestChapterTime > $1.latestChapterTime
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

        case .title:
            list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        case .progress:
            list.sort { Self.progressRatio($0) > Self.progressRatio($1) }
        }

        return list
    }

    private static func progressRatio(_ book: Book) -> Double {
        let hasStarted = book.durChapterIndex > 0 || book.durChapterPos > 0
        guard book.totalChapterNum > 0 else {
            return hasStarted ? 0.01 : 0
        }
        return hasStarted ? Double(book.durChapterIndex + 1) / Double(book.totalChapterNum) : 0
    }
}
