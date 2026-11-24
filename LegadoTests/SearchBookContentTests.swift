import CoreGraphics
import Foundation
@testable import Legado
import Testing

@Suite("Search Book Content Suite")
struct SearchBookContentTests {
    @Test("Test SearchBookContentUseCase across chapters and snippet extraction")
    func searchAcrossChapters() async {
        let getChapterContentUseCase = GetChapterContentUseCase()

        let book = Book(
            bookUrl: "local://test/book1",
            tocUrl: "",
            origin: "local",
            originName: "本地导入",
            name: "诡秘探险",
            author: "探险家")

        let chapters = [
            Chapter(url: "local://test/book1/0", title: "第一章 初入秘境", bookUrl: book.bookUrl, index: 0),
            Chapter(url: "local://test/book1/1", title: "第二章 迷雾中的石碑", bookUrl: book.bookUrl, index: 1),
        ]

        let ch1Content = "夜幕降临，微风吹拂。卢米安站在崖顶，眺望着远方的古老石碑。"
        let ch2Content = "清晨的阳光穿透迷雾，石碑上的铭文若隐若现。卢米安仔细端详。"

        getChapterContentUseCase.saveChapterCache(content: ch1Content, bookUrl: book.bookUrl, index: 0)
        getChapterContentUseCase.saveChapterCache(content: ch2Content, bookUrl: book.bookUrl, index: 1)

        let searchUseCase = SearchBookContentUseCase()

        // 1. 搜索关键词 "石碑"
        var matches: [BookSearchMatch] = []
        for await match in searchUseCase.search(
            keyword: "石碑",
            book: book,
            chapters: chapters,
            getChapterContentUseCase: getChapterContentUseCase) {
            matches.append(match)
        }

        #expect(matches.count == 2)
        #expect(matches[0].chapterIndex == 0)
        #expect(matches[0].chapterTitle == "第一章 初入秘境")
        #expect(matches[0].snippet.contains("石碑"))
        #expect(matches[1].chapterIndex == 1)
        #expect(matches[1].chapterTitle == "第二章 迷雾中的石碑")
        #expect(matches[1].snippet.contains("石碑"))

        // 2. 空白关键词测试
        var emptyMatches: [BookSearchMatch] = []
        for await match in searchUseCase.search(
            keyword: "   ",
            book: book,
            chapters: chapters,
            getChapterContentUseCase: getChapterContentUseCase) {
            emptyMatches.append(match)
        }
        #expect(emptyMatches.isEmpty)
    }

    @Test("Test SearchBookContentViewModel MVI Flow")
    @MainActor
    func viewModelFlow() async {
        let getChapterContentUseCase = GetChapterContentUseCase()

        let book = Book(
            bookUrl: "local://test/book1",
            tocUrl: "",
            origin: "local",
            originName: "本地导入",
            name: "诡秘探险",
            author: "探险家")

        let chapters = [
            Chapter(url: "local://test/book1/0", title: "第一章 初入秘境", bookUrl: book.bookUrl, index: 0),
        ]

        getChapterContentUseCase.saveChapterCache(
            content: "卢米安在迷雾中找到了古老的宝藏。",
            bookUrl: book.bookUrl,
            index: 0)

        let viewModel = BookSearchContentViewModel(
            book: book,
            chapters: chapters,
            getChapterContentUseCase: getChapterContentUseCase)

        #expect(viewModel.state.query.isEmpty)
        #expect(viewModel.state.matches.isEmpty)

        // 发送检索 Intent
        viewModel.send(.updateQuery("宝藏"))
        try? await Task.sleep(nanoseconds: 400_000_000)

        #expect(viewModel.state.matches.count == 1)
        #expect(viewModel.state.matches.first?.chapterTitle == "第一章 初入秘境")
        #expect(viewModel.state.totalMatchesCount == 1)

        // 清理 Intent
        viewModel.send(.clear)
        #expect(viewModel.state.query.isEmpty)
        #expect(viewModel.state.matches.isEmpty)
    }

    @Test("Test ReaderViewModel jumpToChapterAndOffset")
    @MainActor
    func readerJumpToOffset() async {
        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)
        let getChapterContentUseCase = GetChapterContentUseCase()
        let getBookTocUseCase = GetBookTocUseCase(bookRepository: bookRepo)

        let book = Book(
            bookUrl: "local://test/book1",
            tocUrl: "",
            origin: "local",
            originName: "本地导入",
            name: "诡秘探险",
            author: "探险家")

        let chapters = [
            Chapter(url: "https://test.com/c1", title: "第一章", bookUrl: book.bookUrl, index: 0),
            Chapter(url: "https://test.com/c2", title: "第二章", bookUrl: book.bookUrl, index: 1),
        ]

        try? await bookRepo.saveBook(book)
        try? await bookRepo.saveChapters(chapters, for: book.bookUrl)

        getChapterContentUseCase.saveChapterCache(
            content: "第一章内容开始... 经过漫长的旅程，卢米安终于抵达目的地。",
            bookUrl: book.bookUrl,
            index: 0)
        getChapterContentUseCase.saveChapterCache(
            content: "第二章内容开始... 这里是一片无尽的荒漠。",
            bookUrl: book.bookUrl,
            index: 1)

        let readerViewModel = ReaderViewModel(
            book: book,
            initialChapterIndex: 0,
            getChapterContentUseCase: getChapterContentUseCase,
            getBookTocUseCase: getBookTocUseCase,
            bookRepository: bookRepo)

        // 等待初始加载
        try? await Task.sleep(nanoseconds: 200_000_000)

        // 跳转到第二章某个字符偏移
        readerViewModel.send(.jumpToChapterAndOffset(chapterIndex: 1, matchOffset: 12))
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(readerViewModel.state.currentChapterIndex == 1)
        #expect(readerViewModel.state.currentPageIndex >= 0)
    }

    @Test("SearchBookContentUseCase aligns matchOffset with TextLayoutEngine and ChineseConversionMode")
    func searchAlignsMatchOffsetWithPaginationAndChineseConversion() async {
        let getChapterContentUseCase = GetChapterContentUseCase()
        let book = Book(
            bookUrl: "local://test/book_tc_search",
            origin: "local",
            originName: "本地导入",
            name: "繁简搜索校对",
            author: "测试者")
        let chapter = Chapter(
            url: "local://test/book_tc_search/0",
            title: "第一章 秘境",
            bookUrl: book.bookUrl,
            index: 0)

        let rawContent = "这是一段用于校对繁简转换与分页偏移坐标的测试文本，后半段包含关键目标词汇石碑铭文。"
        getChapterContentUseCase.saveChapterCache(content: rawContent, bookUrl: book.bookUrl, index: 0)

        let config = ReaderConfig(
            chineseConversion: .toTraditional,
            enableReplaceRule: false)

        var matches: [BookSearchMatch] = []
        for await match in SearchBookContentUseCase().search(
            keyword: "石碑銘文",
            book: book,
            chapters: [chapter],
            getChapterContentUseCase: getChapterContentUseCase,
            config: config) {
            matches.append(match)
        }

        #expect(matches.count == 1)
        guard let hit = matches.first else { return }

        let pages = TextLayoutEngine.shared.paginate(
            chapterTitle: chapter.title,
            content: rawContent,
            chapterIndex: 0,
            bounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            config: config,
            bookName: book.name,
            bookOrigin: book.origin)

        let hitPage = pages.first { NSLocationInRange(hit.matchOffset, $0.textRange) }
        #expect(hitPage != nil)
        #expect(hitPage?.contentText.contains("石碑銘文") == true)
    }
}
