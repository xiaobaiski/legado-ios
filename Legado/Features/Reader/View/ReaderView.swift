import SwiftUI
import UIKit

/// 沉浸式阅读器主视图 (纯声明式渲染 View = f(State))
public struct ReaderView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var environment: AppEnvironment
    @StateObject var viewModel: ReaderViewModel
    @State var toastMessage: String?
    @State var hapticTrigger = false
    @State var isSearchContentPresented = false
    @State var isTocReversed = false
    @State var tocSearchText = ""
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

    var readerColorScheme: ColorScheme {
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

                if viewModel.state.isAutoPaging && !viewModel.state.isHUDVisible {
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
                viewModel.stopAutoPageTimer()
                volumeHandler.stop()
                restoreSystemDisplaySettings()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    if readingSessionStart == nil {
                        readingSessionStart = Date()
                    }
                    viewModel.handleAppDidBecomeActive()
                } else {
                    flushReadingSession()
                    viewModel.flushRealtimeProgressSync()
                }
            }
            .onReceive(environment.rulesRefreshSubject) { _ in
                viewModel.reloadExternalReaderConfig()
            }
            .onChange(of: viewModel.state.currentPageIndex) { _, _ in
                scheduleScreenKeepOnTimer()
            }
            .onChange(of: viewModel.state.config) { _, _ in
                applySystemDisplaySettings()
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
                    onRulesChanged: { viewModel.notifyRulesChanged() },
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
                    viewModel.notifyRulesChanged()
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
        .sheet(isPresented: tocPresentationBinding) {
            tocSheetView
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
            toastOverlayView
        }
    }
}
