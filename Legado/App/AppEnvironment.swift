import Combine
import Foundation
import SwiftData
import UIKit

/// 全局依赖注入环境容器
@MainActor
public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()

    public let modelContainerProvider: ModelContainerProvider
    public let bookRepository: BookRepository

    // UseCases
    public let saveBookToShelfUseCase: SaveBookToShelfUseCase
    public let getBookshelfUseCase: GetBookshelfUseCase
    public let removeBookFromShelfUseCase: RemoveBookFromShelfUseCase
    public let getBookDetailUseCase: GetBookDetailUseCase
    public let getBookTocUseCase: GetBookTocUseCase
    public let getChapterContentUseCase: GetChapterContentUseCase
    public let purifyContentUseCase: PurifyContentUseCase
    public let backupToWebDAVUseCase: BackupToWebDAVUseCase
    public let restoreFromWebDAVUseCase: RestoreFromWebDAVUseCase
    public let webDAVRealtimeSyncService: WebDAVRealtimeSyncService
    public let searchBookContentUseCase: SearchBookContentUseCase
    public let bookmarkRepository: BookmarkRepository
    public let getBookmarksUseCase: GetBookmarksUseCase
    public let saveBookmarkUseCase: SaveBookmarkUseCase
    public let deleteBookmarkUseCase: DeleteBookmarkUseCase
    public let bookGroupRepository: BookGroupRepository
    public let getBookGroupsUseCase: GetBookGroupsUseCase
    public let saveBookGroupUseCase: SaveBookGroupUseCase
    public let deleteBookGroupUseCase: DeleteBookGroupUseCase
    public let bookCacheRepository: BookCacheRepository
    public let manageBookCacheUseCase: ManageBookCacheUseCase
    public let importLocalBookUseCase: ImportLocalBookUseCase
    public let externalFileImportSubject = PassthroughSubject<Void, Never>()
    public let bookshelfRefreshSubject = PassthroughSubject<Void, Never>()
    public let rulesRefreshSubject = PassthroughSubject<Void, Never>()
    private var pendingExternalImportURLs: [URL] = []
    private static let sampleSeededDefaultsKey = "legado_did_seed_sample_bookshelf_v1"

    public init(inMemory: Bool = false) {
        let provider = ModelContainerProvider(inMemory: inMemory)
        self.modelContainerProvider = provider

        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)
        let bookmarkRepo = BookmarkRepositoryImpl(modelContainer: provider.container)
        let groupRepo = BookGroupRepositoryImpl(modelContainer: provider.container)
        let cacheRepo = BookCacheRepositoryImpl()

        self.bookRepository = bookRepo
        self.bookmarkRepository = bookmarkRepo
        self.bookGroupRepository = groupRepo
        self.bookCacheRepository = cacheRepo

        self.saveBookToShelfUseCase = SaveBookToShelfUseCase(bookRepository: bookRepo)
        self.getBookshelfUseCase = GetBookshelfUseCase(bookRepository: bookRepo)
        self.removeBookFromShelfUseCase = RemoveBookFromShelfUseCase(
            bookRepository: bookRepo,
            bookCacheRepository: cacheRepo,
            bookmarkRepository: bookmarkRepo)
        self.getBookDetailUseCase = GetBookDetailUseCase(bookRepository: bookRepo)
        self.getBookTocUseCase = GetBookTocUseCase(bookRepository: bookRepo)
        self.getChapterContentUseCase = GetChapterContentUseCase(cacheRepository: cacheRepo)
        self.manageBookCacheUseCase = ManageBookCacheUseCase(bookCacheRepository: cacheRepo)

        self.purifyContentUseCase = PurifyContentUseCase()
        self.backupToWebDAVUseCase = BackupToWebDAVUseCase(
            bookRepository: bookRepo,
            bookmarkRepository: bookmarkRepo,
            bookCacheRepository: cacheRepo,
            bookGroupRepository: groupRepo)
        self.restoreFromWebDAVUseCase = RestoreFromWebDAVUseCase(
            bookRepository: bookRepo,
            bookmarkRepository: bookmarkRepo,
            bookCacheRepository: cacheRepo,
            bookGroupRepository: groupRepo)
        self.webDAVRealtimeSyncService = WebDAVRealtimeSyncService(
            bookRepository: bookRepo,
            backupUseCase: self.backupToWebDAVUseCase,
            configProvider: { inMemory ? nil : WebDAVConfigStore.loadSavedIfConfigured() },
            backgroundTaskProvider: inMemory ? nil : Self.makeBackgroundTaskStarter())
        self.searchBookContentUseCase = SearchBookContentUseCase()
        self.getBookmarksUseCase = GetBookmarksUseCase(bookmarkRepository: bookmarkRepo)
        self.saveBookmarkUseCase = SaveBookmarkUseCase(bookmarkRepository: bookmarkRepo)
        self.deleteBookmarkUseCase = DeleteBookmarkUseCase(bookmarkRepository: bookmarkRepo)
        self.getBookGroupsUseCase = GetBookGroupsUseCase(groupRepository: groupRepo)
        self.saveBookGroupUseCase = SaveBookGroupUseCase(groupRepository: groupRepo)
        self.deleteBookGroupUseCase = DeleteBookGroupUseCase(groupRepository: groupRepo)
        self.importLocalBookUseCase = ImportLocalBookUseCase(
            bookRepository: bookRepo,
            bookCacheRepository: cacheRepo)
        configurePostInit(inMemory: inMemory)
    }

    private func configurePostInit(inMemory: Bool) {
        self.webDAVRealtimeSyncService.onBookshelfUpdated = { [weak self] in
            self?.notifyBookshelfNeedsRefresh()
        }
        self.webDAVRealtimeSyncService.onRulesUpdated = { [weak self] in
            self?.notifyRulesNeedsRefresh()
        }
        if !inMemory {
            LocalFontManager.shared.registerAllStoredFonts()
            let launchArgs = ProcessInfo.processInfo.arguments
            let isUIDemo = launchArgs.contains("--open-reader-demo") || launchArgs.contains("--open-reader-hud")
            if !UserDefaults.standard.bool(forKey: Self.sampleSeededDefaultsKey) || isUIDemo {
                primeSampleChapterCache()
                seedInitialDataIfNeeded()
            }
        }
    }

    private func primeSampleChapterCache() {
        let sampleBookUrl = "local://sample/circle_of_inevitability"
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
            bookUrl: sampleBookUrl,
            index: 0)
    }

    private func seedInitialDataIfNeeded() {
        Task {
            await seedSampleBookshelfIfNeeded()
        }
    }

    /// 创建书籍详情 ViewModel
    public func makeBookDetailViewModel(book: Book) -> BookDetailViewModel {
        BookDetailViewModel(
            book: book,
            getBookDetailUseCase: getBookDetailUseCase,
            getBookTocUseCase: getBookTocUseCase,
            saveBookToShelfUseCase: saveBookToShelfUseCase,
            removeBookFromShelfUseCase: removeBookFromShelfUseCase,
            bookRepository: bookRepository,
            getBookmarksUseCase: getBookmarksUseCase,
            deleteBookmarkUseCase: deleteBookmarkUseCase)
    }

    /// 创建书架 ViewModel
    public func makeBookshelfViewModel() -> BookshelfViewModel {
        BookshelfViewModel(
            getBookshelfUseCase: getBookshelfUseCase,
            removeBookFromShelfUseCase: removeBookFromShelfUseCase,
            saveBookToShelfUseCase: saveBookToShelfUseCase,
            getBookGroupsUseCase: getBookGroupsUseCase,
            saveBookGroupUseCase: saveBookGroupUseCase,
            deleteBookGroupUseCase: deleteBookGroupUseCase,
            importLocalBookUseCase: importLocalBookUseCase,
            layoutDefaults: .standard,
            realtimeSyncService: webDAVRealtimeSyncService,
            bookmarkRepository: bookmarkRepository)
    }

    /// 创建阅读器 ViewModel
    public func makeReaderViewModel(
        book: Book,
        initialChapterIndex: Int? = nil,
        initialOffset: Int? = nil,
        showHUDInitially: Bool = false) -> ReaderViewModel {
        ReaderViewModel(
            book: book,
            initialChapterIndex: initialChapterIndex,
            initialOffset: initialOffset,
            showHUDInitially: showHUDInitially,
            getChapterContentUseCase: getChapterContentUseCase,
            getBookTocUseCase: getBookTocUseCase,
            bookRepository: bookRepository,
            getBookmarksUseCase: getBookmarksUseCase,
            saveBookmarkUseCase: saveBookmarkUseCase,
            deleteBookmarkUseCase: deleteBookmarkUseCase,
            realtimeSyncService: webDAVRealtimeSyncService)
    }

    /// 创建系统设置 ViewModel
    public func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            backupUseCase: backupToWebDAVUseCase,
            restoreUseCase: restoreFromWebDAVUseCase,
            manageBookCacheUseCase: manageBookCacheUseCase,
            realtimeSyncService: webDAVRealtimeSyncService,
            rulesRefreshPublisher: rulesRefreshSubject.eraseToAnyPublisher(),
            onBookshelfUpdated: { [weak self] in
                self?.notifyBookshelfNeedsRefresh()
            })
    }

    /// 通知书架重新从数据库加载最新阅读进度与书单
    public func notifyBookshelfNeedsRefresh() {
        bookshelfRefreshSubject.send(())
    }

    /// 通知阅读器与设置页重新加载云端最新同步的规则与排版配置
    public func notifyRulesNeedsRefresh() {
        rulesRefreshSubject.send(())
    }

    private static func makeBackgroundTaskStarter() -> RealtimeBackgroundTaskStarter {
        { onExpire in
            let state = RealtimeBackgroundTaskHolder()
            state.taskId = UIApplication.shared.beginBackgroundTask(withName: "LegadoWebDAVRealtimeSync") {
                Task { @MainActor in
                    onExpire()
                    state.end()
                }
            }
            return {
                state.end()
            }
        }
    }

    /// 创建正文全文搜索 ViewModel
    public func makeBookSearchContentViewModel(
        book: Book,
        chapters: [Chapter]) -> BookSearchContentViewModel {
        BookSearchContentViewModel(
            book: book,
            chapters: chapters,
            getChapterContentUseCase: getChapterContentUseCase,
            searchUseCase: searchBookContentUseCase)
    }

    /// 暂存外部“用 Legado 打开”的文件链接并立即复制至安全临时区（防安全作用域过期与 Inbox 残留）
    public func enqueueExternalImport(_ url: URL) {
        let staged = stageExternalImportURL(url)
        pendingExternalImportURLs.append(staged)
        externalFileImportSubject.send(())
    }

    private func stageExternalImportURL(_ sourceUrl: URL) -> URL {
        let fileManager = FileManager.default
        let stagingDir = fileManager.temporaryDirectory
            .appendingPathComponent("LegadoImportStaging/\(UUID().uuidString)", isDirectory: true)
        let targetUrl = stagingDir.appendingPathComponent(sourceUrl.lastPathComponent)

        let accessing = sourceUrl.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceUrl.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceUrl, to: targetUrl)
            if sourceUrl.path.contains("/Documents/Inbox/") {
                try? fileManager.removeItem(at: sourceUrl)
            }
            return targetUrl
        } catch {
            return sourceUrl
        }
    }

    /// 取出待导入的外部文件链接
    public func consumePendingImportURLs() -> [URL] {
        let urls = pendingExternalImportURLs
        pendingExternalImportURLs.removeAll()
        return urls
    }
}

@MainActor
private final class RealtimeBackgroundTaskHolder {
    var taskId: UIBackgroundTaskIdentifier = .invalid
    private var ended = false

    func end() {
        guard !ended, taskId != .invalid else { return }
        ended = true
        let current = taskId
        taskId = .invalid
        UIApplication.shared.endBackgroundTask(current)
    }
}
