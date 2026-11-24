import CoreGraphics
import Foundation
@testable import Legado
import SwiftData
import Testing

@Suite("Purify, Security and WebDAV Cloud Sync Suite")
struct PurifyAndWebDAVSyncTests {

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

        let bundle = WebDAVBackupBundle(
            version: 1,
            backupTime: Date(),
            appVersion: "1.0.0",
            books: [sampleBook],
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
        #expect(WebDAVClient.normalizeBaseUrl("https://dav.jianguoyun.com/dav/小说备份") != nil)
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
                #expect(request.url?.absoluteString.hasSuffix("/") == true)
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
        #expect(calls.contains("MKCOL:/dav/Backup"))
        #expect(calls.contains("MKCOL:/dav/Backup/Legado"))
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
        try await bookRepoA.saveBook(Book(
            bookUrl: "https://example.com/test-b1",
            origin: "https://source.test",
            originName: "测试书源",
            name: "测试书",
            author: "作者",
            durChapterTitle: "第12章",
            durChapterIndex: 11,
            durChapterPos: 345))

        let backupUseCase = BackupToWebDAVUseCase(
            bookRepository: bookRepoA,
            replaceRuleStore: replaceStoreA,
            txtTocRuleStore: tocStoreA,
            readRecordStore: recordStoreA,
            readerConfigExporter: {
                guard let defaults = UserDefaults(suiteName: suiteA) else { return nil }
                return ReaderConfigStore.exportJSON(defaults: defaults)
            })

        let bundle = try await backupUseCase.generateBackupBundle()
        let data = try backupUseCase.exportBackupJsonData(bundle: bundle)

        let providerB = ModelContainerProvider(inMemory: true)
        let bookRepoB = BookRepositoryImpl(modelContainer: providerB.container)
        let restoreUseCase = RestoreFromWebDAVUseCase(
            bookRepository: bookRepoB,
            replaceRuleStore: replaceStoreB,
            txtTocRuleStore: tocStoreB,
            readRecordStore: recordStoreB,
            readerConfigImporter: { json in
                guard let defaults = UserDefaults(suiteName: suiteB) else { return }
                _ = ReaderConfigStore.importJSON(json, defaults: defaults)
            })

        let summary = try await restoreUseCase.restore(from: data)
        #expect(summary.bookCount == 1)

        let restoredBook = try await bookRepoB.getBook(by: "https://example.com/test-b1")
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

        let detailUseCase = GetBookDetailUseCase(bookRepository: bookRepo)
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

    @Test("Test Selective Progress Sync Prevents Ghost Book and Merges Matching Local Book")
    func webDAVSelectiveSyncProgressDoesNotCreateGhostBook() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebDAVGhostGuard_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let drive = MockWebDAVVirtualDrive()
        let host = "mock-ghost-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: host) { request in
            try drive.handle(request)
        }
        defer { MockWebDAVURLProtocol.unregister(host: host) }

        let client = WebDAVClient(urlSession: MockWebDAVURLProtocol.makeSession())
        let progressOnly = WebDAVSyncOptions(syncProgress: true, syncRules: false, syncBookFiles: false)
        let config = WebDAVConfig(serverUrl: "https://\(host)/dav/", syncOptions: progressOnly)

        let providerA = ModelContainerProvider(inMemory: true)
        let bookRepoA = BookRepositoryImpl(modelContainer: providerA.container)
        let cacheRepoA = BookCacheRepositoryImpl(baseDirectory: tempDir.appendingPathComponent("cacheA"))

        try await bookRepoA.saveBook(Book(
            bookUrl: "local://device-a-only.txt",
            origin: "local",
            originName: "本地书籍",
            name: "诡秘之主",
            author: "爱潜水的乌贼",
            durChapterTitle: "第26章",
            durChapterIndex: 25,
            durChapterPos: 800,
            durChapterTime: 2000))
        try cacheRepoA.saveChapterContent(bookUrl: "local://device-a-only.txt", index: 0, content: "非凡之路")

        try await bookRepoA.saveBook(Book(
            bookUrl: "local://device-a-same.txt",
            origin: "local",
            originName: "本地书籍",
            name: "三体",
            author: "本地导入",
            durChapterTitle: "第13章",
            durChapterIndex: 12,
            durChapterPos: 450,
            durChapterTime: 3000))
        try cacheRepoA.saveChapterContent(bookUrl: "local://device-a-same.txt", index: 0, content: "科学边界")

        let backupA = BackupToWebDAVUseCase(
            bookRepository: bookRepoA,
            bookCacheRepository: cacheRepoA,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_a.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_a.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_a.json")),
            readerConfigExporter: { nil })
        _ = try await backupA.execute(config: config, options: progressOnly)

        let providerB = ModelContainerProvider(inMemory: true)
        let bookRepoB = BookRepositoryImpl(modelContainer: providerB.container)
        let cacheRepoB = BookCacheRepositoryImpl(baseDirectory: tempDir.appendingPathComponent("cacheB"))

        // 设备 B 本身已有同名本地书（不同 UUID），但没有《诡秘之主》的本地文件
        try await bookRepoB.saveBook(Book(
            bookUrl: "local://device-b-uuid.txt",
            origin: "local",
            originName: "本地书籍",
            name: "三体",
            author: "本地导入",
            durChapterTitle: "第2章",
            durChapterIndex: 1,
            durChapterPos: 0,
            durChapterTime: 1000))
        try cacheRepoB.saveChapterContent(bookUrl: "local://device-b-uuid.txt", index: 0, content: "科学边界")

        let restoreB = RestoreFromWebDAVUseCase(
            bookRepository: bookRepoB,
            bookCacheRepository: cacheRepoB,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_b.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_b.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_b.json")),
            readerConfigImporter: { _ in })
        let summary = try await restoreB.execute(config: config, options: progressOnly)

