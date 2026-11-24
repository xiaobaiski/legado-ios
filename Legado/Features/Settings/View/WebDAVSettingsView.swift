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
            realtimeSyncSection
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
            Text("支持坚果云、Alist / OpenList、群晖、Nextcloud 等服务；未完成配置前不会发起任何后台同步请求。")
        }
    }

    private var realtimeSyncSection: some View {
        let options = viewModel.state.webDAVConfig.syncOptions
        let syncStatus = viewModel.state.realtimeSyncStatus
        return Section {
            Toggle(isOn: syncOptionBinding(\.autoSyncEnabled)) {
                Label("启用实时同步", systemImage: "bolt.horizontal.icloud")
            }

            if options.autoSyncEnabled {
                Toggle(isOn: syncOptionBinding(\.realtimeSyncProgress)) {
                    Label("实时同步阅读进度", systemImage: "arrow.triangle.2.circlepath")
                }

                Toggle(isOn: syncOptionBinding(\.realtimeSyncRules)) {
                    Label("实时同步规则与排版", systemImage: "slider.horizontal.3")
                }

                realtimeSyncStatusRow(syncStatus)
            }
        } header: {
            Text("实时自动同步")
        } footer: {
            Text("开启且完成 WebDAV 配置后，翻页或退出阅读将防抖上传进度，开启规则同步时修改排版或净化/目录规则也会自动双向同步。")
        }
    }

    @ViewBuilder
    private func realtimeSyncStatusRow(_ syncStatus: WebDAVRealtimeSyncStatus) -> some View {
        if syncStatus.isSyncing {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.75)
                Text("正在同步云端状态...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let err = syncStatus.lastErrorMessage, !err.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("最近实时同步异常：\(err)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let summary = syncStatus.lastSyncSummary, let syncAt = syncStatus.lastSyncAt {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.icloud")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("\(summary)（\(syncAt.formatted(date: .omitted, time: .shortened))）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
        let isBusy = viewModel.state.isTestingConnection
            || viewModel.state.isBackingUp
            || viewModel.state.isRestoring
        return Section {
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
            .disabled(isBusy)

            actionButtonsRow
            statusMessagesView
        } header: {
            Text("连接验证与同步操作")
        } footer: {
            Text("连接局域网 WebDAV 设备时，系统仅在发起请求时按需询问「本地网络」权限。")
        }
    }

    private var actionButtonsRow: some View {
        let isBusy = viewModel.state.isTestingConnection
            || viewModel.state.isBackingUp
            || viewModel.state.isRestoring
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
            .disabled(isBusy || noSelection)

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
            .disabled(isBusy || noSelection)
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
