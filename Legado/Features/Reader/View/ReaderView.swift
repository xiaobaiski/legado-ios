import SwiftUI
import UIKit

/// 沉浸式阅读器主视图 (纯声明式渲染 View = f(State))
public struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject var viewModel: ReaderViewModel
    @ObservedObject var ttsPlayer: TTSPlayer = .shared
    @State private var toastMessage: String?
    @State private var hapticTrigger = false
    @State private var isTTSSpeaking = false
    @State private var isChangeSourcePresented = false
    @State private var isSearchContentPresented = false
    @State private var isCachePresented = false
    @State private var isTocReversed = false
    @State private var tocSearchText = ""
    @State private var cacheInfo: BookCacheInfo?
    @State private var cacheDownloadProgress: BatchDownloadProgress?
    @State private var cacheDownloadTask: Task<Void, Never>?
    @State private var originalBrightness: CGFloat?
    @State private var isFontPickerPresented = false
    @State private var volumeHandler = VolumeButtonHandler()

    public init(viewModel: ReaderViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景配色
                viewModel.state.config.theme.backgroundColor
                    .ignoresSafeArea()

                // 多模式正文排版呈现 (覆盖 / 滑动 / 连续上下滚动)
                contentLayer(width: geometry.size.width)

                // 液态玻璃 HUD 控制面板
                if viewModel.state.isHUDVisible {
                    ReaderHUDView(
                        bookTitle: viewModel.state.book.name,
                        currentChapterTitle: viewModel.state.currentChapter?.title ?? "",
                        currentChapterIndex: viewModel.state.currentChapterIndex,
                        totalChapters: viewModel.state.chapters.count,
                        config: viewModel.state.config,
                        importedFonts: viewModel.state.importedFonts,
                        safeAreaTop: geometry.safeAreaInsets.top,
                        isConfigOpen: viewModel.state.isConfigSheetVisible,
                        isAutoPaging: viewModel.state.isAutoPaging,
                        isLocalFile: viewModel.state.book.isLocalFile,
                        onBack: { dismiss() },
                        onPreviousChapter: {
                            viewModel.send(.loadChapter(viewModel.state.currentChapterIndex - 1))
                        },
                        onNextChapter: {
                            viewModel.send(.loadChapter(viewModel.state.currentChapterIndex + 1))
                        },
                        onSliderChange: { newIndex in
                            viewModel.send(.loadChapter(Int(newIndex)))
                        },
                        onOpenToc: { viewModel.send(.openToc) },
                        onToggleConfig: {
                            viewModel.send(viewModel.state.isConfigSheetVisible ? .closeConfig : .openConfig)
                        },
                        onUpdateConfig: { newConfig in
                            viewModel.send(.updateConfig(newConfig))
                        },
                        onSelectCustomFont: { font in
                            viewModel.send(.selectCustomFont(font))
                        },
                        onOpenFontImporter: {
                            isFontPickerPresented = true
                        },
                        onResetConfig: {
                            viewModel.send(.resetConfig)
                        },
                        onOpenMoreSettings: {
                            viewModel.send(.openMoreSettings)
                        },
                        onToggleAutoPage: {
                            viewModel.send(.toggleAutoPage)
                        },
                        onStartTTS: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                viewModel.send(.toggleHUD)
                                isTTSSpeaking = true
                            }
                            setupTTSCallbacks()
                            let text = viewModel.state.currentChapterText
                            ttsPlayer.startReading(
                                content: text,
                                bookTitle: viewModel.state.book.name,
                                chapterTitle: viewModel.state.currentChapter?.title ?? "",
                                author: viewModel.state.book.author)
                        },
                        onOpenChangeSource: {
                            if viewModel.state.book.isLocalFile {
                                toastMessage = "本地书籍无需换源"
                                return
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                viewModel.send(.hideHUD)
                                isChangeSourcePresented = true
                            }
                        },
                        onOpenSearch: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                viewModel.send(.hideHUD)
                                isSearchContentPresented = true
                            }
                        },
                        isBookmarked: viewModel.state.isCurrentPageBookmarked,
                        onToggleBookmark: {
                            viewModel.send(.toggleBookmark)
                        },
                        onOpenCache: {
                            cacheInfo = environment.manageBookCacheUseCase.getBookCacheInfo(
                                bookUrl: viewModel.state.book.bookUrl,
                                totalChapters: viewModel.state.chapters.count)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                viewModel.send(.hideHUD)
                                isCachePresented = true
                            }
                        })
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                // 朗读悬浮控制胶囊条
                if isTTSSpeaking {
                    VStack {
                        Spacer()
                        TTSFloatingBar {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                isTTSSpeaking = false
                            }
                        }
                        .frame(maxWidth: 520)
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // 自动翻页悬浮控制胶囊条
                if viewModel.state.isAutoPaging && !viewModel.state.isHUDVisible && !isTTSSpeaking {
                    autoPageFloatingBar
                }
            }
            .onAppear {
                viewModel.send(.updateScreenBounds(geometry.frame(in: .local)))
                applySystemDisplaySettings()
                updateVolumeButtonBinding()
            }
            .onDisappear {
                cacheDownloadTask?.cancel()
                cacheDownloadTask = nil
                viewModel.stopAutoPageTimer()
                volumeHandler.stop()
                restoreSystemDisplaySettings()
                TTSPlayer.shared.stop()
            }
            .onChange(of: geometry.size) { _, newSize in
                viewModel.send(.updateScreenBounds(CGRect(origin: .zero, size: newSize)))
            }
            .onChange(of: viewModel.state.config) { _, _ in
                applySystemDisplaySettings()
                updateVolumeButtonBinding()
            }
            .onChange(of: isTTSSpeaking) { _, _ in
                updateVolumeButtonBinding()
            }
        }
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(!viewModel.state.isHUDVisible && !viewModel.state.config.showStatusBar)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .sheet(isPresented: Binding(
            get: { viewModel.state.isMoreSettingsVisible },
            set: {
                if !$0 {
                    viewModel.send(.closeMoreSettings)
                }
            })) {
                ReaderSettingsSheet(
                    config: viewModel.state.config,
                    importedFonts: viewModel.state.importedFonts,
                    isAutoPaging: viewModel.state.isAutoPaging,
                    onUpdateConfig: { viewModel.send(.updateConfig($0)) },
                    onSelectCustomFont: { viewModel.send(.selectCustomFont($0)) },
                    onDeleteCustomFont: { viewModel.send(.deleteImportedFont($0)) },
                    onOpenFontImporter: {
                        viewModel.send(.closeMoreSettings)
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            isFontPickerPresented = true
                        }
                    },
                    onToggleAutoPage: { viewModel.send(.toggleAutoPage) },
                    onSetAutoPageInterval: { viewModel.send(.setAutoPageInterval($0)) },
                    onResetConfig: { viewModel.send(.resetConfig) })
        }
        .sheet(isPresented: $isFontPickerPresented) {
            DocumentPickerView(
                allowedContentTypes: LocalFontManager.allowedContentTypes,
                allowsMultipleSelection: true,
                onPick: { urls in
                    isFontPickerPresented = false
                    if !urls.isEmpty {
                        viewModel.send(.importFonts(urls))
                    }
                },
                onCancel: {
                    isFontPickerPresented = false
                })
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isChangeSourcePresented) {
            ChangeSourceSheet(
                viewModel: environment.makeChangeSourceViewModel(
                    book: viewModel.state.book,
                    currentChapterTitle: viewModel.state.currentChapter?.title,
                    currentChapterIndex: viewModel.state.currentChapterIndex),
                onSwitched: { updatedBook, newToc, matchedIndex in
                    viewModel.send(.switchSource(
                        updatedBook: updatedBook,
                        newToc: newToc,
                        matchedChapterIndex: matchedIndex))
                })
        }
        .sheet(isPresented: $isSearchContentPresented) {
            BookSearchContentSheet(
                viewModel: environment.makeBookSearchContentViewModel(
                    book: viewModel.state.book,
                    chapters: viewModel.state.chapters),
                onSelectMatch: { chapterIndex, matchOffset in
                    isSearchContentPresented = false
                    viewModel.send(.jumpToChapterAndOffset(
                        chapterIndex: chapterIndex,
                        matchOffset: matchOffset))
                })
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.isTocSheetVisible },
            set: {
                if !$0 {
                    viewModel.send(.closeToc)
                }
            })) {
                BookTocSheet(
                    chapters: viewModel.state.chapters,
                    durChapterIndex: viewModel.state.currentChapterIndex,
                    isReverse: isTocReversed,
                    searchText: tocSearchText,
                    bookmarks: viewModel.state.bookmarks,
                    onToggleReverse: { isTocReversed.toggle() },
                    onSearchChange: { tocSearchText = $0 },
                    onSelectChapter: { chapter in
                        viewModel.send(.closeToc)
                        viewModel.send(.loadChapter(chapter.index))
                    },
                    onSelectBookmark: { bookmark in
                        viewModel.send(.closeToc)
                        viewModel.send(.jumpToChapterAndOffset(
                            chapterIndex: bookmark.chapterIndex,
                            matchOffset: bookmark.chapterPos))
                    },
                    onDeleteBookmark: { bookmark in
                        viewModel.send(.deleteBookmark(id: bookmark.id))
                    })
        }
        .sheet(isPresented: $isCachePresented) {
            BookCacheSheet(
                book: viewModel.state.book,
                chapters: viewModel.state.chapters,
                cacheInfo: cacheInfo ?? environment.manageBookCacheUseCase.getBookCacheInfo(
                    bookUrl: viewModel.state.book.bookUrl,
                    totalChapters: viewModel.state.chapters.count),
                downloadProgress: cacheDownloadProgress,
                onStartDownload: { option in
                    startReaderCacheDownload(option: option)
                },
                onCancelDownload: {
                    cacheDownloadTask?.cancel()
                    cacheDownloadTask = nil
                    cacheDownloadProgress?.status = .idle
                },
                onClearCache: {
                    guard !viewModel.state.book.isLocalFile else { return }
                    try? environment.manageBookCacheUseCase.clearBookCache(bookUrl: viewModel.state.book.bookUrl)
                    cacheInfo = environment.manageBookCacheUseCase.getBookCacheInfo(
                        bookUrl: viewModel.state.book.bookUrl,
                        totalChapters: viewModel.state.chapters.count)
                },
                onDismiss: { isCachePresented = false })
        }
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
                if viewModel.state.config.isHapticEnabled {
                    hapticTrigger.toggle()
                }

            case .navigateBack:
                dismiss()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if toastMessage == toast {
                            toastMessage = nil
                        }
                    }
            }
        }
        .onChange(of: ttsPlayer.state) { _, newState in
            if newState == .idle && isTTSSpeaking {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isTTSSpeaking = false
                }
            }
        }
    }

    private func setupTTSCallbacks() {
        ttsPlayer.onSentenceChanged = { _, sentence in
            if let targetPageIndex = viewModel.state.pages.firstIndex(where: { $0.contentText.contains(sentence) }),
               targetPageIndex != viewModel.state.currentPageIndex {
                viewModel.send(.jumpToPage(targetPageIndex))
            }
        }
        ttsPlayer.onRequestNextChapterAsync = { [weak viewModel] in
            guard let viewModel else { return nil }
            return await viewModel.fetchNextChapterForTTS()
        }
    }
}

