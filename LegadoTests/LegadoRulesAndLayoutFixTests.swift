import CoreGraphics
import Foundation
@testable import Legado
import SwiftData
import Testing

@Suite("Legado Rules Compatibility & Reader Layout Fixes")
struct LegadoRulesAndLayoutFixTests {
    @Test("Local Book Empty Chapter Never Throws URLError -1008")
    func localEmptyChapterNeverThrows1008() async throws {
        let tempCacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLocalEmpty_\(UUID().uuidString)", isDirectory: true)
        let cacheRepo = BookCacheRepositoryImpl(baseDirectory: tempCacheDir)
        defer { try? FileManager.default.removeItem(at: tempCacheDir) }

        let bookUrl = "local://empty-chapter-test"
        try cacheRepo.saveChapterContent(bookUrl: bookUrl, index: 0, content: "")

        let useCase = GetChapterContentUseCase(cacheRepository: cacheRepo)
        let emptyChapter = Chapter(url: "\(bookUrl)/0", title: "第一卷 序幕", bookUrl: bookUrl, index: 0)
        let missingChapter = Chapter(url: "\(bookUrl)/9", title: "缺失章", bookUrl: bookUrl, index: 9)

        let emptyResult = try await useCase.execute(chapter: emptyChapter, origin: "local")
        let missingResult = try await useCase.execute(chapter: missingChapter, origin: "local")
        #expect(emptyResult == "")
        #expect(missingResult == "")
    }

    @Test("Bottom Margin 24 and 12 Match Exact Render Height Without Extra Gap")
    func bottomMarginExactRenderHeight() {
        let engine = TextLayoutEngine.shared
        let iPhoneBounds = CGRect(x: 0, y: 0, width: 393, height: 852)

        var config24 = ReaderConfig.defaultConfig
        config24.topMargin = 50
        config24.bottomMargin = 24
        config24.showHeader = true
        config24.showFooter = true

        let rect24 = engine.contentRenderRect(for: iPhoneBounds, config: config24)
        #expect(rect24.height == 852 - 50 - 24 - TextLayoutEngine.verticalCanvasPadding)

        var config12 = config24
        config12.bottomMargin = 12
        config12.showFooter = false
        let rect12 = engine.contentRenderRect(for: iPhoneBounds, config: config12)
        #expect(rect12.height == 852 - 50 - 12 - TextLayoutEngine.verticalCanvasPadding)
        #expect(rect12.height > rect24.height)
    }