        #expect(summary.skippedBookCount == 1)
        #expect(try await bookRepoB.getBook(by: "local://device-a-only.txt") == nil)
        let merged = try await bookRepoB.getBook(by: "local://device-b-uuid.txt")
        #expect(merged?.durChapterIndex == 12)
        #expect(merged?.durChapterPos == 450)
    }

    @Test("Test Selective Rules Sync Preserves Remote Books and Local Progress")
    func webDAVSelectiveSyncRulesPreservesRemoteBooks() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebDAVRulesOnly_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let drive = MockWebDAVVirtualDrive()
        let host = "mock-rules-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: host) { request in
            try drive.handle(request)
        }
        defer { MockWebDAVURLProtocol.unregister(host: host) }

        let client = WebDAVClient(urlSession: MockWebDAVURLProtocol.makeSession())
        let config = WebDAVConfig(serverUrl: "https://\(host)/dav/")

        let suiteA = "test.sel.rules.a.\(UUID().uuidString)"
        let suiteB = "test.sel.rules.b.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: suiteA)?.removePersistentDomain(forName: suiteA)
            UserDefaults(suiteName: suiteB)?.removePersistentDomain(forName: suiteB)
        }

        let replaceA = ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_a.json"))
        let tocA = TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_a.json"))
        let recA = ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_a.json"))
        let providerA = ModelContainerProvider(inMemory: true)
        let bookRepoA = BookRepositoryImpl(modelContainer: providerA.container)

        try await bookRepoA.saveBook(Book(
            bookUrl: "https://example.com/keep-book",
            origin: "https://source.test",
            name: "云端保留书",
            author: "作者",
            durChapterIndex: 8))
        _ = replaceA.upsert(ReplaceRule(name: "旧规则", pattern: "OLD", replacement: ""))

        let backupA = BackupToWebDAVUseCase(
            bookRepository: bookRepoA,
            webDAVClient: client,
            replaceRuleStore: replaceA,
            txtTocRuleStore: tocA,
            readRecordStore: recA,
            readerConfigExporter: {
                guard let defaults = UserDefaults(suiteName: suiteA) else { return nil }
                return ReaderConfigStore.exportJSON(defaults: defaults)
            })
        _ = try await backupA.execute(config: config, options: .all)

        // 设备 B 书架为空，但仅上传规则与排版
        let replaceB = ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_b.json"))
        let tocB = TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_b.json"))
        let recB = ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_b.json"))
        let providerB = ModelContainerProvider(inMemory: true)
        let bookRepoB = BookRepositoryImpl(modelContainer: providerB.container)

        _ = replaceB.upsert(ReplaceRule(name: "全新规则", pattern: "AD_NEW", replacement: ""))
        if let defaultsB = UserDefaults(suiteName: suiteB) {
            var cfgB = ReaderConfig.defaultConfig
            cfgB.fontSize = 26
            ReaderConfigStore.save(cfgB, defaults: defaultsB)
        }

        let rulesOnly = WebDAVSyncOptions(syncProgress: false, syncRules: true, syncBookFiles: false)
        let backupB = BackupToWebDAVUseCase(
            bookRepository: bookRepoB,
            webDAVClient: client,
            replaceRuleStore: replaceB,
            txtTocRuleStore: tocB,
            readRecordStore: recB,
            readerConfigExporter: {
                guard let defaults = UserDefaults(suiteName: suiteB) else { return nil }
                return ReaderConfigStore.exportJSON(defaults: defaults)
            })
        _ = try await backupB.execute(config: config, options: rulesOnly)

        // 确认云端 JSON 中的书籍未被清空，且设备 A 仅还原规则后本地书进度不变
        let rawBackup = drive.getData(endingWith: "legado_backup.json")
        #expect(rawBackup != nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remoteBundle = try decoder.decode(WebDAVBackupBundle.self, from: rawBackup!)
        #expect(remoteBundle.books.count == 1)

        let restoreA = RestoreFromWebDAVUseCase(
            bookRepository: bookRepoA,
            webDAVClient: client,
            replaceRuleStore: replaceA,
            txtTocRuleStore: tocA,
            readRecordStore: recA,
            readerConfigImporter: { json in
                guard let defaults = UserDefaults(suiteName: suiteA) else { return }
                _ = ReaderConfigStore.importJSON(json, defaults: defaults)
            })
        _ = try await restoreA.execute(config: config, options: rulesOnly)
        #expect(replaceA.loadRules().contains(where: { $0.name == "全新规则" }))
        #expect(UserDefaults(suiteName: suiteA).map { ReaderConfigStore.load(defaults: $0).fontSize } == 26)
        #expect(try await bookRepoA.getBook(by: "https://example.com/keep-book")?.durChapterIndex == 8)
    }

    @Test("Test Compressed Book File Archive WebDAV Sync End to End")
    func webDAVBookFileArchiveSyncEndToEnd() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebDAVArchiveE2E_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let drive = MockWebDAVVirtualDrive()
        let host = "mock-archive-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: host) { request in
            try drive.handle(request)
        }
        defer { MockWebDAVURLProtocol.unregister(host: host) }

        let client = WebDAVClient(urlSession: MockWebDAVURLProtocol.makeSession())
        let config = WebDAVConfig(serverUrl: "https://\(host)/dav/")

        let providerA = ModelContainerProvider(inMemory: true)
        let bookRepoA = BookRepositoryImpl(modelContainer: providerA.container)
        let bookmarkRepoA = BookmarkRepositoryImpl(modelContainer: providerA.container)
        let cacheRepoA = BookCacheRepositoryImpl(baseDirectory: tempDir.appendingPathComponent("cacheA"))

        let bookUrl = "local://archive-e2e-book.txt"
        try await bookRepoA.saveBook(Book(
            bookUrl: bookUrl,
            origin: "local",
            originName: "本地导入",
            name: "凡人修仙传",
            author: "忘语",
            durChapterTitle: "第二章 墨大夫",
            durChapterIndex: 1,
            durChapterPos: 120,
            durChapterTime: 5000,
            totalChapterNum: 2))
        let chaptersA = [
            Chapter(url: "\(bookUrl)#0", title: "第一章 山边小村", bookUrl: bookUrl, index: 0, isCached: true),
            Chapter(url: "\(bookUrl)#1", title: "第二章 墨大夫", bookUrl: bookUrl, index: 1, isCached: true),
        ]
        try await bookRepoA.saveChapters(chaptersA, for: bookUrl)
        try cacheRepoA.saveChapterContent(bookUrl: bookUrl, index: 0, content: "二愣子韩立自幼住在青牛镇。")
        try cacheRepoA.saveChapterContent(bookUrl: bookUrl, index: 1, content: "七玄门收徒考核正式开始。")
        try await bookmarkRepoA.saveBookmark(Bookmark(
            time: 5001,
            bookName: "凡人修仙传",
            bookAuthor: "忘语",
            bookUrl: bookUrl,
            chapterIndex: 1,
            chapterPos: 50,
            chapterName: "第二章 墨大夫",
            bookText: "七玄门收徒考核",
            content: "精彩开篇"))

        let backupA = BackupToWebDAVUseCase(
            bookRepository: bookRepoA,
            bookmarkRepository: bookmarkRepoA,
            bookCacheRepository: cacheRepoA,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_a.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_a.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_a.json")),
            readerConfigExporter: { nil })
        let backupSummary = try await backupA.execute(config: config, options: .all)
        #expect(backupSummary.bookFileCount == 1)

        // 全新空白设备 B 恢复含书籍文件的完整备份
        let providerB = ModelContainerProvider(inMemory: true)
        let bookRepoB = BookRepositoryImpl(modelContainer: providerB.container)
        let bookmarkRepoB = BookmarkRepositoryImpl(modelContainer: providerB.container)
        let cacheRepoB = BookCacheRepositoryImpl(baseDirectory: tempDir.appendingPathComponent("cacheB"))

        let restoreB = RestoreFromWebDAVUseCase(
            bookRepository: bookRepoB,
            bookmarkRepository: bookmarkRepoB,
            bookCacheRepository: cacheRepoB,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_b.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_b.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_b.json")),
            readerConfigImporter: { _ in })
        let restoreSummary = try await restoreB.execute(config: config, options: .all)

        #expect(restoreSummary.bookFileCount == 1)
        #expect(restoreSummary.skippedBookCount == 0)
        #expect(restoreSummary.bookmarkCount == 1)

        let restoredBook = try await bookRepoB.getBook(by: bookUrl)
        #expect(restoredBook?.name == "凡人修仙传")
        #expect(restoredBook?.durChapterIndex == 1)

        let restoredChapters = try await bookRepoB.getChapters(for: bookUrl)
        #expect(restoredChapters.count == 2)
        #expect(cacheRepoB.getCachedChapterContent(bookUrl: bookUrl, index: 0) == "二愣子韩立自幼住在青牛镇。")
        #expect(cacheRepoB.getCachedChapterContent(bookUrl: bookUrl, index: 1) == "七玄门收徒考核正式开始。")

        let restoredBookmarks = try await bookmarkRepoB.getBookmarks(bookName: "凡人修仙传", bookAuthor: "忘语")
        #expect(restoredBookmarks.count == 1)
        #expect(restoredBookmarks.first?.content == "精彩开篇")
    }

    @Test("Test Optimized TxtTocParser Single Pass Splitting and Preface Handling")
    func optimizedTxtTocParserSplitsAccurately() {
        let sample = """
        全书导语
        第一卷 初入江湖
        第1章 少年出发
        风起于青萍之末，少年背上行囊。
        第2章 风雪夜归人
        风雪漫天，客栈灯火摇曳。
        """
        let chapters = TxtTocParser.parse(text: sample, customPattern: TxtTocParser.defaultChapterPattern)
        #expect(chapters.count == 3)
        #expect(chapters[0].title == "前言")
        #expect(chapters[0].content == "全书导语")
        #expect(chapters[1].title == "第一卷 初入江湖 · 第1章 少年出发")
        #expect(chapters[1].content.contains("青萍之末"))
        #expect(chapters[2].title == "第2章 风雪夜归人")
    }

    @Test("Test Manual WebDAV Restore Overrides Freshly Imported Unread Book Progress")
    func webDAVManualRestoreOverridesNewlyImportedBookTimestamp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebDAVRestoreOverride_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let drive = MockWebDAVVirtualDrive()
        let host = "mock-override-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: host) { request in
            try drive.handle(request)
        }
        defer { MockWebDAVURLProtocol.unregister(host: host) }

        let client = WebDAVClient(urlSession: MockWebDAVURLProtocol.makeSession())
        let config = WebDAVConfig(serverUrl: "https://\(host)/dav/")

        // 设备 A 较早阅读到第 20 章偏移 1520
        let providerA = ModelContainerProvider(inMemory: true)
        let bookRepoA = BookRepositoryImpl(modelContainer: providerA.container)
        let cacheRepoA = BookCacheRepositoryImpl(baseDirectory: tempDir.appendingPathComponent("cacheA"))

        try await bookRepoA.saveBook(Book(
            bookUrl: "local://device-a-book",
            origin: "local",
            originName: "本地书籍",
            name: "凡人修仙传",
            author: "忘语",
            durChapterTitle: "第二十章 小试牛刀",
            durChapterIndex: 19,
            durChapterPos: 1520,
            durChapterTime: 1000))
        try cacheRepoA.saveChapterContent(bookUrl: "local://device-a-book", index: 19, content: "第二十章正文")

        let backupA = BackupToWebDAVUseCase(
            bookRepository: bookRepoA,
            bookCacheRepository: cacheRepoA,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_a.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_a.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_a.json")),
            readerConfigExporter: { nil })
        _ = try await backupA.execute(config: config, options: .all)

        // 设备 B 稍后导入同名本地书但未翻阅（即便是较新导入时间戳，也不应阻断还原进度）
        let providerB = ModelContainerProvider(inMemory: true)
        let bookRepoB = BookRepositoryImpl(modelContainer: providerB.container)
        let cacheRepoB = BookCacheRepositoryImpl(baseDirectory: tempDir.appendingPathComponent("cacheB"))

        try await bookRepoB.saveBook(Book(
            bookUrl: "local://device-b-book",
            origin: "local",
            originName: "本地书籍",
            name: "凡人修仙传",
            author: "本地导入",
            durChapterTitle: "第一章",
            durChapterIndex: 0,
            durChapterPos: 0,
            durChapterTime: 9000))
        try cacheRepoB.saveChapterContent(bookUrl: "local://device-b-book", index: 0, content: "第一章正文")

        let restoreB = RestoreFromWebDAVUseCase(
            bookRepository: bookRepoB,
            bookCacheRepository: cacheRepoB,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_b.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_b.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_b.json")),
            readerConfigImporter: { _ in })
        _ = try await restoreB.execute(config: config, options: .all)

        let updatedB = try await bookRepoB.getBook(by: "local://device-b-book")
        #expect(updatedB?.durChapterIndex == 19)
        #expect(updatedB?.durChapterPos == 1520)
        #expect(updatedB?.durChapterTitle == "第二十章 小试牛刀")
    }

    @Test("Test Restore Applies Newer Bundle or Realtime Progress Over Older Archive")
    func webDAVRestoreMergesNewerProgressOverOlderBookArchive() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebDAVArchiveMerge_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let drive = MockWebDAVVirtualDrive()
        let host = "mock-merge-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: host) { request in
            try drive.handle(request)
        }
        defer { MockWebDAVURLProtocol.unregister(host: host) }

        let client = WebDAVClient(urlSession: MockWebDAVURLProtocol.makeSession())
        let config = WebDAVConfig(serverUrl: "https://\(host)/dav/")

        let providerA = ModelContainerProvider(inMemory: true)
        let bookRepoA = BookRepositoryImpl(modelContainer: providerA.container)
        let cacheRepoA = BookCacheRepositoryImpl(baseDirectory: tempDir.appendingPathComponent("cacheA"))

        let bookUrl = "local://merge-archive-book"
        try await bookRepoA.saveBook(Book(
            bookUrl: bookUrl,
            origin: "local",
            originName: "本地书籍",
            name: "遮天",
            author: "辰东",
            durChapterTitle: "第二章 星空古路",
            durChapterIndex: 1,
            durChapterPos: 10,
            durChapterTime: 1000))
        let chaptersA = (0 ..< 6).map { idx in
            Chapter(url: "\(bookUrl)#\(idx)", title: "第\(idx + 1)章", bookUrl: bookUrl, index: idx, isCached: true)
        }
        try await bookRepoA.saveChapters(chaptersA, for: bookUrl)
        for idx in 0 ..< 6 {
            try cacheRepoA.saveChapterContent(bookUrl: bookUrl, index: idx, content: "章节正文内容 \(idx)")
        }

        let backupA = BackupToWebDAVUseCase(
            bookRepository: bookRepoA,
            bookCacheRepository: cacheRepoA,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_a.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_a.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_a.json")),
            readerConfigExporter: { nil })
        // 1. 先完整上传（.legadobook 归档停留在第 2 章）
        _ = try await backupA.execute(config: config, options: .all)

        // 2. 后续仅同步了更新后的进度（第 5 章偏移 888），并未重新上传 .legadobook 压缩包
        try await bookRepoA.saveBook(Book(
            bookUrl: bookUrl,
            origin: "local",
            originName: "本地书籍",
            name: "遮天",
            author: "辰东",
            durChapterTitle: "第5章",
            durChapterIndex: 4,
            durChapterPos: 888,
            durChapterTime: 5000))
        let progressOnly = WebDAVSyncOptions(syncProgress: true, syncRules: false, syncBookFiles: false)
        _ = try await backupA.execute(config: config, options: progressOnly)

        // 3. 设备 B 勾选完整恢复，最终进度必须是更新的第 5 章偏移 888，而不是旧压缩包的第 2 章
        let providerB = ModelContainerProvider(inMemory: true)
        let bookRepoB = BookRepositoryImpl(modelContainer: providerB.container)
        let cacheRepoB = BookCacheRepositoryImpl(baseDirectory: tempDir.appendingPathComponent("cacheB"))

        let restoreB = RestoreFromWebDAVUseCase(
            bookRepository: bookRepoB,
            bookCacheRepository: cacheRepoB,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_b.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_b.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_b.json")),
            readerConfigImporter: { _ in })
        _ = try await restoreB.execute(config: config, options: .all)

        let restoredBook = try await bookRepoB.getBook(by: bookUrl)
        #expect(restoredBook?.durChapterIndex == 4)
        #expect(restoredBook?.durChapterPos == 888)
    }

    @Test("Test ReaderViewModel Restores Fresh Persisted Progress Across Bounds Updates")
    @MainActor
    func readerViewModelRestoresPersistedProgressAcrossScreenBoundsUpdates() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderRestoreVM_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)
        let cacheRepo = BookCacheRepositoryImpl(baseDirectory: tempDir)

        let bookUrl = "local://vm-restore-book"
        let longBody = Array(repeating: "天地玄黄，宇宙洪荒，日月盈昃，辰宿列张。", count: 140).joined(separator: "\n")
        let chapters = [
            Chapter(url: "\(bookUrl)#0", title: "第一章 启程", bookUrl: bookUrl, index: 0, isCached: true),
            Chapter(url: "\(bookUrl)#1", title: "第二章 深空", bookUrl: bookUrl, index: 1, isCached: true),
        ]
        try await bookRepo.saveChapters(chapters, for: bookUrl)
        try cacheRepo.saveChapterContent(bookUrl: bookUrl, index: 0, content: "第一章短正文。")
        try cacheRepo.saveChapterContent(bookUrl: bookUrl, index: 1, content: longBody)

        let persistedBook = Book(
            bookUrl: bookUrl,
            origin: "local",
            originName: "本地书籍",
            name: "星海漫游",
            author: "作者",
            durChapterTitle: "第二章 深空",
            durChapterIndex: 1,
            durChapterPos: 950,
            durChapterTime: 8888,
            totalChapterNum: 2)
        try await bookRepo.saveBook(persistedBook)

        // 传入尚未刷新的旧书架快照 (0, 0)，模拟列表尚未更新时打开阅读器
        let staleBook = Book(
            bookUrl: bookUrl,
            origin: "local",
            originName: "本地书籍",
            name: "星海漫游",
            author: "作者",
            durChapterTitle: "第一章 启程",
            durChapterIndex: 0,
            durChapterPos: 0,
            durChapterTime: 0,
            totalChapterNum: 2)

        let vm = ReaderViewModel(
            book: staleBook,
            initialChapterIndex: nil,
            getChapterContentUseCase: GetChapterContentUseCase(cacheRepository: cacheRepo),
            getBookTocUseCase: GetBookTocUseCase(bookRepository: bookRepo),
            bookRepository: bookRepo)

        // 立即发送屏幕尺寸更新，验证不会把 pendingRestoreOffset 重置为第 0 页
        vm.send(.updateScreenBounds(CGRect(x: 0, y: 0, width: 393, height: 852)))

        for _ in 0 ..< 400 {
            if !vm.state.isLoading && !vm.state.pages.isEmpty && vm.state.currentChapterIndex == 1 {
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        #expect(vm.state.currentChapterIndex == 1)
        #expect(vm.state.pages.count > 1)
        #expect(vm.state.currentPageIndex > 0)
        guard vm.state.pages.indices.contains(vm.state.currentPageIndex) else { return }
        let currentPage = vm.state.pages[vm.state.currentPageIndex]
        #expect(950 >= currentPage.textRange.location)
        #expect(950 < currentPage.textRange.location + max(currentPage.textRange.length, 1))
    }

    @Test("Test WebDAV Realtime Sync Push Pull and Disabled Guard")
    @MainActor
    func webDAVRealtimeSyncPushPullAndDisabledGuard() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebDAVRealtime_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let drive = MockWebDAVVirtualDrive()
        let host = "mock-realtime-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: host) { request in
            try drive.handle(request)
        }
        defer { MockWebDAVURLProtocol.unregister(host: host) }

        let client = WebDAVClient(urlSession: MockWebDAVURLProtocol.makeSession())

        let providerA = ModelContainerProvider(inMemory: true)
        let bookRepoA = BookRepositoryImpl(modelContainer: providerA.container)
        let backupA = BackupToWebDAVUseCase(
            bookRepository: bookRepoA,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_a.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_a.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_a.json")),
            readerConfigExporter: { nil })

        // 1. 当未启用实时同步时，绝对不会发起任何网络请求
        let disabledOptions = WebDAVSyncOptions(
            syncProgress: true,
            syncRules: true,
            syncBookFiles: true,
            autoSyncEnabled: false,
            realtimeSyncProgress: true,
            realtimeSyncRules: false)
        let disabledConfig = WebDAVConfig(serverUrl: "https://\(host)/dav/", syncOptions: disabledOptions)
        let disabledService = WebDAVRealtimeSyncService(
            bookRepository: bookRepoA,
            backupUseCase: backupA,
            webDAVClient: client,
            configProvider: { disabledConfig })

        let bookA = Book(
            bookUrl: "local://realtime-book-a",
            origin: "local",
            name: "雪中悍刀行",
            author: "烽火戏诸侯",
            durChapterTitle: "第十六章",
            durChapterIndex: 15,
            durChapterPos: 900,
            durChapterTime: 6000)
        disabledService.scheduleProgressPush(book: bookA, debounceSeconds: 0)
        _ = await disabledService.pullLatestProgressIfNeeded(for: bookA, force: true)
        #expect(drive.totalRequestCount == 0)

        // 2. 开启实时同步后，设备 A 推送轻量进度，设备 B 拉取后直接合并更新并回调书架刷新
        let enabledConfig = WebDAVConfig(serverUrl: "https://\(host)/dav/", syncOptions: .defaultSelection)
        let serviceA = WebDAVRealtimeSyncService(
            bookRepository: bookRepoA,
            backupUseCase: backupA,
            webDAVClient: client,
            configProvider: { enabledConfig })

        serviceA.scheduleProgressPush(book: bookA, debounceSeconds: 0.02)
        for _ in 0 ..< 50 {
            if drive.getData(endingWith: "reading_progress.json") != nil {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(drive.getData(endingWith: "reading_progress.json") != nil)

        let providerB = ModelContainerProvider(inMemory: true)
        let bookRepoB = BookRepositoryImpl(modelContainer: providerB.container)
        let bookB = Book(
            bookUrl: "local://realtime-book-b",
            origin: "local",
            name: "雪中悍刀行",
            author: "本地导入",
            durChapterTitle: "第一章",
            durChapterIndex: 0,
            durChapterPos: 0,
            durChapterTime: 0)
        try await bookRepoB.saveBook(bookB)

        let backupB = BackupToWebDAVUseCase(
            bookRepository: bookRepoB,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r_b.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t_b.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec_b.json")),
            readerConfigExporter: { nil })

        let refreshFlag = MockWebDAVVirtualDrive()
        let serviceB = WebDAVRealtimeSyncService(
            bookRepository: bookRepoB,
            backupUseCase: backupB,
            webDAVClient: client,
            configProvider: { enabledConfig },
            onBookshelfUpdated: { refreshFlag.markUpdated() })

        let pulledBook = await serviceB.pullLatestProgressIfNeeded(for: bookB, force: true)
        #expect(refreshFlag.wasUpdated)
        #expect(pulledBook?.durChapterIndex == 15)
        #expect(pulledBook?.durChapterPos == 900)
        let persistedB = try await bookRepoB.getBook(by: "local://realtime-book-b")
        #expect(persistedB?.durChapterIndex == 15)
        #expect(persistedB?.durChapterPos == 900)
    }

    // MARK: - v1.2.0 性能优化与内存防泄露回归测试

    @Test("Bookmark formattedDate matches formatter and deleteBookmarks deletes batch in one pass")
    func bookmarkFormattedDateAndBatchDelete() async throws {
        let timestamp: Int64 = 1_700_000_000_000
        let bookmark = Bookmark(
            time: timestamp,
            bookName: "测试书签",
            bookAuthor: "作者A",
            bookUrl: "local://bookmark-test",
            chapterIndex: 2,
            chapterPos: 45,
            chapterName: "第三章",
            bookText: "示例正文摘录")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let expectedDate = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000))
        #expect(bookmark.formattedDate == expectedDate)

        let provider = ModelContainerProvider(inMemory: true)
        let repo = BookmarkRepositoryImpl(modelContainer: provider.container)
        let b1 = Bookmark(
            time: 1001,
            bookName: "书A",
            bookAuthor: "作者",
            bookUrl: "local://b",
            chapterIndex: 0,
            chapterPos: 0,
            chapterName: "一",
            bookText: "摘录1")
        let b2 = Bookmark(
            time: 1002,
            bookName: "书A",
            bookAuthor: "作者",
            bookUrl: "local://b",
            chapterIndex: 1,
            chapterPos: 0,
            chapterName: "二",
            bookText: "摘录2")
        let b3 = Bookmark(
            time: 1003,
            bookName: "书A",
            bookAuthor: "作者",
            bookUrl: "local://b",
            chapterIndex: 2,
            chapterPos: 0,
            chapterName: "三",
            bookText: "摘录3")

        try await repo.saveBookmark(b1)
        try await repo.saveBookmark(b2)
        try await repo.saveBookmark(b3)

        try await repo.deleteBookmarks(ids: [])
        #expect(try await repo.getAllBookmarks().count == 3)

        try await repo.deleteBookmarks(ids: [b1.id, b3.id])
        let remaining = try await repo.getAllBookmarks()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == b2.id)
    }

    @Test("SearchBookContentUseCase runs off main actor and respects maxMatches limit")
    func searchBookContentRunsOffMainActorAndRespectsLimit() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LegadoSearchTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cacheRepo = BookCacheRepositoryImpl(baseDirectory: tempDir)
        let getChapterContentUseCase = GetChapterContentUseCase(cacheRepository: cacheRepo)

        let book = Book(
            bookUrl: "local://search-perf-book",
            origin: "local",
            name: "秘境探索",
            author: "测试作者")
        let chapters = [
            Chapter(url: "local://c0", title: "第一章", bookUrl: book.bookUrl, index: 0),
            Chapter(url: "local://c1", title: "第二章", bookUrl: book.bookUrl, index: 1),
            Chapter(url: "local://c2", title: "第三章", bookUrl: book.bookUrl, index: 2),
        ]

        try cacheRepo.saveChapterContent(bookUrl: book.bookUrl, index: 0, content: "荒野之中藏着古老秘宝。")
        try cacheRepo.saveChapterContent(bookUrl: book.bookUrl, index: 1, content: "密室石门上也刻着秘宝线索。")
        try cacheRepo.saveChapterContent(bookUrl: book.bookUrl, index: 2, content: "最终大厅发现了失落秘宝。")

        var matches: [BookSearchMatch] = []
        for await match in SearchBookContentUseCase().search(
            keyword: "秘宝",
            book: book,
            chapters: chapters,
            getChapterContentUseCase: getChapterContentUseCase,
            maxMatches: 2) {
            matches.append(match)
        }

        #expect(matches.count == 2)
        #expect(matches[0].chapterIndex == 0)
        #expect(matches[1].chapterIndex == 1)
    }

    // MARK: - WebDAV 实时同步可靠性、防覆盖与规则双向同步回归测试

    @Test("Realtime progress push aborts overwrite on HTTP 500 and preserves other books after recovery")
    @MainActor
    func webDAVRealtimeProgressPushProtectsRemoteOnTransientError() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebDAVRealtimeGuard_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let drive = MockWebDAVVirtualDrive()
        let host = "mock-rt-guard-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: host) { request in
            try drive.handle(request)
        }
        defer { MockWebDAVURLProtocol.unregister(host: host) }

        let client = WebDAVClient(urlSession: MockWebDAVURLProtocol.makeSession())
        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)
        let backup = BackupToWebDAVUseCase(
            bookRepository: bookRepo,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec.json")),
            readerConfigExporter: { nil })

        let config = WebDAVConfig(serverUrl: "https://\(host)/dav/", syncOptions: .defaultSelection)
        let existingProgress = WebDAVProgressBundle(
            updatedAt: Date(),
            items: [
                WebDAVBookProgress(
                    bookUrl: "local://existing-book-x",
                    name: "诡秘之主",
                    author: "爱潜水的乌贼",
                    durChapterIndex: 8,
                    durChapterPos: 500,
                    durChapterTitle: "第九章",
                    durChapterTime: 4000),
            ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let seededData = try encoder.encode(existingProgress)
        try await client.upload(data: seededData, filename: "reading_progress.json", config: config)

        let service = WebDAVRealtimeSyncService(
            bookRepository: bookRepo,
            backupUseCase: backup,
            webDAVClient: client,
            configProvider: { config })

        drive.setSimulatedGetStatusCode(500)
        drive.resetRecordedCalls()

        let bookY = Book(
            bookUrl: "local://book-y",
            origin: "local",
            name: "道诡异仙",
            author: "狐尾的笔",
            durChapterTitle: "第二十章",
            durChapterIndex: 19,
            durChapterPos: 300,
            durChapterTime: 8000)
        service.scheduleProgressPush(book: bookY, debounceSeconds: 0.01)

        for _ in 0 ..< 50 {
            if service.status.lastErrorMessage != nil {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.status.lastErrorMessage != nil)
        #expect(!drive.recordedCallsSnapshot().contains { $0.hasPrefix("PUT:") })

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let untouched = try decoder.decode(
            WebDAVProgressBundle.self,
            from: drive.getData(endingWith: "reading_progress.json")!)
        #expect(untouched.items.count == 1)
        #expect(untouched.items.first?.name == "诡秘之主")

        drive.setSimulatedGetStatusCode(nil)
        service.flushPendingProgressPush()
        for _ in 0 ..< 50 {
            if service.status.lastErrorMessage == nil,
               drive.recordedCallsSnapshot().contains(where: { $0.hasPrefix("PUT:") }) {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.status.lastErrorMessage == nil)
        let merged = try decoder.decode(
            WebDAVProgressBundle.self,
            from: drive.getData(endingWith: "reading_progress.json")!)
        #expect(merged.items.count == 2)
        #expect(merged.items.contains { $0.name == "诡秘之主" && $0.durChapterIndex == 8 })
        #expect(merged.items.contains { $0.name == "道诡异仙" && $0.durChapterIndex == 19 })
    }

    @Test("Partial backup throws on remote HTTP 503 instead of wiping existing remote bundle")
    func backupUseCaseAbortsPartialOverwriteWhenRemoteIndexFails() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebDAVPartialGuard_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let drive = MockWebDAVVirtualDrive()
        let host = "mock-partial-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: host) { request in
            try drive.handle(request)
        }
        defer { MockWebDAVURLProtocol.unregister(host: host) }

        let client = WebDAVClient(urlSession: MockWebDAVURLProtocol.makeSession())
        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)
        let backupUseCase = BackupToWebDAVUseCase(
            bookRepository: bookRepo,
            webDAVClient: client,
            replaceRuleStore: ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("r.json")),
            txtTocRuleStore: TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("t.json")),
            readRecordStore: ReadRecordStore(storageUrl: tempDir.appendingPathComponent("rec.json")),
            readerConfigExporter: { nil })

        let config = WebDAVConfig(serverUrl: "https://\(host)/dav/", syncOptions: .defaultSelection)
        let existingBundle = WebDAVBackupBundle(
            version: 2,
            backupTime: Date(),
            appVersion: "1.2.0",
            books: [Book(bookUrl: "local://keep-me", origin: "local", name: "保留书籍", author: "作者")])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try await client.upload(
            data: try encoder.encode(existingBundle),
            filename: "legado_backup.json",
            config: config)

        drive.setSimulatedGetStatusCode(503)
        drive.resetRecordedCalls()

        let rulesOnly = WebDAVSyncOptions(syncProgress: false, syncRules: true, syncBookFiles: false)
        var didThrow = false
        do {
            _ = try await backupUseCase.execute(config: config, options: rulesOnly)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(!drive.recordedCallsSnapshot().contains { $0.hasPrefix("PUT:") })

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let intact = try decoder.decode(
            WebDAVBackupBundle.self,
            from: drive.getData(endingWith: "legado_backup.json")!)
        #expect(intact.books.count == 1)
        #expect(intact.books.first?.name == "保留书籍")
    }

    @Test("Realtime rules sync pushes rules_sync.json, pulls on second device, and ignores older timestamps")
    @MainActor
    func webDAVRealtimeRulesSyncRoundTripAndTimestampGuard() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebDAVRulesRT_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteA = "legado_rt_rules_a_\(UUID().uuidString)"
        let suiteB = "legado_rt_rules_b_\(UUID().uuidString)"
        let defaultsA = UserDefaults(suiteName: suiteA)!
        let defaultsB = UserDefaults(suiteName: suiteB)!
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }

        let drive = MockWebDAVVirtualDrive()
        let host = "mock-rules-rt-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: host) { request in
            try drive.handle(request)
        }
        defer { MockWebDAVURLProtocol.unregister(host: host) }

        let client = WebDAVClient(urlSession: MockWebDAVURLProtocol.makeSession())
        let providerA = ModelContainerProvider(inMemory: true)
        let providerB = ModelContainerProvider(inMemory: true)
        let replaceA = ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("rep_a.json"))
        let replaceB = ReplaceRuleStore(storageUrl: tempDir.appendingPathComponent("rep_b.json"))
        let tocA = TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("toc_a.json"))
        let tocB = TxtTocRuleStore(storageUrl: tempDir.appendingPathComponent("toc_b.json"))
        let configBoxA = LockedStringBox("{\"fontSize\":24}")
        let configBoxB = LockedStringBox(nil)

        replaceA.saveRules([ReplaceRule(name: "实时规则A", pattern: "旧水印", replacement: "")])
        tocA.saveRules([TxtTocRule(name: "实时分章A", rule: "^第\\d+节.*", example: "第1节")])

        let rulesSyncOptions = WebDAVSyncOptions(
            syncProgress: true,
            syncRules: true,
            syncBookFiles: true,
            autoSyncEnabled: true,
            realtimeSyncProgress: true,
            realtimeSyncRules: true)
        let config = WebDAVConfig(serverUrl: "https://\(host)/dav/", syncOptions: rulesSyncOptions)

        let serviceA = WebDAVRealtimeSyncService(
            bookRepository: BookRepositoryImpl(modelContainer: providerA.container),
            backupUseCase: BackupToWebDAVUseCase(
                bookRepository: BookRepositoryImpl(modelContainer: providerA.container),
                webDAVClient: client),
            webDAVClient: client,
            replaceRuleStore: replaceA,
            txtTocRuleStore: tocA,
            readerConfigExporter: { configBoxA.get() },
            rulesTimestampDefaults: defaultsA,
            configProvider: { config })

        serviceA.scheduleRulesPush(debounceSeconds: 0.01)
        for _ in 0 ..< 50 {
            if drive.getData(endingWith: "rules_sync.json") != nil {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(drive.getData(endingWith: "rules_sync.json") != nil)

        let rulesCallbackFlag = MockWebDAVVirtualDrive()
        let serviceB = WebDAVRealtimeSyncService(
            bookRepository: BookRepositoryImpl(modelContainer: providerB.container),
            backupUseCase: BackupToWebDAVUseCase(
                bookRepository: BookRepositoryImpl(modelContainer: providerB.container),
                webDAVClient: client),
            webDAVClient: client,
            replaceRuleStore: replaceB,
            txtTocRuleStore: tocB,
            readerConfigExporter: { configBoxB.get() },
            readerConfigImporter: { configBoxB.set($0) },
            rulesTimestampDefaults: defaultsB,
            configProvider: { config },
            onRulesUpdated: { rulesCallbackFlag.markUpdated() })

        let pulled = await serviceB.pullLatestRulesIfNeeded(force: true)
        #expect(pulled)
        #expect(rulesCallbackFlag.wasUpdated)
        #expect(replaceB.loadRules().contains { $0.name == "实时规则A" })
        #expect(tocB.loadRules().contains { $0.name == "实时分章A" })
        #expect(configBoxB.get() == "{\"fontSize\":24}")

        // 远端退化为更早时间戳时，不会覆盖设备 B 较新的规则
        let staleBundle = WebDAVRulesBundle(
            updatedAt: Date().addingTimeInterval(-3600),
            replaceRules: [ReplaceRule(name: "过期旧规则", pattern: "old", replacement: "")],
            txtTocRules: [],
            readerConfigJson: "{\"fontSize\":12}")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try await client.upload(
            data: try encoder.encode(staleBundle),
            filename: "rules_sync.json",
            config: config)

        let appliedStale = await serviceB.pullLatestRulesIfNeeded(force: true)
        #expect(!appliedStale)
        #expect(configBoxB.get() == "{\"fontSize\":24}")
        #expect(!replaceB.loadRules().contains { $0.name == "过期旧规则" })
    }

    @Test("WebDAVClient skips redundant MKCOL unless 409, and serialized flush preserves latest progress")
    @MainActor
    func webDAVSkipMkcolAndSerializedFlushWithBackgroundTask() async throws {
        let drive = MockWebDAVVirtualDrive()
        let host = "mock-mkcol-opt-\(UUID().uuidString.lowercased()).local"
        MockWebDAVURLProtocol.register(host: host) { request in
            try drive.handle(request)
        }
        defer { MockWebDAVURLProtocol.unregister(host: host) }

        let client = WebDAVClient(urlSession: MockWebDAVURLProtocol.makeSession())
        let config = WebDAVConfig(serverUrl: "https://\(host)/dav/", remoteDirectory: "/Legado/")

        // 目录尚未创建时，ensureDirectory: false 遇 409 自动 MKCOL 并重试 PUT
        drive.setRequireMkcolOnce(true)
        drive.resetRecordedCalls()
        try await client.upload(
            data: Data("{\"v\":1}".utf8),
            filename: "probe.json",
            config: config,
            ensureDirectory: false)
        let firstCalls = drive.recordedCallsSnapshot()
        #expect(firstCalls.contains("MKCOL:/dav/Legado"))
        #expect(firstCalls.filter { $0.hasPrefix("PUT:") }.count == 2)

        // 目录已存在时，ensureDirectory: false 直接 PUT，不发 MKCOL
        drive.resetRecordedCalls()
        try await client.upload(
            data: Data("{\"v\":2}".utf8),
            filename: "probe.json",
            config: config,
            ensureDirectory: false)
        let steadyCalls = drive.recordedCallsSnapshot()
        #expect(!steadyCalls.contains { $0.hasPrefix("MKCOL:") })
        #expect(steadyCalls == ["PUT:/dav/Legado/probe.json"])

        // 连续入队并立即冲洗时，调用后台任务保活成对释放，并持久化最后一次进度
        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)
        let backup = BackupToWebDAVUseCase(
            bookRepository: bookRepo,
            webDAVClient: client)

        let bgStats = MockWebDAVRecorder()
        let service = WebDAVRealtimeSyncService(
            bookRepository: bookRepo,
            backupUseCase: backup,
            webDAVClient: client,
            configProvider: { config },
            backgroundTaskProvider: { _ in
                bgStats.append(method: "BEGIN", path: "bg")
                return {
                    bgStats.append(method: "END", path: "bg")
                }
            })

        let b1 = Book(
            bookUrl: "local://seq-1",
            origin: "local",
            name: "凡人修仙传",
            author: "忘语",
            durChapterTitle: "第10章",
            durChapterIndex: 9,
            durChapterPos: 100,
            durChapterTime: 1000)
        var b2 = b1
        b2.durChapterIndex = 30
        b2.durChapterPos = 450
        b2.durChapterTitle = "第31章"
        b2.durChapterTime = 9000

        service.scheduleProgressPush(book: b1, debounceSeconds: 5.0)
        service.scheduleProgressPush(book: b2, debounceSeconds: 5.0)
        service.flushPendingProgressPush()

        for _ in 0 ..< 50 {
            let calls = bgStats.snapshotCalls()
            if calls.contains("END:bg") {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let bgEvents = bgStats.snapshotCalls()
        #expect(bgEvents.filter { $0 == "BEGIN:bg" }.count == 1)
        #expect(bgEvents.filter { $0 == "END:bg" }.count == 1)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let synced = try decoder.decode(
            WebDAVProgressBundle.self,
            from: drive.getData(endingWith: "reading_progress.json")!)
        #expect(synced.items.first?.durChapterIndex == 30)
        #expect(synced.items.first?.durChapterPos == 450)
    }

    @Test("WebDAVConfigStore filters incomplete hosts and unauthenticated template defaults")
    func webDAVConfigStoreEffectiveConfigurationFilter() {
        #expect(!WebDAVConfigStore.isEffectivelyConfigured(WebDAVConfig()))
        #expect(!WebDAVConfigStore.isEffectivelyConfigured(WebDAVConfig(serverUrl: "http://nas")))
        #expect(!WebDAVConfigStore.isEffectivelyConfigured(WebDAVConfig(serverUrl: "http://192")))
        #expect(!WebDAVConfigStore.isEffectivelyConfigured(
            WebDAVConfig(serverUrl: WebDAVConfigStore.defaultTemplateServerUrl)))
        #expect(WebDAVConfigStore.isEffectivelyConfigured(
            WebDAVConfig(
                serverUrl: WebDAVConfigStore.defaultTemplateServerUrl,
                username: "user@example.com",
                password: "app-password")))
        #expect(WebDAVConfigStore.isEffectivelyConfigured(
            WebDAVConfig(serverUrl: "http://192.168.1.5:5244/dav/")))
        #expect(WebDAVConfigStore.isEffectivelyConfigured(
            WebDAVConfig(serverUrl: "http://nas.local:8080/dav")))
    }

    // MARK: - v1.3.0 安全性与运行效率加固回归测试

    @Test("WebDAVConfigStore stores passwords in Keychain store and migrates legacy plaintext")
    func webDAVKeychainMigrationAndNoPlaintextInDefaults() throws {
        let suite = "legado_keychain_test_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let secretStore = MockWebDAVSecretStore()
        let config = WebDAVConfig(
            serverUrl: "https://dav.jianguoyun.com/dav/",
            username: "alice@example.com",
            password: "super-secret-password")

        WebDAVConfigStore.save(config, defaults: defaults, secretStore: secretStore)
        let rawDefaultsData = try #require(defaults.data(forKey: WebDAVConfigStore.storageKey))
        let persistedInDefaults = try JSONDecoder().decode(WebDAVConfig.self, from: rawDefaultsData)
        #expect(persistedInDefaults.password.isEmpty)

        let restored = WebDAVConfigStore.loadSavedIfConfigured(defaults: defaults, secretStore: secretStore)
        #expect(restored?.password == "super-secret-password")

        // 模拟旧版 UserDefaults 中残留的明文密码，读取时自动迁移至 Keychain 并擦除 UserDefaults 明文
        let legacyStore = MockWebDAVSecretStore()
        let legacyConfig = WebDAVConfig(
            serverUrl: "https://dav.jianguoyun.com/dav/",
            username: "bob@example.com",
            password: "legacy-plaintext-password")
        defaults.set(try JSONEncoder().encode(legacyConfig), forKey: WebDAVConfigStore.storageKey)

        let migrated = WebDAVConfigStore.loadForEditing(defaults: defaults, secretStore: legacyStore)
        #expect(migrated.password == "legacy-plaintext-password")
        let scrubbedData = try #require(defaults.data(forKey: WebDAVConfigStore.storageKey))
        let scrubbedConfig = try JSONDecoder().decode(WebDAVConfig.self, from: scrubbedData)
        #expect(scrubbedConfig.password.isEmpty)
        #expect(legacyStore.loadPassword(account: "webdav_primary_password") == "legacy-plaintext-password")
    }

    @Test("WebDAV redirect auth preservation blocks HTTPS downgrade, cross-port and cross-host")
    func webDAVRedirectAuthProtection() {
        let httpsOrigin = URL(string: "https://dav.example.com/dav/legado_backup.json")
        let httpsSameHost = URL(string: "https://dav.example.com:443/v2/legado_backup.json")
        let httpDowngrade = URL(string: "http://dav.example.com/dav/legado_backup.json")
        let crossPort = URL(string: "https://dav.example.com:8443/dav/legado_backup.json")
        let crossHost = URL(string: "https://evil.example.org/dav/legado_backup.json")
        let fileScheme = URL(string: "file:///etc/passwd")

        #expect(WebDAVClient.shouldPreserveAuth(from: httpsOrigin, to: httpsSameHost))
        #expect(!WebDAVClient.shouldPreserveAuth(from: httpsOrigin, to: httpDowngrade))
        #expect(!WebDAVClient.shouldPreserveAuth(from: httpsOrigin, to: crossPort))
        #expect(!WebDAVClient.shouldPreserveAuth(from: httpsOrigin, to: crossHost))
        #expect(!WebDAVClient.shouldPreserveAuth(from: httpsOrigin, to: fileScheme))
    }

    @Test("ZipArchiveReader, WebDAVSyncHelper and LocalFontManager reject path traversal and oversized blobs")
    func zipArchiveAndPathTraversalSecurityGuards() throws {
        let zipData = makeMinimalZipArchive(entries: [
            (name: "safe.txt", payload: Data("hello".utf8), forgedUncompressedSize: nil),
            (name: "../../escape.txt", payload: Data("bad".utf8), forgedUncompressedSize: nil),
            (name: "bomb.bin", payload: Data("boom".utf8), forgedUncompressedSize: UInt32(64 * 1024 * 1024)),
        ])
        let reader = try ZipArchiveReader(data: zipData)
        #expect(reader.readFile(at: "safe.txt") == Data("hello".utf8))
        #expect(reader.readFile(at: "../../escape.txt") == nil)
        #expect(reader.readFile(at: "bomb.bin") == nil)
        #expect(!reader.entries.contains { $0.path.contains("..") })

        #expect(!WebDAVSyncHelper.isSafeSingleFileName("../secret.legadobook"))
        #expect(!WebDAVSyncHelper.isSafeSingleFileName("sub/file.legadobook"))
        #expect(WebDAVSyncHelper.isSafeSingleFileName("abc123.legadobook"))
        #expect(WebDAVSyncHelper.sanitizeImageExtension("png") == "png")
        #expect(WebDAVSyncHelper.sanitizeImageExtension("jpg/../../x") == "jpg")

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FontSec_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let outsideFile = tempRoot.appendingPathComponent("outside.txt")
        try Data("keep".utf8).write(to: outsideFile)
        let manager = LocalFontManager(fontsDirectory: tempRoot.appendingPathComponent("Fonts", isDirectory: true))
        try manager.deleteFont(ImportedFont(
            id: "evil",
            displayName: "evil",
            postScriptName: "evil",
            fileName: "../outside.txt"))
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    @Test("PurifyContentUseCase and TxtTocParser cache regexes and handle invalid rules safely")
    func purifyAndTxtTocPerformanceConsistency() {
        let purify = PurifyContentUseCase()
        let invalidRule = ReplaceRule(name: "Bad", pattern: "[unclosed", replacement: "", isRegex: true)
        let validRule = ReplaceRule(name: "Ad", pattern: "广告文本", replacement: "", isRegex: false)
        let cleaned = purify.processContent(
            "第一章 初见\n正文第一段广告文本。",
            chapterTitle: "第一章 初见",
            rules: [invalidRule, validRule],
            enableReplace: true,
            removeSameTitle: true,
            reSegment: false)
        #expect(cleaned.contains("正文第一段。"))
        #expect(!cleaned.contains("广告文本"))

        let tocText = "第一章 开始\n第一段正文内容。\n第二章 转折\n第二段正文内容。"
        let chaptersA = TxtTocParser.parse(text: tocText)
        let chaptersB = TxtTocParser.parse(text: tocText)
        #expect(chaptersA == chaptersB)
        #expect(chaptersA.count == 2)
    }

    @Test("WebDAVBackupBundle cleanly decodes legacy backups that contain sources array")
    func webDAVBackupBundleIgnoresLegacySourcesField() throws {
        let legacyJson = """
        {
          "version": 2,
          "backupTime": "2026-11-22T10:00:00Z",
          "appVersion": "1.3.0",
          "books": [
            {
              "bookUrl": "local://legacy-book.txt",
              "tocUrl": "",
              "origin": "local",
              "originName": "本地导入",
              "name": "旧版备份书籍",
              "author": "本地导入",
              "latestChapterTime": 0,
              "durChapterIndex": 3,
              "durChapterPos": 120,
              "durChapterTime": 9000,
              "order": 0,
              "totalChapterNum": 10,
              "type": 0,
              "isPrivate": false,
              "canUpdate": true,
              "disableReadRecord": false,
              "originOrder": 0,
              "lastCheckTime": 0,
              "lastCheckCount": 0,
              "syncTime": 0,
              "config": { "fixedType": false }
            }
          ],
          "sources": [
            {
              "bookSourceUrl": "https://legacy.example.com",
              "bookSourceName": "旧版书源"
            }
          ],
          "replaceRules": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(WebDAVBackupBundle.self, from: Data(legacyJson.utf8))
        #expect(bundle.books.count == 1)
        #expect(bundle.books.first?.name == "旧版备份书籍")
        #expect(bundle.books.first?.durChapterIndex == 3)
        #expect(bundle.replaceRules.isEmpty)
    }

    @Test("Pure reader AppEnvironment creates core ViewModels without source or TTS dependencies")
    @MainActor
    func pureReaderAppEnvironmentSmoke() {
        let env = AppEnvironment(inMemory: true)
        let sampleBook = Book(
            bookUrl: "local://sample/test",
            origin: "local",
            originName: "本地导入",
            name: "纯粹阅读示例",
            author: "本地作者")
        let chapters = [Chapter(url: "local://sample/test/0", title: "第一章", bookUrl: sampleBook.bookUrl, index: 0)]

        _ = env.makeBookshelfViewModel()
        _ = env.makeBookDetailViewModel(book: sampleBook)
        _ = env.makeReaderViewModel(book: sampleBook)
        _ = env.makeBookSearchContentViewModel(book: sampleBook, chapters: chapters)
        _ = env.makeSettingsViewModel()
    }

    @Test("Builtin promo URL rule strips real promo domains without corrupting English sentences")
    func builtinPromoUrlRulePreservesEnglishWords() {
        let input = "Mr.Smith walked to St.Millom yesterday. "
            + "请访问 www.biquge123.com 或 test-site.vip/read 获取最新更新"
        let output = PurifyContentUseCase.shared.processContent(
            input,
            rules: PurifyContentUseCase.defaultRules,
            enableReplace: true,
            removeSameTitle: false,
            reSegment: false)
        #expect(output.contains("Mr.Smith"))
        #expect(output.contains("St.Millom"))
        #expect(!output.contains("www.biquge123.com"))
        #expect(!output.contains("test-site.vip/read"))
    }

    @Test("WebDAVSyncHelper mergeProgressItem blocks stale remote archive from rewinding newer local progress")
    func mergeProgressItemBlocksStaleRemoteArchive() {
        let newerLocal = Book(
            bookUrl: "local://test/novel.txt",
            name: "测试小说",
            author: "作者",
            durChapterIndex: 5,
            durChapterPos: 180,
            durChapterTime: 20_000)
        let staleRemote = WebDAVBookProgress(
            bookUrl: "local://other/novel.txt",
            name: "测试小说",
            author: "作者",
            durChapterIndex: 2,
            durChapterPos: 0,
            durChapterTitle: "第二章",
            durChapterTime: 10_000)

        #expect(WebDAVSyncHelper.mergeProgressItem(staleRemote, into: newerLocal, preferRemote: true) == nil)

        let unreadLocal = Book(
            bookUrl: "local://test/novel.txt",
            name: "测试小说",
            author: "作者",
            durChapterIndex: 0,
            durChapterPos: 0,
            durChapterTime: 20_000)
        let restored = WebDAVSyncHelper.mergeProgressItem(staleRemote, into: unreadLocal, preferRemote: true)
        #expect(restored?.durChapterIndex == 2)
        #expect(restored?.durChapterTitle == "第二章")
    }

    @Test("TxtTocRuleStore imports multiple rules without numeric id without overwriting")
    func txtTocRuleStoreImportsRulesWithoutId() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestTxtTocRules_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storageUrl = tempDir.appendingPathComponent("txt_toc_rules.json")
        let store = TxtTocRuleStore(storageUrl: storageUrl)
        store.saveRules([])
        #expect(store.loadRules().isEmpty)

        let json = """
        [
          {"name": "卷规则", "rule": "^第[一二三]卷.*"},
          {"name": "节规则", "rule": "^第[0-9]+节.*"}
        ]
        """
        let count = try store.importLegadoJSON(Data(json.utf8))
        let loaded = store.loadRules()
        #expect(count == 2)
        #expect(loaded.count == 2)
        #expect(Set(loaded.map(\.id)).count == 2)
    }
}

private final class MockWebDAVSecretStore: WebDAVSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: String] = [:]

    func savePassword(_ password: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if password.isEmpty {
            secrets.removeValue(forKey: account)
        } else {
            secrets[account] = password
        }
        return true
    }

    func loadPassword(account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return secrets[account]
    }

    func deletePassword(account: String) {
        lock.lock()
        defer { lock.unlock() }
        secrets.removeValue(forKey: account)
    }
}

private func makeMinimalZipArchive(
    entries: [(name: String, payload: Data, forgedUncompressedSize: UInt32?)]) -> Data {
    var body = Data()
    var centralDir = Data()

    func appendUInt16(_ target: inout Data, _ val: UInt16) {
        var little = val.littleEndian
        withUnsafeBytes(of: &little) { target.append(contentsOf: $0) }
    }

    func appendUInt32(_ target: inout Data, _ val: UInt32) {
        var little = val.littleEndian
        withUnsafeBytes(of: &little) { target.append(contentsOf: $0) }
    }

    for entry in entries {
        let nameData = Data(entry.name.utf8)
        let localOffset = UInt32(body.count)

        appendUInt32(&body, 0x0403_4B50)
        body.append(Data(count: 22))
        appendUInt16(&body, UInt16(nameData.count))
        appendUInt16(&body, 0)
        body.append(nameData)
        body.append(entry.payload)

        appendUInt32(&centralDir, 0x0201_4B50)
        centralDir.append(Data(count: 6))
        appendUInt16(&centralDir, 0)
        centralDir.append(Data(count: 8))
        appendUInt32(&centralDir, UInt32(entry.payload.count))
        appendUInt32(&centralDir, entry.forgedUncompressedSize ?? UInt32(entry.payload.count))
        appendUInt16(&centralDir, UInt16(nameData.count))
        appendUInt16(&centralDir, 0)
        appendUInt16(&centralDir, 0)
        centralDir.append(Data(count: 8))
        appendUInt32(&centralDir, localOffset)
        centralDir.append(nameData)
    }

    let cdOffset = UInt32(body.count)
    let cdSize = UInt32(centralDir.count)
    var archive = body
    archive.append(centralDir)

    appendUInt32(&archive, 0x0605_4B50)
    archive.append(Data(count: 8))
    appendUInt32(&archive, cdSize)
    appendUInt32(&archive, cdOffset)
    appendUInt16(&archive, 0)
    return archive
}

private final class LockedStringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(_ initial: String?) {
        self.value = initial
    }

    func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: String?) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private final class MockWebDAVVirtualDrive: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var requestCount = 0
    private var updatedFlag = false
    private var simulatedGetStatusCode: Int?
    private var requireMkcolOnce = false
    private var mkcolCompleted = false
    private var recordedCalls: [String] = []

    var totalRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    var wasUpdated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return updatedFlag
    }

    func markUpdated() {
        lock.lock()
        updatedFlag = true
        lock.unlock()
    }

    func setSimulatedGetStatusCode(_ code: Int?) {
        lock.lock()
        simulatedGetStatusCode = code
        lock.unlock()
    }

    func setRequireMkcolOnce(_ required: Bool) {
        lock.lock()
        requireMkcolOnce = required
        mkcolCompleted = false
        lock.unlock()
    }

    func resetRecordedCalls() {
        lock.lock()
        recordedCalls.removeAll()
        lock.unlock()
    }

    func recordedCallsSnapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func getData(endingWith suffix: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return files.first(where: { $0.key.hasSuffix(suffix) })?.value
    }

    func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let method = request.httpMethod ?? "GET"
        let url = request.url!
        let path = url.path
        lock.lock()
        requestCount += 1
        recordedCalls.append("\(method):\(path)")
        let forcedGetCode = simulatedGetStatusCode
        let needsMkcol = requireMkcolOnce && !mkcolCompleted
        if method == "MKCOL" {
            mkcolCompleted = true
        }
        lock.unlock()

        switch method {
        case "MKCOL", "PROPFIND", "OPTIONS":
            let code = method == "PROPFIND" ? 207 : 200
            let resp = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (resp, Data())

        case "PUT":
            if needsMkcol {
                let conflict = HTTPURLResponse(url: url, statusCode: 409, httpVersion: nil, headerFields: nil)!
                return (conflict, Data())
            }
            let body = MockWebDAVURLProtocol.readBody(from: request)
            lock.lock()
            files[path] = body
            lock.unlock()
            let resp = HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (resp, Data())

        case "GET":
            if let forcedGetCode {
                let forcedResp = HTTPURLResponse(
                    url: url,
                    statusCode: forcedGetCode,
                    httpVersion: nil,
                    headerFields: nil)!
                return (forcedResp, Data())
            }
            lock.lock()
            let data = files[path]
            lock.unlock()
            if let data {
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, data)
            }
            let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (notFound, Data())

        default:
            let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (ok, Data())
        }
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
