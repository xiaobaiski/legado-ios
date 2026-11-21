import CoreGraphics
import Foundation
@testable import Legado
import SwiftUI
import Testing
import UIKit

@Suite("Reader Engine Suite")
struct ReaderEngineTests {
    @Test("Test ContentParser Text Cleaning and Chinese Indentation")
    func contentParserCleaning() {
        let parser = ContentParser.shared
        let rawHtmlContent = """
        <p>第一段：这里是小说正文内容。<br/>中间包含了换行标签。</p>
        <div>第二段：&nbsp;&nbsp;包含HTML实体 &quot;引号&quot; 和 &amp; 符号。</div>
        <script>alert("ad");</script>
        <p>第三段：最后一段内容。</p>
        """

        let cleaned = parser.cleanContent(rawHtmlContent)

        // 验证标签已被清理
        #expect(!cleaned.contains("<p>"))
        #expect(!cleaned.contains("</p>"))
        #expect(!cleaned.contains("<br/>"))
        #expect(!cleaned.contains("alert"))

        // 验证实体替换
        #expect(cleaned.contains("\"引号\""))
        #expect(cleaned.contains("&"))

        // 验证中文首行缩进
        let lines = cleaned.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        #expect(lines.count == 4)
        for line in lines {
            #expect(line.hasPrefix("\u{3000}\u{3000}"))
        }
    }

    @Test("Test TextLayoutEngine CoreText Pagination")
    func textLayoutEnginePagination() {
        let engine = TextLayoutEngine.shared
        let sampleText = """
        　　夜幕降临，微凉的晚风吹拂过荒野，带来了远处不知名野兽的低沉吼声。
        　　卢米安站在高耸的崖壁顶端，俯瞰着下方若隐若现的村落灯火。在这个充满神秘与超凡的世界里，每一个看似宁静的黑夜背后，都潜藏着凡人难以窥见的波诡云谲。
        　　他下意识地摸了摸胸前的银质吊坠，冰冷的金属触感让他狂躁的心绪稍微平复了一些。根据那位神秘女士的指引，只要在特定的星象下完成仪式，就能真正迈入第一序列。
        　　但仪式所需要的祭品并不简单，除了罕见的灵界生物毛发，还需要一份真正直面疯狂与恐惧的勇气。
        　　狂风渐起，天空中厚重的铅云缓缓移动，露出了那一弯猩红如血的残月。命运的齿轮，已在此刻悄然转动。
        """

        var config = ReaderConfig.defaultConfig
        config.fontSize = 18
        config.lineSpacing = 6

        // 模拟标准 iPhone 屏幕尺寸排版容器 (宽360, 高600)
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 600)
        let pages = engine.paginate(
            chapterTitle: "第一章 宿命之始",
            content: sampleText,
            chapterIndex: 0,
            bounds: bounds,
            config: config)

        #expect(!pages.isEmpty)
        #expect(pages.count >= 1)

        for (index, page) in pages.enumerated() {
            #expect(page.pageIndex == index)
            #expect(!page.contentText.isEmpty)
            #expect(page.textRange.length > 0)
        }

