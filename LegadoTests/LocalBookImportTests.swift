import Foundation
@testable import Legado
import Testing

@Suite("Local Import and TXT TOC Parser Suite")
struct LocalBookImportTests {
    @Test("Test TxtTocParser with Standard Chinese Chapters")
    func txtTocParserStandardChapters() {
        let sampleTxt = """
        这是小说前言说明。
        欢迎阅读本书！

        第一章 宿命之始
        清晨的阳光洒落在塔罗堡的窗棂上。
        周明缓缓睁开了双眼。

        第2章 诡秘的低语
        深夜的钟声敲响了十二下。
        耳边传来了未知的呓语。

        终章 归于平静
        一切纷争终于落下了帷幕。
        """

        let chapters = TxtTocParser.parse(text: sampleTxt)
        #expect(chapters.count == 4)

        #expect(chapters[0].title == "前言")
        #expect(chapters[0].index == 0)
        #expect(chapters[0].content.contains("这是小说前言说明"))

        #expect(chapters[1].title == "第一章 宿命之始")
        #expect(chapters[1].index == 1)
        #expect(chapters[1].content.contains("周明缓缓睁开了双眼"))

        #expect(chapters[2].title == "第2章 诡秘的低语")
        #expect(chapters[2].index == 2)
        #expect(chapters[2].content.contains("耳边传来了未知的呓语"))

        #expect(chapters[3].title == "终章 归于平静")
        #expect(chapters[3].index == 3)
        #expect(chapters[3].content.contains("一切纷争终于落下了帷幕"))
    }

    @Test("Test TxtTocParser Fallback Chunker for Non-Standard Text")
    func txtTocParserFallbackChunker() {
        let unstructuredText = String(repeating: "这是一段没有标准章节格式的文本内容。", count: 400)
        let chapters = TxtTocParser.parse(text: unstructuredText)
        #expect(!chapters.isEmpty)
        #expect(chapters[0].title.starts(with: "第 1 节") || chapters[0].title == "正文")
    }

    @Test("Test ImportLocalBookUseCase with Temporary TXT File")
    func importLocalBookUseCase() async throws {
        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)
        let cacheRepo = BookCacheRepositoryImpl()

        let useCase = ImportLocalBookUseCase(
            bookRepository: bookRepo,
            bookCacheRepository: cacheRepo)

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("[全本精校]诡秘之主(精校版).txt")

        let txtContent = """
        第一章 绯红
        痛！好痛！头好痛！
        第二章 仪式
        水银在地面上勾勒出诡秘的符号。
        """
        try txtContent.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let book = try await useCase.execute(fileUrl: tempFile)
        #expect(book.name == "诡秘之主")
        #expect(book.author == "本地导入")
        #expect(book.totalChapterNum == 2)

        let savedChapters = try await bookRepo.getChapters(for: book.bookUrl)
        #expect(savedChapters.count == 2)
        #expect(savedChapters[0].title == "第一章 绯红")
        #expect(savedChapters[1].title == "第二章 仪式")

