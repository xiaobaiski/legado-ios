import Foundation
import UIKit

/// 阅读器核心控制器 (MVI 架构)
@MainActor
public final class ReaderViewModel: BaseMVIViewModel<ReaderState, ReaderIntent, ReaderEffect> {
    let getChapterContentUseCase: GetChapterContentUseCase
    let getBookTocUseCase: GetBookTocUseCase
    let bookRepository: BookRepository
    let textLayoutEngine: TextLayoutEngine
    let getBookmarksUseCase: GetBookmarksUseCase?
    let saveBookmarkUseCase: SaveBookmarkUseCase?
    let deleteBookmarkUseCase: DeleteBookmarkUseCase?
    nonisolated(unsafe) var autoPageTask: Task<Void, Never>?
    nonisolated(unsafe) var loadChapterTask: Task<Void, Never>?
    nonisolated(unsafe) var repaginateTask: Task<Void, Never>?
    nonisolated(unsafe) var loadTocTask: Task<Void, Never>?
    nonisolated(unsafe) var remoteSyncTask: Task<Void, Never>?
    nonisolated(unsafe) var loadBookmarksTask: Task<Void, Never>?
    nonisolated(unsafe) var scrollSaveTask: Task<Void, Never>?
    let realtimeSyncService: WebDAVRealtimeSyncService?
    let explicitInitialChapterIndex: Int?
    var pendingRestoreOffset: Int?
    var pendingTargetPageIndex: Int?
    var navigationGeneration = 0

    deinit {
        autoPageTask?.cancel()
        loadChapterTask?.cancel()
        repaginateTask?.cancel()
        loadTocTask?.cancel()
        remoteSyncTask?.cancel()
        loadBookmarksTask?.cancel()
        scrollSaveTask?.cancel()
    }

    public init(
        book: Book,
        initialChapterIndex: Int? = nil,
        initialOffset: Int? = nil,
        showHUDInitially: Bool = false,
        getChapterContentUseCase: GetChapterContentUseCase,
        getBookTocUseCase: GetBookTocUseCase,
        bookRepository: BookRepository,
        textLayoutEngine: TextLayoutEngine = .shared,
        getBookmarksUseCase: GetBookmarksUseCase? = nil,
        saveBookmarkUseCase: SaveBookmarkUseCase? = nil,
        deleteBookmarkUseCase: DeleteBookmarkUseCase? = nil,
        realtimeSyncService: WebDAVRealtimeSyncService? = nil) {
        self.getChapterContentUseCase = getChapterContentUseCase
        self.getBookTocUseCase = getBookTocUseCase
        self.bookRepository = bookRepository
        self.textLayoutEngine = textLayoutEngine
        self.getBookmarksUseCase = getBookmarksUseCase
        self.saveBookmarkUseCase = saveBookmarkUseCase
        self.deleteBookmarkUseCase = deleteBookmarkUseCase
        self.realtimeSyncService = realtimeSyncService
        self.explicitInitialChapterIndex = initialChapterIndex

        let startChapter = initialChapterIndex ?? book.durChapterIndex
        let resolvedOffset: Int?
        if let initialOffset {
            resolvedOffset = initialOffset > 0 ? initialOffset : nil
        } else {
            let shouldRestoreOffset = (initialChapterIndex == nil || initialChapterIndex == book.durChapterIndex)
                && book.durChapterPos > 0
            resolvedOffset = shouldRestoreOffset ? book.durChapterPos : nil
        }
        self.pendingRestoreOffset = resolvedOffset

        super.init(initialState: ReaderState(
            book: book,
            currentChapterIndex: startChapter,
            config: ReaderConfigStore.load(),
            isHUDVisible: showHUDInitially,
            importedFonts: LocalFontManager.shared.listImportedFonts()))

        loadTocAndStartReading()
        loadBookmarks()
    }

    override public func send(_ intent: ReaderIntent) {
        switch intent {
        case .loadChapter, .nextPage, .prevPage, .jumpToPage, .syncScrollOffset, .jumpToChapterAndOffset:
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
            handleUpdateScreenBounds(rect)

        case .toggleBookmark, .addBookmark, .deleteBookmark, .loadBookmarks:
            handleBookmarkIntent(intent)
        }
    }