        // 验证第一页文本与起始字符一致
        if let firstPage = pages.first {
            #expect(firstPage.contentText.contains("夜幕降临"))
        }
    }

    @Test("Test ReaderConfig Theme and Adjustments")
    func readerConfigThemeAndAdjustments() {
        var config = ReaderConfig.defaultConfig
        #expect(config.fontSize == 19)
        #expect(config.theme == .paper)

        // 调整字号
        config.fontSize += 2
        #expect(config.fontSize == 21)

        // 切换主题
        config.theme = .dark
        #expect(config.theme.isDark == true)
        #expect(config.theme.backgroundColor == Color(red: 0.14, green: 0.14, blue: 0.16))

        // 翻页动效模式验证与切换
        #expect(config.pageTurnMode == .cover)
        config.pageTurnMode = .curl
        #expect(config.pageTurnMode == .curl)
        config.pageTurnMode = .slide
        #expect(config.pageTurnMode == .slide)
        config.pageTurnMode = .scroll
        #expect(config.pageTurnMode == .scroll)

        // 音量键翻页配置默认值与编解码验证
        #expect(config.volumeKeyPageTurn == true)
        config.volumeKeyPageTurn = false
        if let encoded = try? JSONEncoder().encode(config),
           let decoded = try? JSONDecoder().decode(ReaderConfig.self, from: encoded) {
            #expect(decoded.volumeKeyPageTurn == false)
            #expect(decoded.pageTurnMode == .scroll)
        } else {
            Issue.record("ReaderConfig JSON 编解码失败")
        }
    }

    @Test("Test ReaderState Page Navigation Logic")
    func readerStateNavigation() {
        let dummyBook = Book(
            bookUrl: "https://example.com/book/1",
            origin: "https://example.com",
            name: "测试阅读书籍",
            author: "测试作者")

        var state = ReaderState(book: dummyBook, currentChapterIndex: 0)
        #expect(state.currentPageIndex == 0)
        #expect(state.currentPage == nil)

        // 模拟填入页面
        let page1 = ReaderPage(
            pageIndex: 0,
            chapterIndex: 0,
            chapterTitle: "第一章",
            textRange: NSRange(location: 0, length: 2),
            contentText: "页1")
        let page2 = ReaderPage(
            pageIndex: 1,
            chapterIndex: 0,
            chapterTitle: "第一章",
            textRange: NSRange(location: 2, length: 2),
            contentText: "页2")
        state.pages = [page1, page2]

        #expect(state.currentPage?.contentText == "页1")

        state.currentPageIndex = 1
        #expect(state.currentPage?.contentText == "页2")
    }

    @Test("Test ReaderConfigStore Persistence and Repagination Detection")
    func readerConfigPersistenceAndRepagination() {
        let suiteName = "legado_reader_test_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var config = ReaderConfig.defaultConfig
        config.fontSize = 22
        config.lineSpacing = 14
        config.paragraphSpacing = 20
        config.letterSpacing = 1.5
        config.paragraphIndent = 0
        config.isBoldFont = true
        config.customFontName = "PingFangSC-Regular"
        config.customFontDisplayName = "苹方简体"
        config.isHapticEnabled = false
        config.leftHandMode = true
        config.tapZoneConfig = .rightHanded
        config.chineseConversion = .toTraditional

        ReaderConfigStore.save(config, defaults: defaults)
        let loaded = ReaderConfigStore.load(defaults: defaults)
        #expect(loaded == config)
        #expect(loaded.isHapticEnabled == false)
        #expect(loaded.paragraphSpacing == 20)
        #expect(loaded.lineSpacing == 14)

        // 仅切换震动开关不应触发重排
        var hapticOnly = loaded
        hapticOnly.isHapticEnabled = true
        #expect(!hapticOnly.requiresRepagination(comparedTo: loaded))

        // 调整段距应触发重排
        var spacingChanged = loaded
        spacingChanged.paragraphSpacing = 28
        #expect(spacingChanged.requiresRepagination(comparedTo: loaded))

        let reset = ReaderConfigStore.reset(defaults: defaults)
        #expect(reset == .defaultConfig)
    }

    @Test("Test Night Mode Memory, 3x3 TapZone Customization and Real System Fonts")
    func nightModeTapZonesAndRealFonts() throws {
        // 1. 夜间模式切换自动记忆日间与夜间主题
        var config = ReaderConfig.defaultConfig
        config.applyTheme(.eyeCare)
        #expect(config.theme == .eyeCare)
        #expect(config.lastLightTheme == .eyeCare)

        config.toggleNightMode()
        #expect(config.theme.isDark)
        config.applyTheme(.black)
        #expect(config.lastDarkTheme == .black)

        config.toggleNightMode()
        #expect(config.theme == .eyeCare)
        config.toggleNightMode()
        #expect(config.theme == .black)

        // 2. 九宫格自定义点按区域坐标解析与预设校验
        var tapConfig = TapZoneConfig.rightHanded
        #expect(tapConfig.action(atXRatio: 0.1, yRatio: 0.1) == .prevPage)
        #expect(tapConfig.action(atXRatio: 0.5, yRatio: 0.5) == .toggleHUD)
        #expect(tapConfig.action(atXRatio: 0.5, yRatio: 0.9) == .nextPage)
        #expect(tapConfig.action(atXRatio: 0.9, yRatio: 0.2) == .nextPage)

        tapConfig.setAction(.toggleNightMode, row: 0, col: 2)
        #expect(tapConfig.action(atXRatio: 0.9, yRatio: 0.1) == .toggleNightMode)

        // 3. 兼容旧版宋体/楷体配置反序列化回退至系统默认，并校验设备真实字体枚举非空
        let legacyFontJson = Data("\"宋体\"".utf8)
        let decodedLegacy = try JSONDecoder().decode(ReaderFontFamily.self, from: legacyFontJson)
        #expect(decodedLegacy == .system)

        let deviceFonts = LocalFontManager.shared.listAvailableSystemFonts()
        #expect(!deviceFonts.isEmpty)
        for font in deviceFonts.prefix(10) {
            #expect(UIFont(name: font.postScriptName, size: 16) != nil)
        }
    }

    @Test("Test TextLayoutEngine Indent, Spacing and Chinese Conversion")
    func textLayoutTypographyControls() {
        let engine = TextLayoutEngine.shared
        let raw = "  第一段文字内容。\n　　第二段简体阅读测试。"

        var noIndentConfig = ReaderConfig.defaultConfig
        noIndentConfig.paragraphIndent = 0
        let noIndentText = engine.normalizeContent(raw, config: noIndentConfig)
        #expect(noIndentText == "第一段文字内容。\n第二段简体阅读测试。")

        var twoIndentConfig = ReaderConfig.defaultConfig
        twoIndentConfig.paragraphIndent = 2
        twoIndentConfig.chineseConversion = .toTraditional
        let traditionalText = engine.normalizeContent(raw, config: twoIndentConfig)
        #expect(traditionalText.hasPrefix("\u{3000}\u{3000}"))
        #expect(traditionalText.contains("簡體閱讀測試") || traditionalText.contains("閱讀"))

        // 验证增大段距与行距后，相同文本所需页数增加或不少于紧凑排版
        let longText = Array(repeating: "这是一段用于验证行距与段距排版效果的正文测试段落。", count: 35)
            .joined(separator: "\n")
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 500)

        var compact = ReaderConfig.defaultConfig
        compact.lineSpacing = 2
        compact.paragraphSpacing = 4

        var spacious = ReaderConfig.defaultConfig
        spacious.lineSpacing = 18
        spacious.paragraphSpacing = 26

        let compactPages = engine.paginate(
            chapterTitle: "测试",
            content: longText,
            chapterIndex: 0,
            bounds: bounds,
            config: compact)
        let spaciousPages = engine.paginate(
            chapterTitle: "测试",
            content: longText,
            chapterIndex: 0,
            bounds: bounds,
            config: spacious)
        #expect(spaciousPages.count > compactPages.count)
    }

    @Test("Test iPad Dual-Page Layout Calculation and LocalFontManager Validation")
    func iPadLayoutAndLocalFontValidation() {
        let engine = TextLayoutEngine.shared
        let iPhoneBounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let iPadPortraitBounds = CGRect(x: 0, y: 0, width: 820, height: 1180)
        let iPadBounds = CGRect(x: 0, y: 0, width: 1024, height: 768)

        var config = ReaderConfig.defaultConfig
        config.enableIPadDualPage = true

        #expect(!config.isDualPageActive(for: iPhoneBounds))
        // iPad 竖屏采用单页、横屏自动启用双页并排
        #expect(!config.isDualPageActive(for: iPadPortraitBounds))
        #expect(config.isDualPageActive(for: iPadBounds))

        // 验证独立左边距、右边距在 iPad 竖屏和横屏均严格即时生效（无隐藏宽度上限拦截）
        config.leftMargin = 20
        config.rightMargin = 40
        let portraitRect = engine.contentRenderRect(for: iPadPortraitBounds, config: config)
        #expect(portraitRect.width == iPadPortraitBounds.width - 60)

        // iPad 双页单栏宽度应严格等于 (宽 - 32中缝) / 2 - leftMargin - rightMargin
        let dualRect = engine.contentRenderRect(for: iPadBounds, config: config)
        #expect(dualRect.width == (iPadBounds.width - 32) / 2 - 60)

        config.enableIPadDualPage = false
        let singleWideRect = engine.contentRenderRect(for: iPadBounds, config: config)
        #expect(singleWideRect.width == iPadBounds.width - 60)

        // 验证自动翻页上下滚动模式与旧版 horizontalMargin 迁移兼容
        let legacyJson = Data("{\"horizontalMargin\": 26}".utf8)
        if let migrated = try? JSONDecoder().decode(ReaderConfig.self, from: legacyJson) {
            #expect(migrated.leftMargin == 26)
            #expect(migrated.rightMargin == 26)
        } else {
            Issue.record("旧版 horizontalMargin 反序列化迁移失败")
        }
        config.autoPageMode = .smoothScroll
        config.autoScrollSpeed = 75
        if let encoded = try? JSONEncoder().encode(config),
           let decoded = try? JSONDecoder().decode(ReaderConfig.self, from: encoded) {
            #expect(decoded.autoPageMode == .smoothScroll)
            #expect(decoded.autoScrollSpeed == 75)
            #expect(decoded.leftMargin == 20)
            #expect(decoded.rightMargin == 40)
        } else {
            Issue.record("AutoPageMode 与左右边距编解码失败")
        }

        // 验证 LocalFontManager 对非法格式的校验
        let tempFontsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestFonts_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempFontsDir) }
        let manager = LocalFontManager(fontsDirectory: tempFontsDir)
        #expect(manager.listImportedFonts().isEmpty)

        let badExtFile = FileManager.default.temporaryDirectory.appendingPathComponent("bad_font.txt")
        try? Data("not a font".utf8).write(to: badExtFile)
        defer { try? FileManager.default.removeItem(at: badExtFile) }

        var caughtUnsupported = false
        do {
            _ = try manager.importFont(from: badExtFile)
        } catch is LocalFontImportError {
            caughtUnsupported = true
        } catch {}
        #expect(caughtUnsupported)
    }

    @Test("Test Chapter Title Layout, 6-Slot Header/Footer, Custom Theme and Reading Options")
    func legadoReadingStyleExtensions() throws {
        let engine = TextLayoutEngine.shared
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)

        // 1. 正文章节大标题开启时第 0 页包含标题前缀，隐藏时为 0
        var config = ReaderConfig.defaultConfig
        config.titleStyle = ChapterTitleStyleConfig(alignment: .center, sizeDelta: 6, topSpacing: 12, bottomSpacing: 18)
        let withTitlePages = engine.paginate(
            chapterTitle: "第一章 星海启航",
            content: "正文第一段内容，用来验证正文章节大标题渲染。",
            chapterIndex: 0,
            bounds: bounds,
            config: config)
        #expect((withTitlePages.first?.titlePrefixLength ?? 0) > 0)
        #expect(withTitlePages.first?.contentText.hasPrefix("第一章 星海启航") == true)

        config.titleStyle.alignment = .hidden
        let hiddenTitlePages = engine.paginate(
            chapterTitle: "第一章 星海启航",
            content: "正文第一段内容，用来验证正文章节大标题隐藏。",
            chapterIndex: 0,
            bounds: bounds,
            config: config)
        #expect(hiddenTitlePages.first?.titlePrefixLength == 0)
        #expect(hiddenTitlePages.first?.contentText.hasPrefix("第一章 星海启航") == false)

        // 2. 自定义十六进制配色与亮度暗色识别
        #expect(HexColorCodec.isDarkColor(hex: "#16202C") == true)
        #expect(HexColorCodec.isDarkColor(hex: "#F7ECD8") == false)
        config.customBackgroundHex = "#16202C"
        config.customTextHex = "#C7D3E0"
        config.applyTheme(.custom)
        #expect(config.isEffectiveDark == true)

        // 3. 6 槽位页眉页脚、字重、常亮时长、进度条行为与护眼滤镜完整编解码
        config.tipConfig = HeaderFooterTipConfig(
            headerLeft: .bookTitle,
            headerCenter: .chapterTitle,
            headerRight: .battery,
            footerLeft: .chapterIndex,
            footerCenter: .remainingPages,
            footerRight: .bookProgress,
            tipFontSize: 12)
        config.fontWeight = .medium
        config.keepScreenOnDuration = .minutes10
        config.progressBarBehavior = .page
        config.eyeProtectionWarmth = 0.25

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ReaderConfig.self, from: encoded)
        #expect(decoded.tipConfig == config.tipConfig)
        #expect(decoded.fontWeight == .medium)
        #expect(decoded.keepScreenOnDuration == .minutes10)
        #expect(decoded.progressBarBehavior == .page)
        #expect(decoded.eyeProtectionWarmth == 0.25)
    }
}
