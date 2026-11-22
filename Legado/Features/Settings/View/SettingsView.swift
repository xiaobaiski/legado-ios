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
                webDAVSection
                ttsSection
                storageSection
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

// MARK: - WebDAV 与 TTS 设置分区

private extension SettingsView {
    var webDAVSection: some View {
        Section {
            TextField("服务器地址 (如 https://dav.jianguoyun.com/dav/)", text: Binding(
                get: { viewModel.state.webDAVConfig.serverUrl },
                set: { viewModel.send(.updateWebDAVServer($0)) }))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("账号 / 邮箱", text: Binding(
                get: { viewModel.state.webDAVConfig.username },
                set: { viewModel.send(.updateWebDAVUsername($0)) }))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("密码 / 应用独立密码", text: Binding(
                get: { viewModel.state.webDAVConfig.password },
                set: { viewModel.send(.updateWebDAVPassword($0)) }))

            TextField("远程存放目录 (如 /Legado/)", text: Binding(
                get: { viewModel.state.webDAVConfig.remoteDirectory },
                set: { viewModel.send(.updateWebDAVDirectory($0)) }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Toggle(
                "允许自签名证书 (局域网 NAS HTTPS)",
                isOn: Binding(
                    get: { viewModel.state.webDAVConfig.allowInsecureCertificate },
                    set: { viewModel.send(.updateWebDAVAllowInsecureCert($0)) }))

            Button {
                viewModel.send(.testWebDAVConnection)
            } label: {
                HStack {
                    if viewModel.state.isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("正在验证连接...")
                    } else {
                        Image(systemName: "network.badge.shield.half.filled")
                        Text("测试服务器连接")
                    }
                }
                .font(.subheadline.weight(.medium))
            }
            .disabled(viewModel.state.isTestingConnection)

            webDAVActionRow
            webDAVStatusViews
        } header: {
            Label("WebDAV 云备份同步", systemImage: "icloud")
        } footer: {
            Text("支持坚果云、Alist / OpenList、群晖、Nextcloud 等 WebDAV 服务。首次连接局域网 NAS 请允许「本地网络」权限。")
        }
    }

    var webDAVActionRow: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.send(.backupToWebDAV)
            } label: {
                HStack {
                    if viewModel.state.isBackingUp {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise.icloud.fill")
                    }
                    Text("立即备份")
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(viewModel.state.isBackingUp)

            Button {
                viewModel.send(.restoreFromWebDAV)
            } label: {
                HStack {
                    if viewModel.state.isRestoring {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "icloud.and.arrow.down.fill")
                    }
                    Text("从云端还原")
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(viewModel.state.isRestoring)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var webDAVStatusViews: some View {
        if let success = viewModel.state.successMessage, !success.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(success)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }

        if let error = viewModel.state.errorMessage, !error.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let summary = viewModel.state.lastBackupSummary {
            let sizeKB = max(summary.dataSizeBytes / 1024, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("最近备份：\(summary.bookCount) 本书、\(summary.ruleCount) 条规则 (\(sizeKB) KB)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
