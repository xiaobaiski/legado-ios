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
    @State var isFontChooserPresented = false
    @State var pendingFontChooserAfterSettings = false
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

    var hasModalSheetPresented: Bool {
        viewModel.state.isMoreSettingsVisible
            || viewModel.state.isTocSheetVisible
            || isFontChooserPresented
            || isTextActionPresented
            || isSearchContentPresented
    }

    public var body: some View {
        GeometryReader { safeGeo in
            ZStack {
                // 全屏沉浸式排版画布：与 ReaderPageView 严格共享同一全屏尺寸，彻底消除底部多余空白
                GeometryReader { fullGeo in
                    ZStack {
                        viewModel.state.config.effectiveBackgroundColor
                        contentLayer(width: fullGeo.size.width, safeArea: safeGeo.safeAreaInsets)

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
                handleScenePhaseChange(phase)
            }
            .onReceive(environment.rulesRefreshSubject) { _ in
                viewModel.reloadExternalReaderConfig()
            }
            .onChange(of: viewModel.state.currentPageIndex) { _, _ in
                scheduleScreenKeepOnTimer()
            }
            .onChange(of: viewModel.state.config.followSystemBrightness) { _, _ in
                applySystemDisplaySettings()
            }
            .onChange(of: viewModel.state.config.customBrightness) { _, _ in
                applySystemDisplaySettings()
            }
            .onChange(of: viewModel.state.config.keepScreenOnDuration) { _, _ in
                scheduleScreenKeepOnTimer()
            }
            .onChange(of: viewModel.state.config.volumeKeyPageTurn) { _, _ in
                updateVolumeButtonBinding()
            }
            .onChange(of: hasModalSheetPresented) { _, _ in
                updateVolumeButtonBinding()
            }
        }
        .preferredColorScheme(readerColorScheme)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(!viewModel.state.isHUDVisible && !viewModel.state.config.showStatusBar)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .upArrow, .rightArrow, .downArrow, .space, .escape]) { press in
            guard !hasModalSheetPresented else { return .ignored }
            return handleHardwareKeyPress(press)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .sheet(
            isPresented: Binding(
                get: { viewModel.state.isMoreSettingsVisible },
                set: { if !$0 { viewModel.send(.closeMoreSettings) } }),
            onDismiss: {
                if pendingFontChooserAfterSettings {
                    pendingFontChooserAfterSettings = false
                    viewModel.send(.refreshImportedFonts)
                    isFontChooserPresented = true
                }
            }) {
                moreSettingsSheetView
        }
        .sheet(isPresented: $isFontChooserPresented) {
            fontChooserSheetView
                .onAppear {
                    viewModel.send(.refreshImportedFonts)
                }
        }
        .sheet(isPresented: $isTextActionPresented) {
            textActionSheetView
        }
        .sheet(isPresented: $isSearchContentPresented) {
            searchContentSheetView
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
