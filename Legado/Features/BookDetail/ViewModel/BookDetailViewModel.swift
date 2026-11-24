import Foundation

/// 书籍详情视图模型 (MVI 架构状态中枢)
@MainActor
public final class BookDetailViewModel: BaseMVIViewModel<BookDetailState, BookDetailIntent, BookDetailEffect> {
    private let getBookDetailUseCase: GetBookDetailUseCase
    private let getBookTocUseCase: GetBookTocUseCase
    private let saveBookToShelfUseCase: SaveBookToShelfUseCase
    private let removeBookFromShelfUseCase: RemoveBookFromShelfUseCase
    private let bookRepository: BookRepository
    private let getBookmarksUseCase: GetBookmarksUseCase?
    private let deleteBookmarkUseCase: DeleteBookmarkUseCase?
    nonisolated(unsafe) private var checkShelfTask: Task<Void, Never>?
    nonisolated(unsafe) private var detailLoadTask: Task<Void, Never>?
    nonisolated(unsafe) private var shelfToggleTask: Task<Void, Never>?

    public init(
        book: Book,
        getBookDetailUseCase: GetBookDetailUseCase,
        getBookTocUseCase: GetBookTocUseCase,
        saveBookToShelfUseCase: SaveBookToShelfUseCase,
        removeBookFromShelfUseCase: RemoveBookFromShelfUseCase,
        bookRepository: BookRepository,
        getBookmarksUseCase: GetBookmarksUseCase? = nil,
        deleteBookmarkUseCase: DeleteBookmarkUseCase? = nil) {
        self.getBookDetailUseCase = getBookDetailUseCase
        self.getBookTocUseCase = getBookTocUseCase
        self.saveBookToShelfUseCase = saveBookToShelfUseCase
        self.removeBookFromShelfUseCase = removeBookFromShelfUseCase
        self.bookRepository = bookRepository
        self.getBookmarksUseCase = getBookmarksUseCase
        self.deleteBookmarkUseCase = deleteBookmarkUseCase

        super.init(initialState: BookDetailState(book: book))

        checkShelfStatus()
        send(.loadDetail)
    }

    deinit {
        checkShelfTask?.cancel()
        detailLoadTask?.cancel()
        shelfToggleTask?.cancel()
    }

    private func checkShelfStatus() {
        checkShelfTask?.cancel()
        checkShelfTask = Task { [weak self] in
            guard let self else { return }
            let existing = try? await self.bookRepository.getBook(by: self.state.book.bookUrl)
            guard !Task.isCancelled else { return }
            let inShelf = existing != nil
            self.updateState { state in
                state.isInBookshelf = inShelf
            }
        }
    }

    override public func send(_ intent: BookDetailIntent) {
        switch intent {
        case .loadDetail:
            loadBookDetailAndToc()

        case .toggleBookshelf:
            toggleShelf()

        case .openToc, .closeToc, .toggleTocReverse, .updateTocSearch,
             .selectChapter, .selectBookmark, .deleteBookmark:
            handleTocIntent(intent)
        }
    }

    private func handleTocIntent(_ intent: BookDetailIntent) {
        switch intent {
        case .openToc:
            updateState { $0.isTocPresented = true }
            emitEffect(.hapticFeedback)

        case .closeToc:
            updateState { $0.isTocPresented = false }

        case .toggleTocReverse:
            updateState { $0.isReverseToc.toggle() }
            emitEffect(.hapticFeedback)

        case let .updateTocSearch(text):
            updateState { $0.tocSearchText = text }

        case let .selectChapter(chapter):
            updateState { $0.isTocPresented = false }
            emitEffect(.navigateToReader(chapterIndex: chapter.index))

        case let .selectBookmark(bookmark):
            updateState { $0.isTocPresented = false }
            emitEffect(.navigateToBookmark(chapterIndex: bookmark.chapterIndex, offset: bookmark.chapterPos))

        case let .deleteBookmark(id):
            performDeleteBookmark(id: id)

        default:
            break
        }
    }

    private func performDeleteBookmark(id: String) {
        Task { [weak self] in
            guard let self else { return }
            try? await self.deleteBookmarkUseCase?.execute(id: id)
            let refreshed = await self.fetchBookmarks(for: self.state.book)
            self.updateState { $0.bookmarks = refreshed }
            self.emitEffect(.showToast("已移除书签"))
            self.emitEffect(.hapticFeedback)
        }
    }

    private func loadBookDetailAndToc() {
        detailLoadTask?.cancel()
        updateState { $0.isLoading = true }

        detailLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let updatedBook = try await self.getBookDetailUseCase.execute(book: self.state.book)
                let toc = try await self.getBookTocUseCase.execute(book: updatedBook, forceRefresh: true)
                let finalBook = (try? await self.bookRepository.getBook(by: updatedBook.bookUrl)) ?? updatedBook
                let inShelf = (try? await self.bookRepository.getBook(by: updatedBook.bookUrl)) != nil
                let bookmarks = await self.fetchBookmarks(for: finalBook)
                guard !Task.isCancelled else { return }

                self.updateState { state in
                    state.isLoading = false
                    state.book = finalBook
                    state.isInBookshelf = inShelf
                    state.chapters = toc
                    state.bookmarks = bookmarks
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.updateState { state in
                    state.isLoading = false
                    state.errorMessage = error.localizedDescription
                }
                self.emitEffect(.showToast("刷新详情失败: \(error.localizedDescription)"))
            }
        }
    }

    private func fetchBookmarks(for book: Book) async -> [Bookmark] {
        guard let getBookmarksUseCase else { return [] }
        return (try? await getBookmarksUseCase.execute(bookName: book.name, bookAuthor: book.author)) ?? []
    }

    private func toggleShelf() {
        shelfToggleTask?.cancel()
        shelfToggleTask = Task { [weak self] in
            guard let self else { return }
            do {
                if self.state.isInBookshelf {
                    try await self.removeBookFromShelfUseCase.execute(bookUrl: self.state.book.bookUrl)
                    self.updateState { state in
                        state.isInBookshelf = false
                    }
                    self.emitEffect(.showToast("已从书架移除"))
                } else {
                    try await self.saveBookToShelfUseCase.execute(self.state.book)
                    self.updateState { state in
                        state.isInBookshelf = true
                    }
                    self.emitEffect(.showToast("已成功加入书架"))
                }
                self.emitEffect(.hapticFeedback)
            } catch {
                self.emitEffect(.showToast("操作失败: \(error.localizedDescription)"))
            }
        }
    }
}