    private func handleNavigationIntent(_ intent: ReaderIntent) {
        switch intent {
        case let .loadChapter(index):
            navigationGeneration += 1
            pendingRestoreOffset = nil
            pendingTargetPageIndex = 0
            loadChapterContent(chapterIndex: index, targetPageIndex: 0)
            if state.isAutoPaging { restartAutoPageTimer() }

        case let .jumpToChapterAndOffset(chapterIndex, matchOffset):
            navigationGeneration += 1
            pendingRestoreOffset = matchOffset
            pendingTargetPageIndex = nil
            loadChapterContent(chapterIndex: chapterIndex, targetPageIndex: 0, targetOffset: matchOffset)
            if state.isAutoPaging { restartAutoPageTimer() }

        case .nextPage:
            navigationGeneration += 1
            pendingRestoreOffset = nil
            pendingTargetPageIndex = nil
            handleNextPage()
            if state.isAutoPaging { restartAutoPageTimer() }

        case .prevPage:
            navigationGeneration += 1
            pendingRestoreOffset = nil
            pendingTargetPageIndex = nil
            handlePrevPage()
            if state.isAutoPaging { restartAutoPageTimer() }

        case let .jumpToPage(index):
            if index >= 0, index < state.pages.count {
                navigationGeneration += 1
                pendingRestoreOffset = nil
                pendingTargetPageIndex = nil
                updateState { $0.currentPageIndex = index }
                saveReadingProgress()
                emitHapticIfEnabled()
                if state.isAutoPaging { restartAutoPageTimer() }
            }

        case let .syncScrollOffset(offset):
            handleSyncScrollOffset(offset)

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
            applyNewConfig(newConfig, triggerHaptic: true)

        case let .selectTheme(theme):
            var newConfig = state.config
            newConfig.applyTheme(theme)
            applyNewConfig(newConfig, triggerHaptic: true)

        case let .selectPageTurnMode(mode):
            var newConfig = state.config
            newConfig.pageTurnMode = mode
            applyNewConfig(newConfig, triggerHaptic: true)

        default:
            break
        }
    }

    func loadChapterContent(
        chapterIndex: Int,
        targetPageIndex: Int,
        targetOffset: Int? = nil,
        persistProgress: Bool = true) {
        guard chapterIndex >= 0, chapterIndex < state.chapters.count else { return }

        loadChapterTask?.cancel()
        repaginateTask?.cancel()
        let chapter = state.chapters[chapterIndex]
        let bookOrigin = state.book.origin
        let bookName = state.book.name
        let configSnapshot = state.config
        let hasRealBounds = state.screenBounds.width > 50
        let defaultBounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let layoutBounds = hasRealBounds ? state.screenBounds : defaultBounds
        let engine = textLayoutEngine

        pendingRestoreOffset = targetOffset
        pendingTargetPageIndex = targetOffset == nil ? targetPageIndex : nil

        updateState {
            $0.isLoading = true
            if $0.currentChapterIndex != chapterIndex {
                $0.pages = []
            }
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

                let input = ChapterPaginationInput(
                    engine: engine,
                    chapterTitle: chapter.title,
                    content: content,
                    chapterIndex: chapterIndex,
                    bounds: layoutBounds,
                    config: configSnapshot,
                    bookName: bookName,
                    bookOrigin: bookOrigin)
                let pages = await Self.computePaginatedPages(input)
                guard !Task.isCancelled else { return }

                self.applyLoadedPages(
                    pages,
                    forChapterIndex: chapterIndex,
                    targetOffset: targetOffset,
                    targetPageIndex: targetPageIndex,
                    hasRealBounds: hasRealBounds,
                    persistProgress: persistProgress)
                self.preloadNextChapterIfAvailable(after: chapterIndex, origin: bookOrigin)
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
            loadChapterContent(chapterIndex: state.currentChapterIndex - 1, targetPageIndex: Int.max)
            emitHapticIfEnabled()
        } else {
            emitEffect(.showToast("已经是第一页了"))
        }
    }
}
