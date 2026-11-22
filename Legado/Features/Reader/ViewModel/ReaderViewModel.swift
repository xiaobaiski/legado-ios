import Foundation
import UIKit

/// 阅读器核心控制器 (MVI 架构)
@MainActor
public final class ReaderViewModel: BaseMVIViewModel<ReaderState, ReaderIntent, ReaderEffect> {
    let getChapterContentUseCase: GetChapterContentUseCase
    private let getBookTocUseCase: GetBookTocUseCase
    private let bookRepository: BookRepository
    private let textLayoutEngine: TextLayoutEngine
    let getBookmarksUseCase: GetBookmarksUseCase?
    let saveBookmarkUseCase: SaveBookmarkUseCase?
    let deleteBookmarkUseCase: DeleteBookmarkUseCase?
    nonisolated(unsafe) var autoPageTask: Task<Void, Never>?
    nonisolated(unsafe) private var loadChapterTask: Task<Void, Never>?
    nonisolated(unsafe) private var repaginateTask: Task<Void, Never>?
    nonisolated(unsafe) private var loadTocTask: Task<Void, Never>?
    private let initialOffsetToRestore: Int?

    deinit {
        autoPageTask?.cancel()
        loadChapterTask?.cancel()
        repaginateTask?.cancel()
        loadTocTask?.cancel()
    }

    public init(
        book: Book,
        initialChapterIndex: Int? = nil,
        showHUDInitially: Bool = false,
        getChapterContentUseCase: GetChapterContentUseCase,
        getBookTocUseCase: GetBookTocUseCase,
        bookRepository: BookRepository,
        textLayoutEngine: TextLayoutEngine = .shared,
        getBookmarksUseCase: GetBookmarksUseCase? = nil,
        saveBookmarkUseCase: SaveBookmarkUseCase? = nil,
        deleteBookmarkUseCase: DeleteBookmarkUseCase? = nil) {
        self.getChapterContentUseCase = getChapterContentUseCase
        self.getBookTocUseCase = getBookTocUseCase
        self.bookRepository = bookRepository
        self.textLayoutEngine = textLayoutEngine
        self.getBookmarksUseCase = getBookmarksUseCase
        self.saveBookmarkUseCase = saveBookmarkUseCase
        self.deleteBookmarkUseCase = deleteBookmarkUseCase

        let startChapter = initialChapterIndex ?? book.durChapterIndex
        let shouldRestoreOffset = (initialChapterIndex == nil || initialChapterIndex == book.durChapterIndex)
            && book.durChapterPos > 0
        self.initialOffsetToRestore = shouldRestoreOffset ? book.durChapterPos : nil

        super.init(initialState: ReaderState(
            book: book,
            currentChapterIndex: startChapter,
            config: ReaderConfigStore.load(),
            isHUDVisible: showHUDInitially,
            importedFonts: LocalFontManager.shared.listImportedFonts()))

        loadTocAndStartReading()
        loadBookmarks()
    }

    private func loadTocAndStartReading() {
        loadTocTask?.cancel()
        loadTocTask = Task { [weak self] in
            guard let self else { return }
            let book = self.state.book
            let local = (try? await self.bookRepository.getChapters(for: book.bookUrl)) ?? []
            guard !Task.isCancelled else { return }

            if !local.isEmpty {
                self.updateState { state in
                    state.chapters = local
                }
                self.loadChapterContent(
                    chapterIndex: self.state.currentChapterIndex,
                    targetPageIndex: 0,
                    targetOffset: self.initialOffsetToRestore)
                return
            }

            var toc = (try? await self.getBookTocUseCase.execute(book: book)) ?? []
            guard !Task.isCancelled else { return }

            if toc.isEmpty, book.isLocalFile {
                let message = "本机未找到该本地书籍的正文文件，请在本机重新导入或开启 WebDAV「本地书籍文件」同步恢复"
                self.updateState { state in
                    state.isLoading = false
                    state.chapters = []
                    state.pages = []
                    state.toastMessage = message
                }
                self.emitEffect(.showToast(message))
                return
            }

            if toc.isEmpty {
                toc = [
                    Chapter(
                        url: book.bookUrl,
                        title: book.durChapterTitle ?? "第一章 宿命之始",
                        bookUrl: book.bookUrl,
                        index: 0),
                ]
            }
            self.updateState { state in
                state.chapters = toc
            }
            self.loadChapterContent(
                chapterIndex: self.state.currentChapterIndex,
                targetPageIndex: 0,
                targetOffset: self.initialOffsetToRestore)
        }
    }

