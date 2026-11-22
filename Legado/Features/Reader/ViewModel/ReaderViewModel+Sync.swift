import Foundation
import UIKit

// MARK: - 阅读进度加载、WebDAV 实时同步、分页计算与配置持久扩展

extension ReaderViewModel {
    func loadTocAndStartReading() {
        loadTocTask?.cancel()
        loadTocTask = Task { [weak self] in
            guard let self else { return }
            var book = self.state.book
            if self.explicitInitialChapterIndex == nil,
               let freshBook = try? await self.bookRepository.getBook(by: book.bookUrl) {
                book = freshBook
                self.pendingRestoreOffset = freshBook.durChapterPos > 0 ? freshBook.durChapterPos : nil
                self.updateState { state in
                    state.book = freshBook
                    state.currentChapterIndex = freshBook.durChapterIndex
                }
            }
            guard !Task.isCancelled else { return }

            let local = (try? await self.bookRepository.getChapters(for: book.bookUrl)) ?? []
            guard !Task.isCancelled else { return }

            var toc = local
            if toc.isEmpty {
                toc = (try? await self.getBookTocUseCase.execute(book: book)) ?? []
                guard !Task.isCancelled else { return }
            }

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

            let rawChapter = self.explicitInitialChapterIndex ?? book.durChapterIndex
            let clampedChapter = min(max(rawChapter, 0), max(toc.count - 1, 0))
            if clampedChapter != rawChapter {
                self.pendingRestoreOffset = nil
            }
            self.updateState { state in
                state.chapters = toc
                state.currentChapterIndex = clampedChapter
            }
            self.loadChapterContent(
                chapterIndex: clampedChapter,
                targetPageIndex: 0,
                targetOffset: self.pendingRestoreOffset,
                persistProgress: false)

            if self.explicitInitialChapterIndex == nil {
                self.startRealtimeProgressPull(for: book)
            }
        }
    }

    func startRealtimeProgressPull(for book: Book) {
        guard let realtimeSyncService else { return }
        remoteSyncTask?.cancel()
        remoteSyncTask = Task { [weak self] in
            guard let syncedBook = await realtimeSyncService.pullLatestProgressIfNeeded(for: book, force: true),
                  let self,
                  !Task.isCancelled,
                  !self.hasUserNavigated else {
                return
            }
            let totalChapters = max(self.state.chapters.count, 1)
            let targetIndex = min(max(syncedBook.durChapterIndex, 0), totalChapters - 1)
            let targetOffset = (targetIndex == syncedBook.durChapterIndex && syncedBook.durChapterPos > 0)
                ? syncedBook.durChapterPos
                : nil
            let currentOffset = self.state.currentPage?.textRange.location ?? 0
            if targetIndex == self.state.currentChapterIndex,
               abs((targetOffset ?? 0) - currentOffset) < 20 {
                self.updateState { $0.book = syncedBook }
                return
            }
            self.pendingRestoreOffset = targetOffset
            self.updateState { $0.book = syncedBook }
            self.loadChapterContent(
                chapterIndex: targetIndex,
                targetPageIndex: 0,
                targetOffset: targetOffset,
                persistProgress: false)
            let chapterLabel = syncedBook.durChapterTitle ?? "第 \(targetIndex + 1) 章"
            self.emitEffect(.showToast("已同步云端最新进度：\(chapterLabel)"))
        }
    }

    func repaginateCurrentChapter() {
        guard let chapter = state.currentChapter else { return }
        repaginateTask?.cancel()
        let currentOffset = pendingRestoreOffset ?? state.currentPage?.textRange.location ?? 0
        let chapterIndex = state.currentChapterIndex
        let bookOrigin = state.book.origin
        let bookName = state.book.name
        let configSnapshot = state.config
        let hasRealBounds = state.screenBounds.width > 50
        let defaultBounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let layoutBounds = hasRealBounds ? state.screenBounds : defaultBounds
        let input = ChapterPaginationInput(
            engine: textLayoutEngine,
            chapterTitle: chapter.title,
            content: "",
            chapterIndex: chapterIndex,
            bounds: layoutBounds,
            config: configSnapshot,
            bookName: bookName,
            bookOrigin: bookOrigin)

        repaginateTask = Task { [weak self] in
            guard let self else { return }
            guard let content = try? await self.getChapterContentUseCase.execute(
                chapter: chapter,
                origin: bookOrigin),
                  !Task.isCancelled else {
                return
            }

            let pages = await Self.computePaginatedPages(input.withContent(content))
            guard !Task.isCancelled else { return }

            let preservedPage = Self.pageIndex(forOffset: currentOffset, in: pages)
            self.updateState { state in
                state.pages = pages
                state.currentPageIndex = preservedPage
            }
            if self.state.screenBounds.width > 50 {
                self.pendingRestoreOffset = nil
            }
        }
    }