    @Test("Legado Android ReplaceRule JSON Import, Scope Filtering and Title Purification")
    func legadoReplaceRuleJSONCompatibility() throws {
        let legadoJson = """
        [
          {
            "id": 1700000001000,
            "name": "去除广告尾巴",
            "group": "通用净化",
            "pattern": "【广告】.*?$",
            "replacement": "",
            "scope": "诡秘之主,星辰大海",
            "scopeTitle": false,
            "scopeContent": true,
            "excludeScope": "排除书名",
            "isEnabled": true,
            "isRegex": true,
            "timeoutMillisecond": 3000,
            "order": 1
          },
          {
            "id": 1700000002000,
            "name": "标题去括号广告",
            "group": "标题净化",
            "pattern": "（求月票）",
            "replacement": "",
            "scope": "",
            "scopeTitle": true,
            "scopeContent": false,
            "isEnabled": true,
            "isRegex": false,
            "timeoutMillisecond": 3000,
            "order": 2
          }
        ]
        """

        let tempStoreUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_replace_rules_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempStoreUrl) }

        let store = ReplaceRuleStore(storageUrl: tempStoreUrl)
        store.saveRules([])
        let count = try store.importLegadoJSON(Data(legadoJson.utf8))
        #expect(count == 2)

        let loaded = store.loadRules()
        #expect(loaded.count == 2)
        #expect(loaded[0].id == "1700000001000")
        #expect(loaded[1].isRegex == false)
        #expect(loaded[1].scopeTitle == true)

        let purifier = PurifyContentUseCase.shared
        let cleanedMatchedBook = purifier.processContent(
            "第一章 启航\n正文第一段。【广告】点击领红包",
            bookName: "星辰大海",
            chapterTitle: "第一章 启航",
            rules: loaded,
            enableReplace: true,
            removeSameTitle: true,
            reSegment: false)
        #expect(!cleanedMatchedBook.contains("【广告】"))
        #expect(!cleanedMatchedBook.hasPrefix("第一章 启航"))
        #expect(cleanedMatchedBook.contains("正文第一段。"))

        let untouchedOtherBook = purifier.processContent(
            "正文第一段。【广告】保留",
            bookName: "其他书籍",
            chapterTitle: "第一章",
            rules: loaded,
            enableReplace: true,
            removeSameTitle: false,
            reSegment: false)
        #expect(untouchedOtherBook.contains("【广告】保留"))

        let cleanedTitle = purifier.purifyTitle(
            "第十章 风云再起（求月票）",
            bookName: "任意书籍",
            rules: loaded,
            enableReplace: true)
        #expect(cleanedTitle == "第十章 风云再起")
    }

    @Test("Legado Smart ReSegment Rejoins Broken Lines and Splits Dialogues")
    func legadoSmartReSegment() {
        let broken = """
        第一章 测试
        夜色深沉，他推开
        沉重的木门走了进去。
        “你来了？”“是的，我来了。”
        """
        let result = PurifyContentUseCase.shared.smartReSegment(broken, chapterTitle: "第一章 测试")
        #expect(result.contains("夜色深沉，他推开沉重的木门走了进去。"))
        #expect(result.contains("“你来了？”\n“是的，我来了。”"))
    }

    @Test("Legado TxtTocRule JSON Import, Auto-Selection and Volume Header Merging")
    func legadoTxtTocRuleAndVolumeMerge() throws {
        let tocJson = """
        [
          {
            "id": -12,
            "enable": true,
            "name": "Chapter 英文序号",
            "rule": "^[ 　\\\\t]{0,4}[Cc]hapter\\\\s{0,4}\\\\d{1,4}.{0,30}$",
            "example": "Chapter 1 Start",
            "serialNumber": 0
          }
        ]
        """
        let tempStoreUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_toc_rules_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempStoreUrl) }

        let store = TxtTocRuleStore(storageUrl: tempStoreUrl)
        let imported = try store.importLegadoJSON(Data(tocJson.utf8))
        #expect(imported == 1)

        let englishSample = """
        Chapter 1 Dawn
        The sun rose slowly over the quiet valley.

        Chapter 2 Journey
        They packed their supplies and headed north.
        """
        let engChapters = TxtTocParser.parse(text: englishSample, rules: TxtTocRule.defaultRules)
        #expect(engChapters.count == 2)
        #expect(engChapters[0].title == "Chapter 1 Dawn")
        #expect(engChapters[1].title == "Chapter 2 Journey")

        let volumeWithChapterTxt = """
        第一卷 崛起
        第一章 初遇
        少年推开院门，踏上旅途。

        第二章 启程
        远方的钟声回荡在群山之间。
        """
        let merged = TxtTocParser.parse(text: volumeWithChapterTxt, rules: TxtTocRule.defaultRules)
        #expect(merged.count == 2)
        #expect(merged[0].title.contains("第一卷 崛起"))
        #expect(merged[0].title.contains("第一章 初遇"))
        #expect(!merged[0].content.isEmpty)
    }

    @Test("ReadRecordStore Tracks Today & Total Reading Duration Accurately")
    func readRecordStoreTracking() {
        let tempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_read_records_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let store = ReadRecordStore(storageUrl: tempUrl)
        let now = Date()
        store.recordSession(bookName: "诡秘之主", bookAuthor: "乌贼", durationSeconds: 180, date: now)
        store.recordSession(bookName: "诡秘之主", bookAuthor: "乌贼", durationSeconds: 120, date: now)
        store.recordSession(bookName: "星辰大海", bookAuthor: "测试", durationSeconds: 600, date: now)
        // 不足 2 秒的瞬间切出应被忽略
        store.recordSession(bookName: "忽略", bookAuthor: "无", durationSeconds: 1, date: now)

        #expect(store.todayReadSeconds(now: now) == 900)
        #expect(store.totalReadSeconds() == 900)
        let sorted = store.allRecordsSorted()
        #expect(sorted.count == 2)
        #expect(sorted[0].bookName == "星辰大海")
        #expect(sorted[1].readTimeSeconds == 300)
        #expect(ReadRecordStore.formatDuration(3900) == "1 小时 5 分钟")
    }

    @Test("BookshelfState Sorting by Recent, Title and Reading Progress")
    func bookshelfSortingModes() {
        let bookA = Book(
            bookUrl: "local://a",
            name: "B书名",
            author: "作者A",
            durChapterIndex: 5,
            durChapterTime: 2000,
            totalChapterNum: 10)
        let bookB = Book(
            bookUrl: "local://b",
            name: "A书名",
            author: "作者B",
            durChapterIndex: 9,
            durChapterTime: 1000,
            totalChapterNum: 10)

        var state = BookshelfState(books: [bookA, bookB], sortOrder: .recent)
        #expect(state.filteredBooks.first?.bookUrl == "local://a")

        state.sortOrder = .title
        #expect(state.filteredBooks.first?.bookUrl == "local://b")

        state.sortOrder = .progress
        #expect(state.filteredBooks.first?.bookUrl == "local://b")
    }
}
