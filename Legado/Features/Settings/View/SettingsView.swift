import SwiftUI

/// 系统设置主视图 (遵循 MVI 架构与原生 iOS 18 液态玻璃质感)
public struct SettingsView: View {
    @AppStorage(AppAppearanceMode.storageKey) var appearanceModeRaw = AppAppearanceMode.system.rawValue
    @StateObject var viewModel: SettingsViewModel
    @State private var toastMessage: String?
    @State private var hapticTrigger = false
    @State var isShowingClearAlert = false
    @State var isShowingFontPicker = false
    @State var isShowingFontChooser = false

    public init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            Form {
                readingPreferencesSection
                localFontsSection
                cloudAndStorageSection
                purifySection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                viewModel.send(.refreshCacheSize)
                viewModel.send(.refreshReaderConfig)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
            .onReceive(viewModel.effectPublisher) { effect in
                switch effect {
                case let .showToast(msg):
                    toastMessage = msg

                case .hapticFeedback:
                    if viewModel.state.readerConfig.isHapticEnabled {
                        hapticTrigger.toggle()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .padding(.bottom, 24)
                        .task(id: toastMessage) {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            if self.toastMessage == toastMessage {
                                self.toastMessage = nil
                            }
                        }
                }
            }
            .alert("清理临时章节缓存", isPresented: $isShowingClearAlert) {
                Button("取消", role: .cancel) {}
                Button("确定清理", role: .destructive) {
                    viewModel.send(.clearAllCache)
                }
            } message: {
                Text("仅清理临时章节缓存（共 \(viewModel.state.formattedCacheSize)），不会删除已导入的本地书籍。")
            }
            .sheet(isPresented: $isShowingFontChooser) {
                FontPickerSheet(
                    selectedPostScriptName: viewModel.state.readerConfig.customFontName,
                    importedFonts: viewModel.state.importedFonts,
                    onSelectSystemDefault: {
                        var updated = viewModel.state.readerConfig
                        updated.customFontName = nil
                        updated.customFontDisplayName = nil
                        updated.fontFamily = .system
                        viewModel.send(.updateReaderConfig(updated))
                    },
                    onSelectFont: { psName, displayName in
                        var updated = viewModel.state.readerConfig
                        updated.customFontName = psName
                        updated.customFontDisplayName = displayName
                        viewModel.send(.updateReaderConfig(updated))
                    },
                    onDeleteImportedFont: { font in
                        viewModel.send(.deleteLocalFont(font))
                    },
                    onOpenFontImporter: {
                        isShowingFontChooser = false
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            isShowingFontPicker = true
                        }
                    })
            }
            .sheet(isPresented: $isShowingFontPicker) {
                DocumentPickerView(
                    allowedContentTypes: LocalFontManager.allowedContentTypes,
                    allowsMultipleSelection: true,
                    onPick: { urls in
                        isShowingFontPicker = false
                        if !urls.isEmpty {
                            viewModel.send(.importLocalFonts(urls))
                        }
                    },
                    onCancel: {
                        isShowingFontPicker = false
                    })
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - 云同步与存储分区

private extension SettingsView {
    var cloudAndStorageSection: some View {
        Section {
            NavigationLink {
                WebDAVSettingsView(viewModel: viewModel)
            } label: {
                HStack {
                    Label("WebDAV 云备份同步", systemImage: "icloud")
                    Spacer()
                    Text(WebDAVConfigStore.isEffectivelyConfigured(viewModel.state.webDAVConfig) ? "已配置" : "未配置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label("临时章节缓存", systemImage: "internaldrive")
                Spacer()
                Text(viewModel.state.formattedCacheSize)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                isShowingClearAlert = true
            } label: {
                Label("清理临时章节缓存正文", systemImage: "trash")
            }
        } header: {
            Label("云同步与存储", systemImage: "icloud.and.arrow.up")
        } footer: {
            Text("仅在配置有效 WebDAV 服务器后支持手动或可选实时同步；本地导入的 TXT / EPUB 电子书独立保存，清理缓存不会删除本地书籍。")
        }
    }
}