        let cachedCh1 = cacheRepo.getCachedChapterContent(bookUrl: book.bookUrl, index: 0)
        #expect(cachedCh1?.contains("痛！好痛！头好痛！") == true)
    }

    @Test("Test ImportLocalBookUseCase with UTF-8 BOM, UTF-16 BOM and Unsupported Format")
    func importLocalBookEncodingsAndValidation() async throws {
        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)
        let tempCacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLocalImportCache_\(UUID().uuidString)", isDirectory: true)
        let cacheRepo = BookCacheRepositoryImpl(baseDirectory: tempCacheDir)
        defer { try? FileManager.default.removeItem(at: tempCacheDir) }

        let useCase = ImportLocalBookUseCase(
            bookRepository: bookRepo,
            bookCacheRepository: cacheRepo)

        // 1. UTF-8 BOM 文件首行章节识别
        let bomFile = FileManager.default.temporaryDirectory.appendingPathComponent("utf8_bom_test.txt")
        let bomData = Data([0xEF, 0xBB, 0xBF]) + Data("第一章 启程\n新的冒险开始了。\n".utf8)
        try bomData.write(to: bomFile)
        defer { try? FileManager.default.removeItem(at: bomFile) }

        let bomBook = try await useCase.execute(fileUrl: bomFile)
        let bomChapters = try await bookRepo.getChapters(for: bomBook.bookUrl)
        #expect(bomChapters.count == 1)
        #expect(bomChapters[0].title == "第一章 启程")

        // 2. UTF-16 LE BOM 文件解码
        let utf16File = FileManager.default.temporaryDirectory.appendingPathComponent("utf16_test.txt")
        if let utf16Data = "第一章 黎明\n微光穿透云层。".data(using: .utf16) {
            try utf16Data.write(to: utf16File)
            defer { try? FileManager.default.removeItem(at: utf16File) }
            let utf16Book = try await useCase.execute(fileUrl: utf16File)
            let utf16Chapters = try await bookRepo.getChapters(for: utf16Book.bookUrl)
            #expect(utf16Chapters.first?.title == "第一章 黎明")
        }

        // 3. 清空在线缓存时应保留本地书籍章节
        try cacheRepo.saveChapterContent(bookUrl: "https://online.example/book", index: 0, content: "在线缓存")
        try cacheRepo.clearAllCache()
        #expect(cacheRepo.getCachedChapterContent(bookUrl: "https://online.example/book", index: 0) == nil)
        #expect(cacheRepo.getCachedChapterContent(bookUrl: bomBook.bookUrl, index: 0)?.contains("新的冒险") == true)

        // 4. 非文本格式应抛出清晰错误
        let invalidFile = FileManager.default.temporaryDirectory.appendingPathComponent("not_a_book.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: invalidFile)
        defer { try? FileManager.default.removeItem(at: invalidFile) }

        var didThrowUnsupported = false
        do {
            _ = try await useCase.execute(fileUrl: invalidFile)
        } catch is LocalBookImportError {
            didThrowUnsupported = true
        }
        #expect(didThrowUnsupported)
    }

    @Test("Test ZipArchiveReader, EpubParser and ImportLocalBookUseCase with Stored EPUB")
    func importLocalEpubUseCase() async throws {
        let containerXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let contentOpf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>星辰大海</dc:title>
            <dc:creator>测试作者</dc:creator>
            <dc:description>一部本地 EPUB 测试小说。</dc:description>
          </metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="ch1"/>
            <itemref idref="ch2"/>
          </spine>
        </package>
        """
        let tocNcx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
          <navMap>
            <navPoint id="n1"><navLabel><text>第一章 启航</text></navLabel><content src="ch1.xhtml"/></navPoint>
            <navPoint id="n2"><navLabel><text>第二章 航线</text></navLabel><content src="ch2.xhtml"/></navPoint>
          </navMap>
        </ncx>
        """
        let ch1Html = "<html><body><h1>第一章 启航</h1><p>飞船缓缓离开港口。</p><p>星光洒满舷窗。</p></body></html>"
        let ch2Html = "<html><body><h1>第二章 航线</h1><p>跃迁引擎轰鸣启动。</p></body></html>"

        let epubData = Self.makeStoredZip(entries: [
            ("META-INF/container.xml", Data(containerXml.utf8)),
            ("OEBPS/content.opf", Data(contentOpf.utf8)),
            ("OEBPS/toc.ncx", Data(tocNcx.utf8)),
            ("OEBPS/ch1.xhtml", Data(ch1Html.utf8)),
            ("OEBPS/ch2.xhtml", Data(ch2Html.utf8)),
        ])

        let tempEpub = FileManager.default.temporaryDirectory.appendingPathComponent("test_book.epub")
        try epubData.write(to: tempEpub)
        defer { try? FileManager.default.removeItem(at: tempEpub) }

        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)
        let tempCacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestEpubCache_\(UUID().uuidString)", isDirectory: true)
        let cacheRepo = BookCacheRepositoryImpl(baseDirectory: tempCacheDir)
        defer { try? FileManager.default.removeItem(at: tempCacheDir) }

        let useCase = ImportLocalBookUseCase(bookRepository: bookRepo, bookCacheRepository: cacheRepo)
        let book = try await useCase.execute(fileUrl: tempEpub)

        #expect(book.name == "星辰大海")
        #expect(book.author == "测试作者")
        #expect(book.totalChapterNum == 2)
        #expect(book.isLocalFile == true)

        let chapters = try await bookRepo.getChapters(for: book.bookUrl)
        #expect(chapters.count == 2)
        #expect(chapters[0].title == "第一章 启航")
        #expect(chapters[1].title == "第二章 航线")

        let ch1Content = cacheRepo.getCachedChapterContent(bookUrl: book.bookUrl, index: 0)
        #expect(ch1Content?.contains("飞船缓缓离开港口") == true)
        #expect(ch1Content?.contains("星光洒满舷窗") == true)
    }

    private static func makeStoredZip(entries: [(String, Data)]) -> Data {
        var output = Data()
        var centralDir = Data()

        for (name, payload) in entries {
            let nameData = Data(name.utf8)
            let localOffset = UInt32(output.count)
            let size = UInt32(payload.count)

            output.appendLE(UInt32(0x0403_4B50))
            output.appendLE(UInt16(20))
            output.appendLE(UInt16(0))
            output.appendLE(UInt16(0))
            output.appendLE(UInt16(0))
            output.appendLE(UInt16(0))
            output.appendLE(UInt32(0))
            output.appendLE(size)
            output.appendLE(size)
            output.appendLE(UInt16(nameData.count))
            output.appendLE(UInt16(0))
            output.append(nameData)
            output.append(payload)

            centralDir.appendLE(UInt32(0x0201_4B50))
            centralDir.appendLE(UInt16(20))
            centralDir.appendLE(UInt16(20))
            centralDir.appendLE(UInt16(0))
            centralDir.appendLE(UInt16(0))
            centralDir.appendLE(UInt16(0))
            centralDir.appendLE(UInt16(0))
            centralDir.appendLE(UInt32(0))
            centralDir.appendLE(size)
            centralDir.appendLE(size)
            centralDir.appendLE(UInt16(nameData.count))
            centralDir.appendLE(UInt16(0))
            centralDir.appendLE(UInt16(0))
            centralDir.appendLE(UInt16(0))
            centralDir.appendLE(UInt16(0))
            centralDir.appendLE(UInt32(0))
            centralDir.appendLE(localOffset)
            centralDir.append(nameData)
        }

        let cdOffset = UInt32(output.count)
        let cdSize = UInt32(centralDir.count)
        output.append(centralDir)

        output.appendLE(UInt32(0x0605_4B50))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt16(entries.count))
        output.appendLE(cdSize)
        output.appendLE(cdOffset)
        output.appendLE(UInt16(0))
        return output
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
