import Foundation

/// 发现模块视图模型 (MVI 状态中枢)
@MainActor
public final class ExploreViewModel: BaseMVIViewModel<ExploreState, ExploreIntent, ExploreEffect> {
    private let getExploreCategoriesUseCase: GetExploreCategoriesUseCase
    private let exploreBooksUseCase: ExploreBooksUseCase

    public init(
        getExploreCategoriesUseCase: GetExploreCategoriesUseCase,
        exploreBooksUseCase: ExploreBooksUseCase) {
        self.getExploreCategoriesUseCase = getExploreCategoriesUseCase
        self.exploreBooksUseCase = exploreBooksUseCase
        super.init(initialState: ExploreState())

        send(.onAppear)
    }

    override public func send(_ intent: ExploreIntent) {
        switch intent {
        case .onAppear:
            loadCategories()

        case let .selectCategory(category):
            updateState { state in
                state.selectedCategory = category
                state.currentPage = 1
                state.books = []
            }
            emitEffect(.hapticFeedback)
            loadBooks(for: category, page: 1, isAppending: false)

        case .refresh:
            if let category = state.selectedCategory {
                loadBooks(for: category, page: 1, isAppending: false)
            } else {
                loadCategories()
            }

        case .loadNextPage:
            guard let category = state.selectedCategory, !state.isLoadingBooks else { return }
            let nextPage = state.currentPage + 1
            loadBooks(for: category, page: nextPage, isAppending: true)

        case let .openBook(book):
            emitEffect(.navigateToDetail(book))
        }
    }

    private func loadCategories() {
        updateState { $0.isLoadingCategories = true }

        Task {
            do {
                let categories = try await getExploreCategoriesUseCase.execute()
                let previousSelection = state.selectedCategory
                let nextSelection = previousSelection.flatMap { prev in
                    categories.first(where: { $0.id == prev.id })
                } ?? categories.first

                self.updateState { state in
                    state.isLoadingCategories = false
                    state.categories = categories
                    state.selectedCategory = nextSelection
                    if nextSelection == nil {
                        state.books = []
                    }
                }

                if let target = nextSelection,
                   target.id != previousSelection?.id || state.books.isEmpty {
                    self.loadBooks(for: target, page: 1, isAppending: false)
                }
            } catch {
                self.updateState { state in
                    state.isLoadingCategories = false
                    state.errorMessage = error.localizedDescription
                }
                self.emitEffect(.showToast("加载发现分类失败: \(error.localizedDescription)"))
            }
        }
    }

    private func loadBooks(for category: ExploreCategory, page: Int, isAppending: Bool) {
        updateState { $0.isLoadingBooks = true }

        Task {
            do {
                let fetched = try await exploreBooksUseCase.execute(category: category, page: page)
                self.updateState { state in
                    state.isLoadingBooks = false
                    state.currentPage = page
                    if isAppending {
                        state.books.append(contentsOf: fetched)
                    } else {
                        state.books = fetched
                    }
                }
            } catch {
                self.updateState { state in
                    state.isLoadingBooks = false
                    state.errorMessage = error.localizedDescription
                }
                self.emitEffect(.showToast("加载发现书籍失败: \(error.localizedDescription)"))
            }
        }
    }
}
