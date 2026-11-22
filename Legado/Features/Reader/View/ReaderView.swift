import SwiftUI
import UIKit

/// 沉浸式阅读器主视图 (纯声明式渲染 View = f(State))
public struct ReaderView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var environment: AppEnvironment
    @StateObject var viewModel: ReaderViewModel
    @ObservedObject var ttsPlayer: TTSPlayer = .shared
    @State var toastMessage: String?
    @State var hapticTrigger = false
    @State var isTTSSpeaking = false
    @State var isChangeSourcePresented = false
    @State var isSearchContentPresented = false
    @State var isCachePresented = false
    @State var isTocReversed = false
    @State var tocSearchText = ""
    @State var cacheInfo: BookCacheInfo?
    @State var cacheDownloadProgress: BatchDownloadProgress?
    @State var cacheDownloadTask: Task<Void, Never>?
    @State var originalBrightness: CGFloat?
    @State var isFontPickerPresented = false
    @State var isFontChooserPresented = false
    @State var isTextActionPresented = false
    @State var readingSessionStart: Date?
    @State var screenKeepOnTask: Task<Void, Never>?
    @State var volumeHandler = VolumeButtonHandler()

    public init(viewModel: ReaderViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var readerColorScheme: ColorScheme {
        viewModel.state.config.isEffectiveDark ? .dark : .light
    }

    public var body: some View {
        GeometryReader { safeGeo in
            ZStack {
                // 全屏沉浸式排版画布：与 ReaderPageView 严格共享同一全屏尺寸，彻底消除底部多余空白
                GeometryReader { fullGeo in
                    ZStack {
                        viewModel.state.config.effectiveBackgroundColor
                        contentLayer(width: fullGeo.size.width)

                        if viewModel.state.config.eyeProtectionWarmth > 0 {
                            Color(red: 1.0, green: 0.62, blue: 0.12)
                                .opacity(viewModel.state.config.eyeProtectionWarmth * 0.45)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: fullGeo.size.width, height: fullGeo.size.height)
                    .onAppear {
                        viewModel.send(.updateScreenBounds(CGRect(origin: .zero, size: fullGeo.size)))
                    }
                    .onChange(of: fullGeo.size) { _, newSize in
                        viewModel.send(.updateScreenBounds(CGRect(origin: .zero, size: newSize)))
                    }
                }
                .ignoresSafeArea()

                if viewModel.state.isHUDVisible {
                    hudOverlay(safeAreaTop: safeGeo.safeAreaInsets.top)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

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

                if viewModel.state.isAutoPaging && !viewModel.state.isHUDVisible && !isTTSSpeaking {
                    autoPageFloatingBar
                }
            }
            .onAppear {
                readingSessionStart = Date()
                applySystemDisplaySettings()
                updateVolumeButtonBinding()
            }
            .onDisappear {
                flushReadingSession()
                viewModel.flushRealtimeProgressSync()
                cacheDownloadTask?.cancel()
                cacheDownloadTask = nil
                viewModel.stopAutoPageTimer()
                volumeHandler.stop()
                restoreSystemDisplaySettings()
                TTSPlayer.shared.onSentenceChanged = nil
                TTSPlayer.shared.onChapterFinished = nil
                TTSPlayer.shared.onRequestNextChapter = nil
                TTSPlayer.shared.onRequestNextChapterAsync = nil
                TTSPlayer.shared.stop()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    if readingSessionStart == nil {
                        readingSessionStart = Date()
                    }
                } else {
                    flushReadingSession()
                    viewModel.flushRealtimeProgressSync()
                }
            }
            .onChange(of: viewModel.state.currentPageIndex) { _, _ in
                scheduleScreenKeepOnTimer()
            }
            .onChange(of: viewModel.state.config) { _, _ in
                applySystemDisplaySettings()
                updateVolumeButtonBinding()
            }
            .onChange(of: isTTSSpeaking) { _, _ in
                updateVolumeButtonBinding()
            }
        }
        .preferredColorScheme(readerColorScheme)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(!viewModel.state.isHUDVisible && !viewModel.state.config.showStatusBar)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .upArrow, .rightArrow, .downArrow, .space, .escape]) { press in
            handleHardwareKeyPress(press)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .sheet(isPresented: Binding(
            get: { viewModel.state.isMoreSettingsVisible },
            set: { if !$0 { viewModel.send(.closeMoreSettings) } })) {
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
                            isFontChooserPresented = true
                        }
                    },
                    onToggleAutoPage: { viewModel.send(.toggleAutoPage) },
                    onSetAutoPageInterval: { viewModel.send(.setAutoPageInterval($0)) },
                    onRulesChanged: { viewModel.send(.repaginate) },
                    onResetConfig: { viewModel.send(.resetConfig) })
        }
        .sheet(isPresented: $isFontChooserPresented) {
            FontPickerSheet(
                selectedPostScriptName: viewModel.state.config.customFontName,
                importedFonts: viewModel.state.importedFonts,
                onSelectSystemDefault: {
                    var updated = viewModel.state.config
                    updated.customFontName = nil
                    updated.customFontDisplayName = nil
                    updated.fontFamily = .system
                    viewModel.send(.updateConfig(updated))
                },
                onSelectFont: { psName, displayName in
                    var updated = viewModel.state.config
                    updated.customFontName = psName
                    updated.customFontDisplayName = displayName
                    viewModel.send(.updateConfig(updated))
                },
                onDeleteImportedFont: { viewModel.send(.deleteImportedFont($0)) },
                onOpenFontImporter: {
                    isFontChooserPresented = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        isFontPickerPresented = true
                    }
                })
                .preferredColorScheme(readerColorScheme)
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
                onCancel: { isFontPickerPresented = false })
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isTextActionPresented) {
            PageTextActionSheet(
                pageText: viewModel.state.currentPage?.contentText ?? viewModel.state.currentChapterText,
                chapterTitle: viewModel.state.currentChapter?.title ?? "",
                bookName: viewModel.state.book.name,
                onAddBookmarkWithNote: { excerpt, note in
                    viewModel.send(.addBookmark(
                        chapterIndex: viewModel.state.currentChapterIndex,
                        chapterPos: viewModel.state.currentPage?.textRange.location ?? 0,
                        chapterTitle: viewModel.state.currentChapter?.title ?? "",
                        bookText: excerpt,
                        note: note))
                },
                onQuickPurifyRuleSaved: {
                    viewModel.send(.repaginate)
                })
                .preferredColorScheme(readerColorScheme)
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
                .preferredColorScheme(readerColorScheme)
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
                .preferredColorScheme(readerColorScheme)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.isTocSheetVisible },
            set: {
                if !$0 {
                    tocSearchText = ""
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
                    onDeleteBookmark: { viewModel.send(.deleteBookmark(id: $0.id)) })
                    .preferredColorScheme(readerColorScheme)
        }
        .sheet(isPresented: $isCachePresented) {
            BookCacheSheet(
                book: viewModel.state.book,
                chapters: viewModel.state.chapters,
                cacheInfo: cacheInfo ?? environment.manageBookCacheUseCase.getBookCacheInfo(
                    bookUrl: viewModel.state.book.bookUrl,
                    totalChapters: viewModel.state.chapters.count),
                downloadProgress: cacheDownloadProgress,
                onStartDownload: { startReaderCacheDownload(option: $0) },
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
                .preferredColorScheme(readerColorScheme)
        }
        .onReceive(viewModel.effectPublisher) { effect in
            switch effect {
            case let .showToast(msg):
                toastMessage = msg

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
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
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

    private func hudOverlay(safeAreaTop: CGFloat) -> some View {
        ReaderHUDView(
            bookTitle: viewModel.state.book.name,
            currentChapterTitle: viewModel.state.currentChapter?.title ?? "",
            currentChapterIndex: viewModel.state.currentChapterIndex,
            totalChapters: viewModel.state.chapters.count,
            currentPageIndex: viewModel.state.currentPageIndex,
            totalPages: viewModel.state.pages.count,
            chapters: viewModel.state.chapters,
            config: viewModel.state.config,
            importedFonts: viewModel.state.importedFonts,
            safeAreaTop: safeAreaTop,
            isConfigOpen: viewModel.state.isConfigSheetVisible,
            isAutoPaging: viewModel.state.isAutoPaging,
            isLocalFile: viewModel.state.book.isLocalFile,
            onBack: { dismiss() },
            onPreviousChapter: { viewModel.send(.loadChapter(viewModel.state.currentChapterIndex - 1)) },
            onNextChapter: { viewModel.send(.loadChapter(viewModel.state.currentChapterIndex + 1)) },
            onSliderChange: { viewModel.send(.loadChapter(Int($0))) },
            onPageSliderChange: { viewModel.send(.jumpToPage($0)) },
            onOpenToc: {
                tocSearchText = ""
                viewModel.send(.openToc)
            },
            onToggleConfig: {
                viewModel.send(viewModel.state.isConfigSheetVisible ? .closeConfig : .openConfig)
            },
            onUpdateConfig: { viewModel.send(.updateConfig($0)) },
            onSelectCustomFont: { viewModel.send(.selectCustomFont($0)) },
            onOpenFontImporter: { isFontChooserPresented = true },
            onToggleNightMode: {
                var updated = viewModel.state.config
                updated.toggleNightMode()
                viewModel.send(.updateConfig(updated))
            },
            onOpenTextAction: {
                viewModel.send(.hideHUD)
                isTextActionPresented = true
            },
            onResetConfig: { viewModel.send(.resetConfig) },
            onOpenMoreSettings: { viewModel.send(.openMoreSettings) },
            onToggleAutoPage: { viewModel.send(.toggleAutoPage) },
            onStartTTS: { startTTSReading() },
            onOpenChangeSource: { openChangeSourceSheet() },
            onOpenSearch: { openSearchContentSheet() },
            isBookmarked: viewModel.state.isCurrentPageBookmarked,
            onToggleBookmark: { viewModel.send(.toggleBookmark) },
            onOpenCache: { openCacheSheet() })
    }
}
