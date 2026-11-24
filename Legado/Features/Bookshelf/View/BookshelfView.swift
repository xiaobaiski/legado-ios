import SwiftUI
import UniformTypeIdentifiers

/// 书架主视图：遵循 MVI 单向数据流与 iOS 18+ 原生液态玻璃美学
public struct BookshelfView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: BookshelfViewModel
    @State private var activeToast: String?
    @State private var selectedBookForDetail: Book?
    @State private var readerDestination: ReaderDestination?
    @State private var hapticTrigger = false
    @State private var isShowingAddGroupAlert = false
    @State private var isShowingFileImporter = false
    @State private var newGroupName = ""
    @State private var editingBook: Book?
    @State private var editBookName = ""
    @State private var editBookAuthor = ""
    @State private var bookPendingRemoval: Book?
    @State private var isShowingBatchRemoveAlert = false

    public init(viewModel: @autoclosure @escaping () -> BookshelfViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel.state.searchText },
            set: { viewModel.send(.updateSearchText($0)) })
    }

    public var body: some View {
        let displayedBooks = viewModel.state.filteredBooks

        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    groupSelectorSection

                    if !viewModel.state.isBatchMode,
                       viewModel.state.searchText.isEmpty,
                       viewModel.state.selectedGroup == "全部",
                       let recentBook = viewModel.state.recentReadingBook {
                        BookshelfResumeBannerView(book: recentBook) {
                            viewModel.send(.didSelectBook(recentBook))
                        }
                    }

                    if displayedBooks.isEmpty && !viewModel.state.isLoading {
                        emptyStateView
                    } else if viewModel.state.layoutMode == .grid {
                        booksGridContent(books: displayedBooks)
                    } else {
                        booksListContent(books: displayedBooks)
                    }
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? 1180 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
                .padding(.top, 12)
                .padding(.bottom, viewModel.state.isBatchMode ? 90 : 20)
            }
            .navigationTitle("书架")
            .toolbarTitleDisplayMode(.large)
            .searchable(text: searchTextBinding, prompt: "搜索书架中的书籍或作者")
            .toolbar {
                toolbarItems
            }
            .refreshable {
                await viewModel.refreshAsync()
            }
            .onAppear {
                viewModel.send(.onAppear)
                consumeExternalImports()
            }
            .onReceive(environment.externalFileImportSubject) { _ in
                consumeExternalImports()
            }
            .onReceive(environment.bookshelfRefreshSubject) { _ in
                viewModel.send(.onAppear)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
            .navigationDestination(item: $selectedBookForDetail) { book in
                BookDetailView(viewModel: environment.makeBookDetailViewModel(book: book))
            }
            .fullScreenCover(
                item: $readerDestination,
                onDismiss: { viewModel.send(.onAppear) },
                content: { dest in
                    ReaderView(viewModel: environment.makeReaderViewModel(
                        book: dest.book,
                        initialChapterIndex: dest.chapterIndex))
                })
            .onReceive(viewModel.effectPublisher) { handleEffect($0) }
            .overlay {
                if viewModel.state.isImporting {
                    loadingOverlay
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 12) {
                    toastOverlay
                    if viewModel.state.isBatchMode {
                        batchBarOverlay(displayedCount: displayedBooks.count)
                    }
                }
            }
            .alert("新建分组", isPresented: $isShowingAddGroupAlert) {
                TextField("分组名称", text: $newGroupName)
                Button("取消", role: .cancel) { newGroupName = "" }
                Button("确定") {
                    let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        viewModel.send(.addCustomGroup(name: trimmed))
                    }
                    newGroupName = ""
                }
            }
            .alert(
                "编辑书籍信息",
                isPresented: Binding(
                    get: { editingBook != nil },
                    set: { if !$0 { editingBook = nil } })) {
                TextField("书名", text: $editBookName)
                TextField("作者", text: $editBookAuthor)
                Button("取消", role: .cancel) { editingBook = nil }
                Button("保存") {
                    if let target = editingBook {
                        viewModel.send(.updateBookMetadata(
                            bookUrl: target.bookUrl,
                            name: editBookName,
                            author: editBookAuthor))
                    }
                    editingBook = nil
                }
            }
            .alert(
                "移出书架",
                isPresented: Binding(
                    get: { bookPendingRemoval != nil },
                    set: { if !$0 { bookPendingRemoval = nil } })) {
                Button("取消", role: .cancel) { bookPendingRemoval = nil }
                Button("确认移出", role: .destructive) {
                    if let target = bookPendingRemoval {
                        viewModel.send(.removeBook(bookUrl: target.bookUrl))
                    }
                    bookPendingRemoval = nil
                }
            } message: {
                if let target = bookPendingRemoval {
                    Text("确定将《\(target.name)》从书架移出吗？本地书籍的章节正文与封面缓存也会同步清理。")
                }
            }
            .alert("批量移出书架", isPresented: $isShowingBatchRemoveAlert) {
                Button("取消", role: .cancel) {}
                Button("确认移出", role: .destructive) {
                    viewModel.send(.batchRemoveSelected)
                }
            } message: {
                Text("确定将选中的 \(viewModel.state.selectedBookUrls.count) 本书从书架移出吗？本地书籍正文与封面将同步删除。")
            }
            .sheet(isPresented: $isShowingFileImporter) {
                DocumentPickerView(
                    allowedContentTypes: Self.localBookContentTypes,
                    allowsMultipleSelection: true,
                    onPick: { urls in
                        isShowingFileImporter = false
                        if !urls.isEmpty {
                            viewModel.send(.importLocalBooks(urls))
                        }
                    },
                    onCancel: {
                        isShowingFileImporter = false
                    })
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 12) {
                Button {
                    viewModel.send(.toggleLayoutMode)
                } label: {
                    Image(systemName: viewModel.state.layoutMode == .grid ? "list.bullet" : "square.grid.2x2")
                        .symbolRenderingMode(.hierarchical)
                }

                Menu {
                    ForEach(BookshelfSortOrder.allCases) { order in
                        Button {
                            viewModel.send(.selectSortOrder(order))
                        } label: {
                            if viewModel.state.sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("排序方式")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                if !viewModel.state.books.isEmpty || viewModel.state.isBatchMode {
                    Button {
                        viewModel.send(.toggleBatchMode)
                    } label: {
                        Text(viewModel.state.isBatchMode ? "完成" : "管理")
                            .font(.subheadline.weight(.medium))
                    }
                }

                Button {
                    isShowingFileImporter = true
                } label: {
                    Image(systemName: "plus.circle")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("导入本地书籍")
            }
        }
    }

    // MARK: - Group Selector

    private var groupSelectorSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.state.groups, id: \.self) { group in
                    groupPillView(for: group)
                }

                Button {
                    isShowingAddGroupAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func groupPillView(for group: String) -> some View {
        let isSelected = viewModel.state.selectedGroup == group
        let isCustom = viewModel.state.customGroups.contains(where: { $0.name == group })
        let customGroup = viewModel.state.customGroups.first(where: { $0.name == group })

        return Button {
            viewModel.send(.selectGroup(group))
        } label: {
            Text(group)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? .regularMaterial : .ultraThinMaterial)
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(isSelected ? 0.3 : 0.16), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isCustom, let customGroup {
                Button(role: .destructive) {
                    viewModel.send(.deleteCustomGroup(id: customGroup.id))
                } label: {
                    Label("删除分组「\(group)」", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Books Content, Overlays & File Import

private extension BookshelfView {
    func booksGridContent(books: [Book]) -> some View {
        let isWide = horizontalSizeClass == .regular
        let gridSpacing: CGFloat = isWide ? 20 : 14
        let columns = [GridItem(.adaptive(minimum: isWide ? 144 : 102, maximum: 186), spacing: gridSpacing)]

        return LazyVGrid(
            columns: columns,
            spacing: isWide ? 22 : 16) {
                ForEach(books) { book in
                    BookshelfBookCardView(
                        book: book,
                        isBatchMode: viewModel.state.isBatchMode,
                        isSelected: viewModel.state.selectedBookUrls.contains(book.bookUrl),
                        allGroups: viewModel.state.groups,
                        onTap: { viewModel.send(.didSelectBook(book)) },
                        onShowDetail: { viewModel.send(.openBookDetail(book)) },
                        onEditMetadata: {
                            editingBook = book
                            editBookName = book.name
                            editBookAuthor = book.author
                        },
                        onRemove: { bookPendingRemoval = book },
                        onMoveGroup: { viewModel.send(.moveBookToGroup(bookUrl: book.bookUrl, groupName: $0)) })
                }
            }
    }

    func booksListContent(books: [Book]) -> some View {
        let isWide = horizontalSizeClass == .regular
        let columns = isWide
            ? [GridItem(.adaptive(minimum: 340, maximum: 560), spacing: 16)]
            : [GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: isWide ? 14 : 12) {
            ForEach(books) { book in
                BookshelfBookRowView(
                    book: book,
                    isBatchMode: viewModel.state.isBatchMode,
                    isSelected: viewModel.state.selectedBookUrls.contains(book.bookUrl),
                    allGroups: viewModel.state.groups,
                    onTap: { viewModel.send(.didSelectBook(book)) },
                    onShowDetail: { viewModel.send(.openBookDetail(book)) },
                    onEditMetadata: {
                        editingBook = book
                        editBookName = book.name
                        editBookAuthor = book.author
                    },
                    onRemove: { bookPendingRemoval = book },
                    onMoveGroup: { viewModel.send(.moveBookToGroup(bookUrl: book.bookUrl, groupName: $0)) })
            }
        }
    }

    var emptyStateView: some View {
        ContentUnavailableView {
            Label(
                viewModel.state.searchText.isEmpty ? "书架空空如也" : "无搜索结果",
                systemImage: "books.vertical")
        } description: {
            Text(viewModel.state.searchText.isEmpty ? "点击右上角「+」导入本地 TXT 或 EPUB 电子书" : "未找到匹配的书籍")
        } actions: {
            if viewModel.state.searchText.isEmpty {
                Button {
                    isShowingFileImporter = true
                } label: {
                    Label("导入本地书籍 (TXT / EPUB)", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.top, 40)
    }

    /// 允许选择 TXT / EPUB 与通用数据文件，避免 iOS 文件选择器中部分下载的电子书变灰不可选
    static var localBookContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .data]
        if let epubType = UTType(filenameExtension: "epub") {
            types.insert(epubType, at: 0)
        }
        return types
    }

    func consumeExternalImports() {
        let urls = environment.consumePendingImportURLs()
        if !urls.isEmpty {
            viewModel.send(.importLocalBooks(urls))
        }
    }

    var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("正在处理本地书籍...")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    func batchBarOverlay(displayedCount: Int) -> some View {
        BookshelfBatchBar(
            selectedCount: viewModel.state.selectedBookUrls.count,
            isAllSelected: displayedCount > 0 && viewModel.state.selectedBookUrls.count == displayedCount,
            customGroups: viewModel.state.customGroups,
            onToggleSelectAll: {
                if viewModel.state.selectedBookUrls.count == displayedCount {
                    viewModel.send(.deselectAll)
                } else {
                    viewModel.send(.selectAll)
                }
            },
            onBatchMove: { groupName in
                viewModel.send(.batchMoveSelectedToGroup(groupName: groupName))
            },
            onBatchRemove: {
                isShowingBatchRemoveAlert = true
            },
            onFinish: {
                viewModel.send(.toggleBatchMode)
            })
            .frame(maxWidth: horizontalSizeClass == .regular ? 540 : .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    var toastOverlay: some View {
        if let toast = activeToast {
            Text(toast)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Color.black.opacity(0.55)
                    }
                }
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.bottom, viewModel.state.isBatchMode ? 4 : 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if activeToast == toast {
                        activeToast = nil
                    }
                }
        }
    }

    func handleEffect(_ effect: BookshelfEffect) {
        switch effect {
        case let .navigateToReader(book):
            readerDestination = ReaderDestination(book: book)

        case let .navigateToDetail(book):
            selectedBookForDetail = book

        case let .showToast(message):
            activeToast = message

        case .hapticFeedback:
            if ReaderConfigStore.isHapticEnabled {
                hapticTrigger.toggle()
            }
        }
    }
}