    static func computePaginatedPages(_ input: ChapterPaginationInput) async -> [ReaderPage] {
        await Task.detached(priority: .userInitiated) {
            input.engine.paginate(
                chapterTitle: input.chapterTitle,
                content: input.content,
                chapterIndex: input.chapterIndex,
                bounds: input.bounds,
                config: input.config,
                bookName: input.bookName,
                bookOrigin: input.bookOrigin)
        }.value
    }

    func applyLoadedPages(
        _ pages: [ReaderPage],
        targetOffset: Int?,
        targetPageIndex: Int,
        hasRealBounds: Bool,
        persistProgress: Bool) {
        let safePageIndex = Self.resolveTargetPageIndex(
            targetOffset: targetOffset,
            targetPageIndex: targetPageIndex,
            in: pages)
        updateState { state in
            state.isLoading = false
            state.pages = pages
            state.currentPageIndex = safePageIndex
        }
        if hasRealBounds {
            pendingRestoreOffset = nil
        }
        if persistProgress {
            saveReadingProgress()
        }
    }

    static func resolveTargetPageIndex(
        targetOffset: Int?,
        targetPageIndex: Int,
        in pages: [ReaderPage]) -> Int {
        if let offset = targetOffset {
            return pageIndex(forOffset: offset, in: pages)
        }
        return min(max(targetPageIndex, 0), max(pages.count - 1, 0))
    }

    func preloadNextChapterIfAvailable(after chapterIndex: Int, origin: String) {
        if chapterIndex + 1 < state.chapters.count {
            let nextChapter = state.chapters[chapterIndex + 1]
            getChapterContentUseCase.preload(chapter: nextChapter, origin: origin)
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
        realtimeSyncService?.scheduleRulesPush()
        if newConfig.requiresRepagination(comparedTo: oldConfig) {
            repaginateCurrentChapter()
        }
        if triggerHaptic {
            emitHapticIfEnabled()
        }
    }

    func flushRealtimeProgressSync() {
        realtimeSyncService?.flushPendingProgressPush()
    }

    func emitHapticIfEnabled() {
        if state.config.isHapticEnabled {
            emitEffect(.hapticFeedback)
        }
    }

    func saveReadingProgress() {
        guard !state.pages.isEmpty, let chapter = state.currentChapter else { return }
        var updated = state.book
        updated.durChapterIndex = state.currentChapterIndex
        updated.durChapterPos = state.currentPage?.textRange.location ?? 0
        updated.durChapterTitle = chapter.title
        updated.durChapterTime = Int64(Date().timeIntervalSince1970 * 1000)

        updateState { $0.book = updated }
        realtimeSyncService?.scheduleProgressPush(book: updated)

        let repository = bookRepository
        Task {
            try? await repository.saveBook(updated)
        }
    }
}

struct ChapterPaginationInput: @unchecked Sendable {
    let engine: TextLayoutEngine
    let chapterTitle: String
    let content: String
    let chapterIndex: Int
    let bounds: CGRect
    let config: ReaderConfig
    let bookName: String
    let bookOrigin: String

    func withContent(_ newContent: String) -> ChapterPaginationInput {
        ChapterPaginationInput(
            engine: engine,
            chapterTitle: chapterTitle,
            content: newContent,
            chapterIndex: chapterIndex,
            bounds: bounds,
            config: config,
            bookName: bookName,
            bookOrigin: bookOrigin)
    }
}