private extension ReaderView {
    var autoPageFloatingBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("自动翻页 \(Int(viewModel.state.config.autoPageIntervalSeconds))秒")
                    .font(.caption.weight(.medium).monospacedDigit())

                Button {
                    viewModel.send(.setAutoPageInterval(viewModel.state.config.autoPageIntervalSeconds - 1))
                } label: {
                    Image(systemName: "minus.circle")
                }

                Button {
                    viewModel.send(.setAutoPageInterval(viewModel.state.config.autoPageIntervalSeconds + 1))
                } label: {
                    Image(systemName: "plus.circle")
                }

                Button("停止") {
                    viewModel.send(.toggleAutoPage)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .padding(.bottom, 22)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    func updateVolumeButtonBinding() {
        let shouldEnable = viewModel.state.config.volumeKeyPageTurn && !isTTSSpeaking
        if shouldEnable {
            volumeHandler.start(
                onVolumeUp: { viewModel.send(.prevPage) },
                onVolumeDown: { viewModel.send(.nextPage) })
        } else {
            volumeHandler.stop()
        }
    }

    func applySystemDisplaySettings() {
        let config = viewModel.state.config
        UIApplication.shared.isIdleTimerDisabled = config.keepScreenOn

        guard let screen = activeWindowScreen else { return }
        if originalBrightness == nil {
            originalBrightness = screen.brightness
        }
        if config.followSystemBrightness {
            if let originalBrightness {
                screen.brightness = originalBrightness
            }
        } else {
            screen.brightness = CGFloat(config.customBrightness)
        }
    }

    func restoreSystemDisplaySettings() {
        UIApplication.shared.isIdleTimerDisabled = false
        if let originalBrightness, let screen = activeWindowScreen {
            screen.brightness = originalBrightness
        }
    }

    var activeWindowScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
    }

