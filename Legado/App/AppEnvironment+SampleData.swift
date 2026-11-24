import Foundation

// MARK: - AppEnvironment 示例数据初始化扩展

extension AppEnvironment {
    func seedSampleBookshelfIfNeeded() async {
        let books = (try? await bookRepository.getBookshelf()) ?? []
        guard books.isEmpty else {
            UserDefaults.standard.set(true, forKey: Self.sampleSeededDefaultsKey)
            return
        }
        if UserDefaults.standard.bool(forKey: Self.sampleSeededDefaultsKey),
           !ProcessInfo.processInfo.arguments.contains("--open-reader-demo"),
           !ProcessInfo.processInfo.arguments.contains("--open-reader-hud") {
            return
        }
        UserDefaults.standard.set(true, forKey: Self.sampleSeededDefaultsKey)

        let sampleBookUrl = "local://sample/circle_of_inevitability"
        let sampleBook = Book(
            bookUrl: sampleBookUrl,
            tocUrl: "",
            origin: "local",
            originName: "内置试读",
            name: "宿命之环",
            author: "爱潜水的乌贼",
            kind: "奇幻 试读",
            coverUrl: nil,
            intro: "诡秘之主第二部。四旬节的前夜，微风轻拂的夜晚，卢米安站在崖顶，眺望着科尔杜村...",
            latestChapterTitle: "第三章 恶作剧与神秘客",
            durChapterTitle: "第一章 宿命之始",
            durChapterIndex: 0,
            wordCount: "285万字",
            totalChapterNum: 3)
        try? await bookRepository.saveBook(sampleBook)

        let chapters = [
            Chapter(url: "\(sampleBookUrl)/0", title: "第一章 宿命之始", bookUrl: sampleBookUrl, index: 0),
            Chapter(url: "\(sampleBookUrl)/1", title: "第二章 科尔杜村的阴影", bookUrl: sampleBookUrl, index: 1),
            Chapter(url: "\(sampleBookUrl)/2", title: "第三章 恶作剧与神秘客", bookUrl: sampleBookUrl, index: 2),
        ]
        try? await bookRepository.saveChapters(chapters, for: sampleBookUrl)
        seedSampleChaptersContent(for: sampleBookUrl)
        notifyBookshelfNeedsRefresh()
    }

    private func seedSampleChaptersContent(for bookUrl: String) {
        let sampleContent = """
        　　夜幕降临，微凉的晚风吹拂过荒野，带来了远处不知名野兽的低沉吼声。
        　　卢米安站在高耸的崖壁顶端，俯瞰着下方若隐若现的村落灯火。在这个充满神秘与超凡的世界里，每一个看似宁静的黑夜背后，都潜藏着凡人难以窥见的波诡云谲。
        　　他下意识地摸了摸胸前的银质吊坠，冰冷的金属触感让他狂躁的心绪稍微平复了一些。根据那位神秘女士的指引，只要在特定的星象下完成仪式，就能真正迈入第一序列。
        　　但仪式所需要的祭品并不简单，除了罕见的灵界生物毛发，还需要一份真正直面疯狂与恐惧的勇气。
        　　狂风渐起，天空中厚重的铅云缓缓移动，露出了那一弯猩红如血的残月。命运的齿轮，已在此刻悄然转动。
        　　“时间差不多了。”卢米安低声自语，转身踏上了通往古老遗迹的荒凉小道。
        """

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
        getChapterContentUseCase.saveChapterCache(content: sampleContent, bookUrl: bookUrl, index: 0)
        getChapterContentUseCase.saveChapterCache(content: chapterTwoContent, bookUrl: bookUrl, index: 1)
        getChapterContentUseCase.saveChapterCache(content: chapterThreeContent, bookUrl: bookUrl, index: 2)
    }
}
