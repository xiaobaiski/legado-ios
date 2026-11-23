import Foundation

/// 书架业务视图模型 (MVI 架构)
@MainActor
public final class BookshelfViewModel: BaseMVIViewModel<BookshelfState, BookshelfIntent, BookshelfEffect> {
    let getBookshelfUseCase: GetBookshelfUseCase
    let removeBookFromShelfUseCase: RemoveBookFromShelfUseCase
    let saveBookToShelfUseCase: SaveBookToShelfUseCase?
    private let getBookGroupsUseCase: GetBookGroupsUseCase?
    let saveBookGroupUseCase: SaveBookGroupUseCase?
    let deleteBookGroupUseCase: DeleteBookGroupUseCase?
    let importLocalBookUseCase: ImportLocalBookUseCase?
    private let realtimeSyncService: WebDAVRealtimeSyncService?
    private let layoutDefaults: UserDefaults?

    nonisolated(unsafe) var loadTask: Task<Void, Never>?
    nonisolated(unsafe) var refreshTask: Task<Void, Never>?
    nonisolated(unsafe) var importTask: Task<Void, Never>?
    nonisolated(unsafe) var mutationTask: Task<Void, Never>?

    deinit {
        loadTask?.cancel()
        refreshTask?.cancel()
        importTask?.cancel()
        mutationTask?.cancel()
    }

    public init(
        getBookshelfUseCase: GetBookshelfUseCase,
        removeBookFromShelfUseCase: RemoveBookFromShelfUseCase,
        saveBookToShelfUseCase: SaveBookToShelfUseCase? = nil,
        getBookGroupsUseCase: GetBookGroupsUseCase? = nil,
        saveBookGroupUseCase: SaveBookGroupUseCase? = nil,
        deleteBookGroupUseCase: DeleteBookGroupUseCase? = nil,
        importLocalBookUseCase: ImportLocalBookUseCase? = nil,
        layoutDefaults: UserDefaults? = nil,
        realtimeSyncService: WebDAVRealtimeSyncService? = nil) {
        self.getBookshelfUseCase = getBookshelfUseCase
        self.removeBookFromShelfUseCase = removeBookFromShelfUseCase
        self.saveBookToShelfUseCase = saveBookToShelfUseCase
        self.getBookGroupsUseCase = getBookGroupsUseCase
        self.saveBookGroupUseCase = saveBookGroupUseCase
        self.deleteBookGroupUseCase = deleteBookGroupUseCase
        self.importLocalBookUseCase = importLocalBookUseCase
        self.layoutDefaults = layoutDefaults
        self.realtimeSyncService = realtimeSyncService
        let savedSort = UserDefaults.standard.string(forKey: BookshelfSortOrder.storageKey)
            .flatMap(BookshelfSortOrder.init(rawValue:)) ?? .recent
        let savedLayout = layoutDefaults?.string(forKey: BookshelfLayoutMode.storageKey)
            .flatMap(BookshelfLayoutMode.init(rawValue:)) ?? .grid
        super.init(initialState: BookshelfState(layoutMode: savedLayout, sortOrder: savedSort))

        send(.onAppear)
    }

    override public func send(_ intent: BookshelfIntent) {
        switch intent {
        case .onAppear:
            loadData()

        case .refresh:
            refreshUpdates()

        case .updateSearchText, .selectGroup, .toggleLayoutMode, .selectSortOrder,
             .updateBookMetadata, .importLocalBook, .importLocalBooks:
            handlePreferenceAndImportIntent(intent)

        case .didSelectBook, .openBookDetail, .removeBook:
            handleBookActionIntent(intent)

        case .toggleBatchMode, .toggleSelectBook, .selectAll, .deselectAll,
             .batchRemoveSelected, .batchMoveSelectedToGroup:
            handleBatchIntent(intent)

        case .addCustomGroup, .deleteCustomGroup, .moveBookToGroup:
            handleGroupIntent(intent)
        }
    }

    private func handlePreferenceAndImportIntent(_ intent: BookshelfIntent) {
        switch intent {
        case let .updateSearchText(query):
            updateState { $0.searchText = query }

        case let .selectGroup(group):
            updateState { $0.selectedGroup = group }
            emitEffect(.hapticFeedback)

        case .toggleLayoutMode:
            let nextLayout: BookshelfLayoutMode = (state.layoutMode == .grid ? .list : .grid)
            layoutDefaults?.set(nextLayout.rawValue, forKey: BookshelfLayoutMode.storageKey)
            updateState { $0.layoutMode = nextLayout }
            emitEffect(.hapticFeedback)

        case let .selectSortOrder(order):
            UserDefaults.standard.set(order.rawValue, forKey: BookshelfSortOrder.storageKey)
            updateState { $0.sortOrder = order }
            emitEffect(.hapticFeedback)

        case let .updateBookMetadata(bookUrl, name, author):
            performUpdateBookMetadata(bookUrl: bookUrl, name: name, author: author)

        case let .importLocalBook(url):
            handleImportLocalBooks(urls: [url])

        case let .importLocalBooks(urls):
            handleImportLocalBooks(urls: urls)

        default:
            break
        }
    }

