import Foundation

// MARK: - AppEnvironment 示例数据初始化扩展

extension AppEnvironment {
    func seedSampleSourcesIfNeeded() async {
        let sources = (try? await bookSourceRepository.fetchSources()) ?? []
        let sampleSource = Self.createDefaultSampleSource()
        let kuwoSource = Self.createKuwoSampleSource()

        var toSave: [BookSource] = []
        if !sources.contains(where: { $0.bookSourceUrl == sampleSource.bookSourceUrl }) {
            toSave.append(sampleSource)
        }
        if !sources.contains(where: { $0.bookSourceUrl == kuwoSource.bookSourceUrl }) {
            toSave.append(kuwoSource)
        }
        if !toSave.isEmpty {
            try? await bookSourceRepository.saveSources(toSave)
        }
    }

    private static func createDefaultSampleSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://biquge.example.com",
            bookSourceName: "笔趣阁官方",
            bookSourceType: 0,
            bookSourceComment: "内置演示书源",
            exploreUrl: """
            玄幻奇幻::/sort/1_{{page}}.html
            武侠仙侠::/sort/2_{{page}}.html
            都市言情::/sort/3_{{page}}.html
            历史军事::/sort/4_{{page}}.html
            """,
            ruleExplore: RuleExplore(
                bookList: ".item",
                name: "dt a@text",
                author: "dt span@text",
                intro: ".intro@text",
                kind: ".book-kind@text",
                bookUrl: "dt a@href",
                coverUrl: "img@src"),
            ruleSearch: RuleSearch(
                checkKeyWord: "宿命",
                bookList: ".item",
                name: "dt a@text",
                author: "dt span@text",
                intro: ".intro@text",
                kind: ".book-kind@text",
                bookUrl: "dt a@href",
                coverUrl: "img@src"),
            ruleBookInfo: RuleBookInfo(
                name: "h1.book-name@text",
                author: "span.author@text",
                intro: "p.intro@text"),
            ruleToc: RuleToc(
                chapterList: "ul.chapters li a",
                chapterName: "text",
                chapterUrl: "href"),
            ruleContent: RuleContent(
                content: "#content@text"))
    }

    private static func createKuwoSampleSource() -> BookSource {
        let kuwoHeader = "{\"Accept\":\"*/*\",\"Connection\":\"Close\"," +
            "\"User-Agent\":\"Dalvik/2.1.0 (Linux; U; Android 8.0.0; LND-AL40 Build/HONORLND-AL40)\"}"
        let kuwoKindSearch = "{{$.category_name}},{{$.status}}@js:result.replace(/30/,\"连载\").replace(/50/,\"完结\")"
        let kuwoKindInfo = "{{$.category_name}},{{$.status}},{{$.update_time}}@js:result" +
            ".replace(/30/,\"连载\").replace(/50/,\"完结\").replace(/\\s..:.*/,\"\")"
        let kuwoChapterFilter = "$.chapter_title##正文卷.|正文.|VIP卷.|默认卷.|卷_|VIP章节.|免费章节.|章节目录.|最新章节.|" +
            "[\\(（【].*?[求更票谢乐发订合补加架字修Kk].*?[】）\\)]"

        return BookSource(
            bookSourceUrl: "http://appi.kuwo.cn",
            bookSourceName: "酷我小说",
            bookSourceGroup: "API",
            bookSourceType: 0,
            customOrder: 1,
            enabled: true,
            enabledExplore: false,
            header: kuwoHeader,
            searchUrl: "/novels/api/book/search?keyword={{key}}&pi={{page}}&ps=30",
            ruleSearch: RuleSearch(
                checkKeyWord: "剑神",
                bookList: "$.data",
                name: "$.title",
                author: "$.author_name",
                intro: "$.intro",
                kind: kuwoKindSearch,
                bookUrl: "/novels/api/book/{{$.book_id}}",
                coverUrl: "$.cover_url",
                wordCount: "$.all_words"),
            ruleBookInfo: RuleBookInfo(
                bookInfoInit: "$.data",
                name: "$.title",
                author: "$.author_name",
                intro: "$.intro##(^|[。！？]+[”」）】]?)##$1<br>",
                kind: kuwoKindInfo,
                lastChapter: "$.new_chapter_name",
                coverUrl: "$.cover_url",
                tocUrl: "/novels/api/book/{{$.book_id}}/chapters?paging=0",
                wordCount: "$.all_words"),
            ruleToc: RuleToc(
                chapterList: "$.data",
                chapterName: kuwoChapterFilter,
                chapterUrl: "/novels/api/book/{{$.book_id}}/chapters/{{$.chapter_id}}"),
            ruleContent: RuleContent(
                content: "$.data.content"))
    }

    func seedSampleBookshelfIfNeeded() async {
        let books = (try? await bookRepository.getBookshelf()) ?? []
        guard books.isEmpty else { return }

        let sampleBook = Book(
            bookUrl: "https://biquge.example.com/book/circle_of_inevitability",
            tocUrl: "https://biquge.example.com/book/circle_of_inevitability/toc",
            origin: "https://biquge.example.com",
            originName: "笔趣阁官方",
            name: "宿命之环",
            author: "爱潜水的乌贼",
            kind: "连载中 奇幻 序列途径",
            coverUrl: "https://bookcover.yuewen.com/qdbimg/349573/1036370336/300.webp",
            intro: "诡秘之主第二部。四旬节的前夜，微风轻拂的夜晚，卢米安站在崖顶，眺望着科尔杜村...",
            latestChapterTitle: "第150章 最后的落幕",
            durChapterTitle: "第一章 宿命之始",
            durChapterIndex: 0,
            wordCount: "285万字")
        try? await bookRepository.saveBook(sampleBook)

        let chapters = [
            Chapter(url: "https://biquge.example.com/c1", title: "第一章 宿命之始", bookUrl: sampleBook.bookUrl, index: 0),
            Chapter(url: "https://biquge.example.com/c2", title: "第二章 科尔杜村的阴影", bookUrl: sampleBook.bookUrl, index: 1),
            Chapter(url: "https://biquge.example.com/c3", title: "第三章 恶作剧与神秘客", bookUrl: sampleBook.bookUrl, index: 2),
        ]
        try? await bookRepository.saveChapters(chapters, for: sampleBook.bookUrl)

        let sampleContent = """
        　　夜幕降临，微凉的晚风吹拂过荒野，带来了远处不知名野兽的低沉吼声。
        　　卢米安站在高耸的崖壁顶端，俯瞰着下方若隐若现的村落灯火。在这个充满神秘与超凡的世界里，每一个看似宁静的黑夜背后，都潜藏着凡人难以窥见的波诡云谲。
        　　他下意识地摸了摸胸前的银质吊坠，冰冷的金属触感让他狂躁的心绪稍微平复了一些。根据那位神秘女士的指引，只要在特定的星象下完成仪式，就能真正迈入第一序列。
        　　但仪式所需要的祭品并不简单，除了罕见的灵界生物毛发，还需要一份真正直面疯狂与恐惧的勇气。
        　　狂风渐起，天空中厚重的铅云缓缓移动，露出了那一弯猩红如血的残月。命运的齿轮，已在此刻悄然转动。
        　　“时间差不多了。”卢米安低声自语，转身踏上了通往古老遗迹的荒凉小道。
        """

        getChapterContentUseCase.saveChapterCache(
            content: sampleContent,
            bookUrl: sampleBook.bookUrl,
            index: 0)

        let chapterTwoContent = """
        　　清晨的薄雾还未散尽，科尔杜村的钟楼已经敲响了第一声沉闷的钟鸣。
        　　石板路两侧的木屋渐渐升起炊烟，面包房里飘出黑麦发酵后的微酸香气，与山风带来的松针气息交织在一起。
        　　卢米安压低帽檐，穿过热闹却又透着一丝压抑的集市。自从前几日那场突如其来的浓雾之后，村里几位老人总是在黄昏时分早早关紧木门，低声谈论着山谷深处传来的怪异回响。
        　　他站在旅店斜对面的旧报亭旁，看似随意地翻阅着泛黄的旧报纸，余光却始终留意着通往教堂的那条鹅卵石坡道。
        """
        let chapterThreeContent = """
        　　推开略显陈旧的橡木门时，门框上的铜铃发出清脆而短促的声响。
        　　壁炉里的松木正噼啪作响，橘红色的火光将墙面上几幅褪色的油画映照得明暗不定。坐在窗边的中年绅士放下了手中的银质茶匙，镜片后的目光平静而深邃。
        　　“你比约定的时间晚了两分钟，卢米安。”对方的声音低沉而温和，却莫名给人一种置身于教堂忏悔室般的压力。
        　　卢米安拉开木椅坐下，从风衣内袋取出那张折叠整齐的羊皮纸：“因为街口多出了几个陌生的面孔，我绕了两条街才确认没有尾巴。”
        """
        getChapterContentUseCase.saveChapterCache(
            content: chapterTwoContent,
            bookUrl: sampleBook.bookUrl,
            index: 1)
        getChapterContentUseCase.saveChapterCache(
            content: chapterThreeContent,
            bookUrl: sampleBook.bookUrl,
            index: 2)
    }
}
