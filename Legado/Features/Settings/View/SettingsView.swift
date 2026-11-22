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
                ttsSection
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
            .alert("清空所有离线缓存", isPresented: $isShowingClearAlert) {
                Button("取消", role: .cancel) {}
                Button("确定清空", role: .destructive) {
                    viewModel.send(.clearAllCache)
                }
            } message: {
                Text("仅清理在线章节缓存正文，可释放 \(viewModel.state.formattedCacheSize) 空间，不会删除已导入的本地书籍。")
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

// MARK: - 云同步、存储与 TTS 分区

private extension SettingsView {
    var cloudAndStorageSection: some View {
        Section {
            NavigationLink {
                WebDAVSettingsView(viewModel: viewModel)
            } label: {
                HStack {
                    Label("WebDAV 云备份同步", systemImage: "icloud")
                    Spacer()
                    Text(viewModel.state.webDAVConfig.isValid ? "已配置" : "未配置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label("离线章节缓存", systemImage: "internaldrive")
                Spacer()
                Text(viewModel.state.formattedCacheSize)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                isShowingClearAlert = true
            } label: {
                Label("清空所有离线章节正文", systemImage: "trash")
            }
        } header: {
            Label("云同步与存储", systemImage: "icloud.and.arrow.up")
        } footer: {
            Text("仅在主动备份、还原或测试连接时访问网络；本地导入的 TXT / EPUB 电子书独立保存，清理缓存不会删除本地书籍。")
        }
    }

    var ttsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("朗读语速")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2fx", viewModel.state.speechRate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(viewModel.state.speechRate) },
                        set: { viewModel.send(.updateSpeechRate(Float($0))) }),
                    in: 0.5 ... 2.0,
                    step: 0.05)
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("语音音调")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2f", viewModel.state.speechPitch))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(viewModel.state.speechPitch) },
                        set: { viewModel.send(.updateSpeechPitch(Float($0))) }),
                    in: 0.5 ... 1.5,
                    step: 0.05)
            }
            .padding(.vertical, 2)
        } header: {
            Label("语音朗读偏好 (TTS)", systemImage: "headphones")
        }
    }
}