    private func handleBookActionIntent(_ intent: BookshelfIntent) {
        switch intent {
        case let .didSelectBook(book):
            if state.isBatchMode {
                send(.toggleSelectBook(bookUrl: book.bookUrl))
            } else {
                emitEffect(.navigateToReader(book))
            }

        case let .openBookDetail(book):
            emitEffect(.navigateToDetail(book))

        case let .removeBook(bookUrl):
            deleteBook(bookUrl: bookUrl)

        default:
            break
        }
    }

    private func handleBatchIntent(_ intent: BookshelfIntent) {
        switch intent {
        case .toggleBatchMode:
            updateState {
                $0.isBatchMode.toggle()
                $0.selectedBookUrls.removeAll()
            }
            emitEffect(.hapticFeedback)

        case let .toggleSelectBook(bookUrl):
            updateState {
                if $0.selectedBookUrls.contains(bookUrl) {
                    $0.selectedBookUrls.remove(bookUrl)
                } else {
                    $0.selectedBookUrls.insert(bookUrl)
                }
            }
            emitEffect(.hapticFeedback)

        case .selectAll:
            updateState { $0.selectedBookUrls = Set($0.filteredBooks.map(\.bookUrl)) }
            emitEffect(.hapticFeedback)

        case .deselectAll:
            updateState { $0.selectedBookUrls.removeAll() }
            emitEffect(.hapticFeedback)

        case .batchRemoveSelected:
            performBatchRemove()

        case let .batchMoveSelectedToGroup(groupName):
            performBatchMove(groupName: groupName)

        default:
            break
        }
    }

    private func handleGroupIntent(_ intent: BookshelfIntent) {
        switch intent {
        case let .addCustomGroup(name):
            performAddGroup(name: name)

        case let .deleteCustomGroup(id):
            performDeleteGroup(id: id)

        case let .moveBookToGroup(bookUrl, groupName):
            performMoveSingleBook(bookUrl: bookUrl, groupName: groupName)

        default:
            break
        }
    }

    func loadData() {
        loadTask?.cancel()
        updateState { $0.isLoading = true }

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let books = try await self.getBookshelfUseCase.execute()
                let customGroups = (try? await self.getBookGroupsUseCase?.execute()) ?? []
                guard !Task.isCancelled else { return }
                let defaultGroups = ["全部", "在读", "未读", "完结"]
                let allGroupNames = defaultGroups + customGroups.map(\.name)

                self.updateState { state in
                    state.isLoading = false
                    state.books = books
                    state.customGroups = customGroups
                    state.groups = allGroupNames
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.updateState { $0.isLoading = false }
                self.emitEffect(.showToast("获取书架失败: \(error.localizedDescription)"))
            }
        }
    }

    private func refreshUpdates() {
        refreshTask?.cancel()
        updateState {
            $0.isLoading = true
            $0.isRefreshing = true
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = await self.realtimeSyncService?.pullLatestProgressIfNeeded(force: true)
                _ = await self.realtimeSyncService?.pullLatestRulesIfNeeded(force: true)
                let currentBooks = try await self.getBookshelfUseCase.execute()
                let customGroups = (try? await self.getBookGroupsUseCase?.execute()) ?? []
                guard !Task.isCancelled else { return }
                let defaultGroups = ["全部", "在读", "未读", "完结"]
                self.updateState { state in
                    state.isLoading = false
                    state.isRefreshing = false
                    state.books = currentBooks
                    state.customGroups = customGroups
                    state.groups = defaultGroups + customGroups.map(\.name)
                }
                self.emitEffect(.showToast("书架已刷新"))
                self.emitEffect(.hapticFeedback)
            } catch {
                guard !Task.isCancelled else { return }
                self.updateState {
                    $0.isLoading = false
                    $0.isRefreshing = false
                }
            }
        }
    }

    private func deleteBook(bookUrl: String) {
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.removeBookFromShelfUseCase.execute(bookUrl: bookUrl)
                let books = try await self.getBookshelfUseCase.execute()
                self.updateState { $0.books = books }
                self.emitEffect(.showToast("已从书架移出"))
                self.emitEffect(.hapticFeedback)
            } catch {
                self.emitEffect(.showToast("移除失败: \(error.localizedDescription)"))
            }
        }
    }
}
