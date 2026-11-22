import AVFoundation
import Foundation
@testable import Legado
import SwiftData
import Testing

@Suite("TTS and WebDAV Cloud Sync Suite")
struct TTSAndWebDAVSyncTests {

    // MARK: - 文本净化与规则测试

    @Test("Test Purify Content Removes Ads and Page Turn Prompts")
    func purifyContentRemovesAds() {
        let purifyUseCase = PurifyContentUseCase()
        let rawContent = """
        　　夜幕降临，风吹过荒野。
        本章未完，请点击下一页继续阅读！
        笔趣阁最快更新！关注网址 https://ad.example.com/promo
        　　卢米安握紧了手中的吊坠。
        """

        let cleaned = purifyUseCase.execute(content: rawContent)
        #expect(!cleaned.contains("本章未完"))
        #expect(!cleaned.contains("https://ad.example.com"))
        #expect(!cleaned.contains("最快更新"))
        #expect(cleaned.contains("夜幕降临"))
        #expect(cleaned.contains("卢米安握紧"))
    }

    @Test("Test Custom User Regex Replacement Rule")
    func customUserRegexRule() {
        let purifyUseCase = PurifyContentUseCase()
        let rawContent = "错别字【乌贼】与特定标记【VIP】"
        let customRule = ReplaceRule(
            name: "标记替换",
            pattern: "【VIP】",
            replacement: "[精品]")

        let cleaned = purifyUseCase.execute(
            content: rawContent,
            customRules: [customRule])

        #expect(cleaned.contains("[精品]"))
        #expect(!cleaned.contains("【VIP】"))
    }

    // MARK: - 朗读断句与状态机测试

    @Test("Test TTS Sentence Splitting and Normalization")
    @MainActor
    func ttsSentenceSplitting() {
        let player = TTSPlayer.shared
        player.stop()

        let sampleText = """
        夜幕降临！荒野的风在呼啸？
        卢米安低语：“开始吧。”
        命运的齿轮转动了。
        """

        player.startReading(
            content: sampleText,
            bookTitle: "宿命之环",
            chapterTitle: "第一章",
            author: "爱潜水的乌贼")

        #expect(player.totalSentences >= 3)
        #expect(player.state == .playing)
        #expect(player.currentSentenceIndex == 0)

        // 测试暂停与恢复
        player.pause()
        #expect(player.state == .paused)

        player.resume()
        #expect(player.state == .playing)

        player.stop()
        #expect(player.state == .idle)
    }

    @Test("Test TTS Rate and Sleep Timer Adjustments")
    @MainActor
    func ttsRateAndTimer() {
        let player = TTSPlayer.shared
        player.speechRate = 0.55
        player.speechPitch = 1.2

        #expect(player.speechRate == 0.55)
        #expect(player.speechPitch == 1.2)

        player.setSleepTimer(minutes: 15)
        #expect(player.timerRemainingSeconds == 15 * 60)

        player.clearSleepTimer()
        #expect(player.timerRemainingSeconds == nil)
    }

    // MARK: - WebDAV 序列化与备份恢复测试

    @Test("Test WebDAV Config Validation")
    func webDAVConfigValidation() {
        var config = WebDAVConfig()
        #expect(!config.isValid)

        config.serverUrl = "https://dav.jianguoyun.com/dav/"
        config.username = "test@example.com"
        config.password = "app-password"
        #expect(config.isValid)
    }

    @Test("Test WebDAV Backup Bundle Serialization Roundtrip")
    func webDAVBundleSerialization() throws {
        let sampleBook = Book(
            bookUrl: "https://example.com/b1",
            tocUrl: "https://example.com/toc1",
            origin: "https://example.com",
            originName: "测试源",
            name: "诡秘之主",
            author: "乌贼")

        let sampleSource = BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "测试源",
            bookSourceType: 0)

        let bundle = WebDAVBackupBundle(
            version: 1,
            backupTime: Date(),
            appVersion: "1.0.0",
            books: [sampleBook],
            sources: [sampleSource],
            replaceRules: PurifyContentUseCase.defaultRules)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(WebDAVBackupBundle.self, from: data)

