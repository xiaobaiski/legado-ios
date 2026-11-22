import SwiftUI

/// WebDAV 云备份同步独立配置页（支持按需连接与选择性同步）
public struct WebDAVSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            credentialsSection
            syncContentSection
            actionsAndStatusSection
        }
        .navigationTitle("WebDAV 云备份同步")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var credentialsSection: some View {
        Section {
            TextField("服务器地址 (如 https://dav.jianguoyun.com/dav/)", text: Binding(
                get: { viewModel.state.webDAVConfig.serverUrl },
                set: { viewModel.send(.updateWebDAVServer($0)) }))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("账号 / 邮箱（匿名局域网可留空）", text: Binding(
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
        } header: {
            Text("服务器与账号配置")
        } footer: {
            Text("支持坚果云、Alist / OpenList、群晖、Nextcloud 等服务；仅在点击下方按钮时发起网络请求。")
        }
    }

    private var syncContentSection: some View {
        let options = viewModel.state.webDAVConfig.syncOptions
        return Section {
            Toggle(isOn: syncOptionBinding(\.syncProgress)) {
                Label("阅读进度、书架与书签", systemImage: "bookmark.circle")
            }
            Toggle(isOn: syncOptionBinding(\.syncRules)) {
                Label("净化规则、目录规则与排版", systemImage: "wand.and.stars")
            }
            Toggle(isOn: syncOptionBinding(\.syncBookFiles)) {
                Label("本地书籍文件（正文与封面）", systemImage: "books.vertical")
            }
        } header: {
            Text("同步内容选择")
        } footer: {
            if !options.hasAnySelection {
                Text("请至少勾选一项需要同步的内容。")
                    .foregroundStyle(.red)
            } else {
                Text("单独备份某一项时会自动保留云端其它已备份内容；还原未勾选本地书籍文件时，将自动跳过本机尚无正文的本地书以避免产生打不开的空书。")
            }
        }
    }

    private var actionsAndStatusSection: some View {
        Section {
            Button {
                viewModel.send(.testWebDAVConnection)
            } label: {
                HStack {
                    if viewModel.state.isTestingConnection {
                        ProgressView().scaleEffect(0.8)
                        Text("正在验证连接...")
                    } else {
                        Image(systemName: "network.badge.shield.half.filled")
                        Text("测试服务器连接")
                    }
                }
                .font(.subheadline.weight(.medium))
            }
            .disabled(viewModel.state.isTestingConnection)

            actionButtonsRow
            statusMessagesView
        } header: {
            Text("连接验证与同步操作")
        } footer: {
            Text("连接局域网 WebDAV 设备时，系统仅在发起请求时按需询问「本地网络」权限。")
        }
    }

    private var actionButtonsRow: some View {
        let noSelection = !viewModel.state.webDAVConfig.syncOptions.hasAnySelection
        return HStack(spacing: 12) {
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
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(viewModel.state.isBackingUp || viewModel.state.isRestoring || noSelection)

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
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(viewModel.state.isRestoring || viewModel.state.isBackingUp || noSelection)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusMessagesView: some View {
        if let success = viewModel.state.successMessage, !success.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(success)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
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
            let fileInfo = summary.bookFileCount > 0 ? "、\(summary.bookFileCount) 本文件" : ""
            Text("最近同步：\(summary.bookCount) 本书、\(summary.ruleCount) 条规则\(fileInfo) (\(sizeKB) KB)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func syncOptionBinding(_ keyPath: WritableKeyPath<WebDAVSyncOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel.state.webDAVConfig.syncOptions[keyPath: keyPath] },
            set: { newValue in
                var updated = viewModel.state.webDAVConfig.syncOptions
                updated[keyPath: keyPath] = newValue
                viewModel.send(.updateWebDAVSyncOptions(updated))
            })
    }
}