    override public func send(_ intent: ReaderIntent) {
        switch intent {
        case .loadChapter, .nextPage, .prevPage, .jumpToPage, .jumpToChapterAndOffset:
            handleNavigationIntent(intent)

        case .toggleHUD, .hideHUD, .openToc, .closeToc:
            handleHUDIntent(intent)

        case .openConfig, .closeConfig, .changeFontSize, .selectTheme, .selectPageTurnMode:
            handleConfigIntent(intent)

        case .updateConfig, .resetConfig, .openMoreSettings, .closeMoreSettings,
             .toggleAutoPage, .setAutoPageInterval, .importFonts, .selectCustomFont,
             .deleteImportedFont, .refreshImportedFonts, .repaginate:
            handleExtendedConfigIntent(intent)

        case let .updateScreenBounds(rect):
            if state.screenBounds != rect, rect.width > 50 {
                updateState { $0.screenBounds = rect }
                repaginateCurrentChapter()
            }

        case let .switchSource(updatedBook, newToc, matchedChapterIndex):
            updateState {
                $0.book = updatedBook
                $0.chapters = newToc
                $0.currentChapterIndex = matchedChapterIndex
                $0.pages = []
                $0.currentPageIndex = 0
            }
            loadChapterContent(chapterIndex: matchedChapterIndex, targetPageIndex: 0)
            emitEffect(.showToast("已成功换源至 [\(updatedBook.originName)]"))
            emitHapticIfEnabled()

        case .toggleBookmark, .addBookmark, .deleteBookmark, .loadBookmarks:
            handleBookmarkIntent(intent)
        }
    }

    private func handleNavigationIntent(_ intent: ReaderIntent) {
        switch intent {
        case let .loadChapter(index):
            loadChapterContent(chapterIndex: index, targetPageIndex: 0)

        case let .jumpToChapterAndOffset(chapterIndex, matchOffset):
            loadChapterContent(chapterIndex: chapterIndex, targetPageIndex: 0, targetOffset: matchOffset)

        case .nextPage:
            handleNextPage()

        case .prevPage:
            handlePrevPage()

        case let .jumpToPage(index):
            if index >= 0, index < state.pages.count {
                updateState { $0.currentPageIndex = index }
                saveReadingProgress()
                emitHapticIfEnabled()
            }

        default:
            break
        }
    }

    private func handleHUDIntent(_ intent: ReaderIntent) {
        switch intent {
        case .toggleHUD:
            updateState { $0.isHUDVisible.toggle() }
            emitHapticIfEnabled()

        case .hideHUD:
            updateState {
                $0.isHUDVisible = false
                $0.isConfigSheetVisible = false
            }

        case .openToc:
            updateState {
                $0.isHUDVisible = false
                $0.isTocSheetVisible = true
            }
            emitHapticIfEnabled()

        case .closeToc:
            updateState { $0.isTocSheetVisible = false }

        default:
            break
        }
    }