        #expect(restored.version == 1)
        #expect(restored.books.count == 1)
        #expect(restored.books.first?.name == "诡秘之主")
        #expect(restored.sources.count == 1)
        #expect(restored.sources.first?.bookSourceName == "测试源")
        #expect(!restored.replaceRules.isEmpty)
    }

    @Test("Test WebDAV URL Normalization, Scheme Upgrade and Chinese Directory Encoding")
    func webDAVUrlNormalizationAndEncoding() {
        #expect(WebDAVClient.normalizeBaseUrl("davs://dav.jianguoyun.com/dav")?.absoluteString
            == "https://dav.jianguoyun.com/dav/")
        #expect(WebDAVClient.normalizeBaseUrl("dav://192.168.1.50:5244/dav")?.absoluteString
            == "http://192.168.1.50:5244/dav/")
        #expect(WebDAVClient.normalizeBaseUrl("dav.jianguoyun.com/dav/")?.absoluteString
            == "https://dav.jianguoyun.com/dav/")
        #expect(WebDAVClient.normalizeBaseUrl("192.168.31.100:5244/dav")?.absoluteString
            == "http://192.168.31.100:5244/dav/")
        #expect(WebDAVClient.normalizeBaseUrl("nas.local/webdav")?.absoluteString
            == "http://nas.local/webdav/")
        #expect(WebDAVClient.normalizeBaseUrl("  https://example.com/dav  ")?.absoluteString
            == "https://example.com/dav/")
        #expect(WebDAVClient.normalizeBaseUrl("   ") == nil)

        let emptyConfig = WebDAVConfig(serverUrl: "  ")
        #expect(!emptyConfig.isValid)

        let anonymousLanConfig = WebDAVConfig(serverUrl: "http://192.168.1.5:5244/dav")
        #expect(anonymousLanConfig.isValid)

        let segments = WebDAVClient.remotePathSegments(from: "/阅读备份/Legado/")
        #expect(segments == ["阅读备份", "Legado"])
        let fileUrl = WebDAVClient.buildUrl(
            base: "http://192.168.1.5:5244/dav",
            pathSegments: segments + ["legado_backup.json"],
            isDirectory: false)
        #expect(fileUrl != nil)
        #expect(fileUrl?.lastPathComponent == "legado_backup.json")
    }

    @Test("Test WebDAVConfig Backward Compatible Decoding")
    func webDAVConfigBackwardCompatibility() throws {
        let legacyJson = """
        {
          "serverUrl": "https://dav.jianguoyun.com/dav/",
          "username": "user@example.com",
          "password": "secret",
          "remoteDirectory": "/Legado/"
        }
        """
        let decoded = try JSONDecoder().decode(WebDAVConfig.self, from: Data(legacyJson.utf8))
        #expect(decoded.serverUrl == "https://dav.jianguoyun.com/dav/")
        #expect(decoded.allowInsecureCertificate == false)
        #expect(decoded.isValid)
    }

    @Test("Test WebDAVClient Connection Fallback, Nested MKCOL and Upload/Download")
    func webDAVClientMockSessionProtocol() async throws {
        let session = MockWebDAVURLProtocol.makeSession()

        // 1. 标准 PROPFIND Depth: 0 验证 XML 请求体与认证头
        let hostA = "mock-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: hostA) { request in
            #expect(request.httpMethod == "PROPFIND")
            #expect(request.value(forHTTPHeaderField: "Depth") == "0")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("application/xml") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
            let bodyStr = String(data: MockWebDAVURLProtocol.readBody(from: request), encoding: .utf8) ?? ""
            #expect(bodyStr.contains("propfind"))
            let resp = HTTPURLResponse(url: request.url!, statusCode: 207, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        defer { MockWebDAVURLProtocol.unregister(host: hostA) }

        let client = WebDAVClient(urlSession: session)
        let configA = WebDAVConfig(serverUrl: "https://\(hostA)/dav/", username: "alice", password: "pw")
        #expect(try await client.testConnection(config: configA))

        // 2. Depth: 0 返回 405 时自动降级至 Depth: 1 / OPTIONS
        let hostB = "mock-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: hostB) { request in
            let code = request.httpMethod == "OPTIONS" ? 200 : 405
            let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        defer { MockWebDAVURLProtocol.unregister(host: hostB) }

        let configB = WebDAVConfig(serverUrl: "https://\(hostB)/dav/")
        #expect(try await client.testConnection(config: configB))

        // 3. 多级目录逐级 MKCOL + PUT + GET 往返
        let hostC = "mock-\(UUID().uuidString.lowercased()).local"
        let recorder = MockWebDAVRecorder()
        MockWebDAVURLProtocol.register(host: hostC) { request in
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? ""
            recorder.append(method: method, path: path)

            if method == "MKCOL" {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
                return (resp, Data())
            }
            if method == "PUT" {
                recorder.setStoredData(MockWebDAVURLProtocol.readBody(from: request))
                let resp = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
                return (resp, Data())
            }
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, recorder.getStoredData())
        }
        defer { MockWebDAVURLProtocol.unregister(host: hostC) }

        let configC = WebDAVConfig(
            serverUrl: "https://\(hostC)/dav/",
            username: "bob",
            password: "secret",
            remoteDirectory: "/Backup/Legado/")
        let payload = Data("{\"hello\":\"webdav\"}".utf8)
        try await client.upload(data: payload, filename: "legado_backup.json", config: configC)
        let downloaded = try await client.download(filename: "legado_backup.json", config: configC)
        #expect(downloaded == payload)
        let calls = recorder.snapshotCalls()
        #expect(calls.contains("MKCOL:/dav/Backup/"))
        #expect(calls.contains("MKCOL:/dav/Backup/Legado/"))
        #expect(calls.contains("PUT:/dav/Backup/Legado/legado_backup.json"))
        #expect(calls.contains("GET:/dav/Backup/Legado/legado_backup.json"))

        // 4. 常见 URLError 映射为明确中文诊断
        let hostErr = WebDAVClient.mapNetworkError(
            URLError(.cannotConnectToHost),
            url: URL(string: "http://192.168.1.5:5244/dav/"))
        #expect(hostErr.errorDescription?.contains("-1004") == true)
        let tlsErr = WebDAVClient.mapNetworkError(
            URLError(.serverCertificateUntrusted),
            url: URL(string: "https://nas.local:5006/"))
        #expect(tlsErr.errorDescription?.contains("允许自签名证书") == true)
    }

    @Test("Test Full WebDAV Backup and Restore Includes Rules, Records and ReaderConfig")
    func webDAVFullBackupAndRestoreWithRulesAndConfig() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebDAVBackupTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteA = "test.webdav.cfg.a.\(UUID().uuidString)"
        let suiteB = "test.webdav.cfg.b.\(UUID().uuidString)"
        let defaultsA = UserDefaults(suiteName: suiteA)!
        let defaultsB = UserDefaults(suiteName: suiteB)!
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }

        let replaceStoreA = ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_a.json"))
        let replaceStoreB = ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_b.json"))
        let tocStoreA = TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_a.json"))
        let tocStoreB = TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_b.json"))
        let recordStoreA = ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_a.json"))
        let recordStoreB = ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_b.json"))

        _ = replaceStoreA.upsert(ReplaceRule(name: "自定义净化", pattern: "BAD_AD", replacement: ""))
        _ = tocStoreA.upsert(TxtTocRule(id: 999, name: "自定义分章", rule: "^第\\d+节", enable: true))
        recordStoreA.recordSession(bookName: "测试书", bookAuthor: "作者", durationSeconds: 3600)

        var customConfig = ReaderConfig.defaultConfig
        customConfig.fontSize = 24
        customConfig.theme = .eyeCare
        ReaderConfigStore.save(customConfig, defaults: defaultsA)

        let providerA = ModelContainerProvider(inMemory: true)
        let bookRepoA = BookRepositoryImpl(modelContainer: providerA.container)
        let sourceRepoA = BookSourceRepositoryImpl(modelContainer: providerA.container)
        try await bookRepoA.saveBook(Book(
            bookUrl: "local://test-b1",
            origin: "local",
            originName: "本地书籍",
            name: "测试书",
            author: "作者",
            durChapterTitle: "第12章",
            durChapterIndex: 11,
            durChapterPos: 345))

        let backupUseCase = BackupToWebDAVUseCase(
            bookRepository: bookRepoA,
            sourceRepository: sourceRepoA,
            replaceRuleStore: replaceStoreA,
            txtTocRuleStore: tocStoreA,
            readRecordStore: recordStoreA,
            readerConfigExporter: { ReaderConfigStore.exportJSON(defaults: defaultsA) })

        let bundle = try await backupUseCase.generateBackupBundle()
        let data = try backupUseCase.exportBackupJsonData(bundle: bundle)

        let providerB = ModelContainerProvider(inMemory: true)
        let bookRepoB = BookRepositoryImpl(modelContainer: providerB.container)
        let sourceRepoB = BookSourceRepositoryImpl(modelContainer: providerB.container)
        let restoreUseCase = RestoreFromWebDAVUseCase(
            bookRepository: bookRepoB,
            sourceRepository: sourceRepoB,
            replaceRuleStore: replaceStoreB,
            txtTocRuleStore: tocStoreB,
            readRecordStore: recordStoreB,
            readerConfigImporter: { _ = ReaderConfigStore.importJSON($0, defaults: defaultsB) })

        let summary = try await restoreUseCase.restore(from: data)
        #expect(summary.bookCount == 1)

        let restoredBook = try await bookRepoB.getBook(by: "local://test-b1")
        #expect(restoredBook?.durChapterIndex == 11)
        #expect(restoredBook?.durChapterPos == 345)
        #expect(replaceStoreB.loadRules().contains(where: { $0.name == "自定义净化" }))
        #expect(tocStoreB.loadRules().contains(where: { $0.name == "自定义分章" }))
        #expect(recordStoreB.allRecordsSorted().first?.readTimeSeconds == 3600)

        let restoredConfig = ReaderConfigStore.load(defaults: defaultsB)
        #expect(restoredConfig.fontSize == 24)
        #expect(restoredConfig.theme == .eyeCare)
    }

    @Test("Test Local Book Detail Progress Refresh and Cache Size Isolation")
    func localBookDetailRefreshAndCacheSizeIsolation() async throws {
        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)
        let sourceRepo = BookSourceRepositoryImpl(modelContainer: provider.container)

        let originalBook = Book(
            bookUrl: "local://progress-book",
            origin: "local",
            originName: "本地书籍",
            name: "本地进度书",
            author: "本地导入",
            durChapterTitle: "第一章",
            durChapterIndex: 0)
        try await bookRepo.saveBook(originalBook)

        var updatedBook = originalBook
        updatedBook.durChapterIndex = 5
        updatedBook.durChapterTitle = "第六章"
        try await bookRepo.saveBook(updatedBook)

        let detailUseCase = GetBookDetailUseCase(sourceRepository: sourceRepo, bookRepository: bookRepo)
        let fetched = try await detailUseCase.execute(book: originalBook)
        #expect(fetched.durChapterIndex == 5)
        #expect(fetched.durChapterTitle == "第六章")

        let tempCacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestIsolation_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempCacheDir) }
        let cacheRepo = BookCacheRepositoryImpl(baseDirectory: tempCacheDir)

        try cacheRepo.saveChapterContent(bookUrl: "local://progress-book", index: 0, content: "本地正文不应计入在线缓存")
        let onlineUrl = "https://online.example.com/b1"
        try cacheRepo.saveChapterContent(bookUrl: onlineUrl, index: 0, content: "在线缓存正文内容")

        let expectedOnlineSize = cacheRepo.calculateBookCacheSize(bookUrl: onlineUrl)
        #expect(expectedOnlineSize > 0)
        #expect(cacheRepo.calculateTotalCacheSize() == expectedOnlineSize)

        try cacheRepo.clearAllCache()
        #expect(cacheRepo.calculateTotalCacheSize() == 0)
        #expect(cacheRepo.getCachedChapterContent(bookUrl: "local://progress-book", index: 0) == "本地正文不应计入在线缓存")
    }
}

private final class MockWebDAVRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private var storedData = Data()

    func append(method: String, path: String) {
        lock.lock()
        calls.append("\(method):\(path)")
        lock.unlock()
    }

    func snapshotCalls() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func setStoredData(_ data: Data) {
        lock.lock()
        storedData = data
        lock.unlock()
    }

    func getStoredData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storedData
    }
}

private final class MockWebDAVURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [String: Handler] = [:]

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockWebDAVURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func register(host: String, handler: @escaping Handler) {
        lock.lock()
        handlers[host.lowercased()] = handler
        lock.unlock()
    }

    static func unregister(host: String) {
        lock.lock()
        handlers.removeValue(forKey: host.lowercased())
        lock.unlock()
    }

    static func readBody(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: bufferSize)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        lock.lock()
        let matched = handlers[host] != nil
        lock.unlock()
        return matched
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host?.lowercased() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.lock.lock()
        let handler = Self.handlers[host]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
