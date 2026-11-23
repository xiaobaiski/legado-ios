import SwiftUI

/// 书籍详情页面视图 (纯声明式渲染 View = f(State))
public struct BookDetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject var viewModel: BookDetailViewModel
    @State private var toastMessage: String?
    @State private var hapticTrigger = false
    @State private var readerDestination: ReaderDestination?

    public init(viewModel: BookDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 顶部卡片：封面、书名、作者与关键标签
                headerCard

                // 操作按钮栏：阅读、加入/移出书架
                actionButtons

                // 书籍详细简介
                introCard

                // 目录与最新章节预览卡片
                tocPreviewCard
            }
            .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .background {
            // 背景渐变与毛玻璃环境光
            ZStack {
                if viewModel.state.book.coverUrl != nil {
                    BookCoverImage(coverUrl: viewModel.state.book.coverUrl) {
                        Color.clear
                    }
                    .blur(radius: 60)
                    .opacity(0.18)
                }
            }
            .ignoresSafeArea()
        }
        .navigationTitle(viewModel.state.book.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.send(.loadDetail)
                } label: {
                    if viewModel.state.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.isTocPresented },
            set: {
                if !$0 {
                    viewModel.send(.closeToc)
                }
            })) {
                BookTocSheet(
                    chapters: viewModel.state.chapters,
                    durChapterIndex: viewModel.state.book.durChapterIndex,
                    isReverse: viewModel.state.isReverseToc,
                    searchText: viewModel.state.tocSearchText,
                    onToggleReverse: { viewModel.send(.toggleTocReverse) },
                    onSearchChange: { viewModel.send(.updateTocSearch($0)) },
                    onSelectChapter: { viewModel.send(.selectChapter($0)) })
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .onReceive(viewModel.effectPublisher) { effect in
            switch effect {
            case let .showToast(msg):
                toastMessage = msg
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if toastMessage == msg {
                        toastMessage = nil
                    }
                }

            case .hapticFeedback:
                if ReaderConfigStore.isHapticEnabled {
                    hapticTrigger.toggle()
                }

            case let .navigateToReader(chapterIndex):
                readerDestination = ReaderDestination(book: viewModel.state.book, chapterIndex: chapterIndex)
            }
        }
        .fullScreenCover(
            item: $readerDestination,
            onDismiss: { viewModel.send(.loadDetail) },
            content: { dest in
                ReaderView(viewModel: environment.makeReaderViewModel(
                    book: dest.book,
                    initialChapterIndex: dest.chapterIndex))
            })
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
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
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toastMessage)
            }
        }
    }

    // MARK: - 头部大卡片

    private var headerCard: some View {
        let isWide = horizontalSizeClass == .regular
        let coverW: CGFloat = isWide ? 124 : 100
        let coverH: CGFloat = isWide ? 172 : 138

        return HStack(alignment: .top, spacing: isWide ? 22 : 16) {
            // 封面图
            BookCoverImage(coverUrl: viewModel.state.book.coverUrl) {
                placeholderCover
            }
            .frame(width: coverW, height: coverH)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.state.book.name)
                    .font(.title3.bold())
                    .lineLimit(2)

                Text(viewModel.state.book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if let kind = viewModel.state.book.kind, !kind.isEmpty {
                        Text(kind)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if let wordCount = viewModel.state.book.wordCount, !wordCount.isEmpty {
                        Text(wordCount)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                    let originLabel = viewModel.state.book.originName.isEmpty
                        ? "本地导入"
                        : viewModel.state.book.originName
                    Text("来源: \(originLabel)")
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5))
    }

    private var placeholderCover: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 操作按钮栏

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // 开始阅读按钮
            Button {
                readerDestination = ReaderDestination(book: viewModel.state.book)
            } label: {
                HStack {
                    Image(systemName: "book.fill")
                    Text(viewModel.state.book.durChapterIndex > 0 ? "继续阅读" : "开始阅读")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent(tint: .accentColor, cornerRadius: 14))

            // 加入/移出书架按钮
            Button {
                viewModel.send(.toggleBookshelf)
            } label: {
                HStack {
                    Image(
                        systemName: viewModel.state.isInBookshelf ? "bookmark.slash.fill" : "bookmark.fill")
                    Text(viewModel.state.isInBookshelf ? "移出书架" : "加入书架")
                }
                .font(.headline)
                .foregroundStyle(viewModel.state.isInBookshelf ? .red : .primary)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glass(cornerRadius: 14))
        }
    }
}