    func startReaderCacheDownload(option: BatchDownloadOption) {
        guard !viewModel.state.book.isLocalFile else { return }
        cacheDownloadTask?.cancel()
        cacheDownloadProgress = BatchDownloadProgress(
            bookUrl: viewModel.state.book.bookUrl,
            bookName: viewModel.state.book.name,
            totalChaptersToDownload: 0,
            completedChaptersCount: 0,
            status: .downloading)

        let book = viewModel.state.book
        let chapters = viewModel.state.chapters
        cacheDownloadTask = Task {
            do {
                try await environment.batchDownloadChaptersUseCase.execute(
                    book: book,
                    chapters: chapters,
                    option: option,
                    concurrency: 3) { progress in
                        Task { @MainActor in
                            cacheDownloadProgress = progress
                        }
                    }
                await MainActor.run {
                    cacheInfo = environment.manageBookCacheUseCase.getBookCacheInfo(
                        bookUrl: book.bookUrl,
                        totalChapters: chapters.count)
                    toastMessage = "离线缓存完成！"
                }
            } catch is CancellationError {
                await MainActor.run {
                    cacheDownloadProgress?.status = .paused
                }
            } catch {
                await MainActor.run {
                    cacheDownloadProgress?.status = .failed(error.localizedDescription)
                    toastMessage = "缓存失败: \(error.localizedDescription)"
                }
            }
        }
    }
}