    private func handleConfigIntent(_ intent: ReaderIntent) {
        switch intent {
        case .openConfig:
            updateState { $0.isConfigSheetVisible = true }
            emitHapticIfEnabled()

        case .closeConfig:
            updateState { $0.isConfigSheetVisible = false }

        case let .changeFontSize(delta):
            let newSize = min(max(state.config.fontSize + delta, 12), 36)
            var newConfig = state.config
            newConfig.fontSize = newSize
            applyNewConfig(newConfig)

        case let .selectTheme(theme):
            var newConfig = state.config
            newConfig.theme = theme
            applyNewConfig(newConfig)

        case let .selectPageTurnMode(mode):
            var newConfig = state.config
            newConfig.pageTurnMode = mode
            applyNewConfig(newConfig)

        default:
            break
        }
    }

    private func loadChapterContent(
        chapterIndex: Int,
        targetPageIndex: Int,
        targetOffset: Int? = nil) {
        guard chapterIndex >= 0, chapterIndex < state.chapters.count else { return }

        loadChapterTask?.cancel()
        repaginateTask?.cancel()
        let chapter = state.chapters[chapterIndex]
        let bookOrigin = state.book.origin
        let bookName = state.book.name
        let configSnapshot = state.config
        let defaultBounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let layoutBounds = state.screenBounds.width > 50 ? state.screenBounds : defaultBounds
        let engine = textLayoutEngine

        updateState {
            $0.isLoading = true
            $0.currentChapterIndex = chapterIndex
        }

        loadChapterTask = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await self.getChapterContentUseCase.execute(
                    chapter: chapter,
                    origin: bookOrigin)
                guard !Task.isCancelled else { return }

                if self.handleMissingLocalChapterIfNeeded(chapter: chapter, content: content) {
                    return
                }

                let pages = await Task.detached(priority: .userInitiated) {
                    engine.paginate(
                        chapterTitle: chapter.title,
                        content: content,
                        chapterIndex: chapterIndex,
                        bounds: layoutBounds,
                        config: configSnapshot,
                        bookName: bookName,
                        bookOrigin: bookOrigin)
                }.value
                guard !Task.isCancelled else { return }

                let safePageIndex: Int
                if let offset = targetOffset {
                    safePageIndex = Self.pageIndex(forOffset: offset, in: pages)
                } else {
                    safePageIndex = min(max(targetPageIndex, 0), max(pages.count - 1, 0))
                }

                self.updateState { state in
                    state.isLoading = false
                    state.pages = pages
                    state.currentPageIndex = safePageIndex
                }

                self.saveReadingProgress()

                if chapterIndex + 1 < self.state.chapters.count {
                    let nextChapter = self.state.chapters[chapterIndex + 1]
                    self.getChapterContentUseCase.preload(chapter: nextChapter, origin: bookOrigin)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.updateState { state in
                    state.isLoading = false
                    state.toastMessage = "加载章节失败: \(error.localizedDescription)"
                }
                self.emitEffect(.showToast("章节加载失败: \(error.localizedDescription)"))
            }
        }
    }

    private func handleMissingLocalChapterIfNeeded(chapter: Chapter, content: String) -> Bool {
        guard state.book.isLocalFile,
              content.isEmpty,
              !chapter.isVolume,
              !getChapterContentUseCase.isChapterCached(bookUrl: chapter.bookUrl, index: chapter.index) else {
            return false
        }
        let message = "本机缺失章节正文文件，请在本机重新导入或通过 WebDAV「本地书籍文件」同步恢复"
        updateState { state in
            state.isLoading = false
            state.pages = []
            state.toastMessage = message
        }
        emitEffect(.showToast(message))
        return true
    }

    private func handleNextPage() {
        let step = state.config.isDualPageActive(for: state.screenBounds) ? 2 : 1
        let alignedCurrent = step == 2 ? (state.currentPageIndex - state.currentPageIndex % 2) : state.currentPageIndex
        if alignedCurrent + step < state.pages.count {
            updateState { $0.currentPageIndex = alignedCurrent + step }
            saveReadingProgress()
            emitHapticIfEnabled()
        } else if state.currentChapterIndex + 1 < state.chapters.count {
            // 翻入下一章第一页
            loadChapterContent(chapterIndex: state.currentChapterIndex + 1, targetPageIndex: 0)
            emitHapticIfEnabled()
        } else {
            emitEffect(.showToast("已经是最后一页了"))
        }
    }

    private func handlePrevPage() {
        let step = state.config.isDualPageActive(for: state.screenBounds) ? 2 : 1
        let alignedCurrent = step == 2 ? (state.currentPageIndex - state.currentPageIndex % 2) : state.currentPageIndex
        if alignedCurrent - step >= 0 {
            updateState { $0.currentPageIndex = alignedCurrent - step }
            saveReadingProgress()
            emitHapticIfEnabled()
        } else if alignedCurrent > 0 {
            updateState { $0.currentPageIndex = 0 }
            saveReadingProgress()
            emitHapticIfEnabled()
        } else if state.currentChapterIndex > 0 {
            // 翻入上一章最后一页
            loadChapterContent(chapterIndex: state.currentChapterIndex - 1, targetPageIndex: Int.max)
            emitHapticIfEnabled()
        } else {
            emitEffect(.showToast("已经是第一页了"))
        }
    }

    func repaginateCurrentChapter() {
        guard let chapter = state.currentChapter else { return }
        repaginateTask?.cancel()
        let currentOffset = state.currentPage?.textRange.location ?? 0
        let chapterIndex = state.currentChapterIndex
        let bookOrigin = state.book.origin
        let bookName = state.book.name
        let configSnapshot = state.config
        let defaultBounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let layoutBounds = state.screenBounds.width > 50 ? state.screenBounds : defaultBounds
        let engine = textLayoutEngine

        repaginateTask = Task { [weak self] in
            guard let self else { return }
            guard let content = try? await self.getChapterContentUseCase.execute(
                chapter: chapter,
                origin: bookOrigin),
                  !Task.isCancelled else {
                return
            }

            let pages = await Task.detached(priority: .userInitiated) {
                engine.paginate(
                    chapterTitle: chapter.title,
                    content: content,
                    chapterIndex: chapterIndex,
                    bounds: layoutBounds,
                    config: configSnapshot,
                    bookName: bookName,
                    bookOrigin: bookOrigin)
            }.value
            guard !Task.isCancelled else { return }

            let preservedPage = Self.pageIndex(forOffset: currentOffset, in: pages)
            self.updateState { state in
                state.pages = pages
                state.currentPageIndex = preservedPage
            }
        }
    }

    static func pageIndex(forOffset offset: Int, in pages: [ReaderPage]) -> Int {
        guard !pages.isEmpty else { return 0 }
        if let exact = pages.firstIndex(where: { page in
            offset >= page.textRange.location &&
                offset < (page.textRange.location + max(page.textRange.length, 1))
        }) {
            return exact
        }
        if let last = pages.last, offset >= last.textRange.location {
            return pages.count - 1
        }
        return 0
    }

    func applyNewConfig(_ newConfig: ReaderConfig, triggerHaptic: Bool = true) {
        let oldConfig = state.config
        updateState { $0.config = newConfig }
        ReaderConfigStore.save(newConfig)
        if newConfig.requiresRepagination(comparedTo: oldConfig) {
            repaginateCurrentChapter()
        }
        if triggerHaptic {
            emitHapticIfEnabled()
        }
    }

    func emitHapticIfEnabled() {
        if state.config.isHapticEnabled {
            emitEffect(.hapticFeedback)
        }
    }

    private func saveReadingProgress() {
        guard let chapter = state.currentChapter else { return }
        var updated = state.book
        updated.durChapterIndex = state.currentChapterIndex
        updated.durChapterPos = state.currentPage?.textRange.location ?? 0
        updated.durChapterTitle = chapter.title
        updated.durChapterTime = Int64(Date().timeIntervalSince1970 * 1000)

        Task {
            try? await bookRepository.saveBook(updated)
        }
    }
}
