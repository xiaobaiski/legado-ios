import SwiftUI

// MARK: - SettingsView 辅助分区扩展

extension SettingsView {
    var readingPreferencesSection: some View {
        Section {
            Picker("全局外观模式", selection: appearanceBinding) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("阅读器夜间模式", isOn: Binding(
                get: { viewModel.state.readerConfig.theme.isDark },
                set: { wantDark in
                    if wantDark != viewModel.state.readerConfig.theme.isDark {
                        var updated = viewModel.state.readerConfig
                        updated.toggleNightMode()
                        viewModel.send(.updateReaderConfig(updated))
                    }
                }))

            Toggle("触感震动反馈", isOn: readerBinding(\.isHapticEnabled))
            Toggle("阅读时屏幕常亮", isOn: readerBinding(\.keepScreenOn))
            Toggle("点击屏幕翻页", isOn: readerBinding(\.tapToTurnPage))

            NavigationLink {
                TapZoneConfigView(tapZoneConfig: readerBinding(\.tapZoneConfig))
            } label: {
                Label("点按区域自定义 (九宫格)", systemImage: "square.grid.3x3")
            }

            Toggle("音量键翻页", isOn: readerBinding(\.volumeKeyPageTurn))
            Toggle("iPad 大屏双页分栏", isOn: readerBinding(\.enableIPadDualPage))

            Picker("繁简转换", selection: readerBinding(\.chineseConversion)) {
                ForEach(ChineseConversionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("显示页眉（章节名与时间）", isOn: readerBinding(\.showHeader))
            Toggle("显示页脚（页码、总进度与电量）", isOn: readerBinding(\.showFooter))

            Button(role: .destructive) {
                viewModel.send(.resetReaderConfig)
            } label: {
                Label("恢复默认阅读排版", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Label("阅读与外观偏好", systemImage: "book.pages")
        } footer: {
            Text("字号、字体、行距、段距、字距、边距与主题配色可在阅读器「排版」面板中实时调节并自动保存。")
        }
    }

    private var appearanceBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue })
    }

    private func readerBinding<T>(_ keyPath: WritableKeyPath<ReaderConfig, T>) -> Binding<T> {
        Binding(
            get: { viewModel.state.readerConfig[keyPath: keyPath] },
            set: { newValue in
                var updated = viewModel.state.readerConfig
                updated[keyPath: keyPath] = newValue
                viewModel.send(.updateReaderConfig(updated))
            })
    }

    var localFontsSection: some View {
        Section {
            Button {
                isShowingFontChooser = true
            } label: {
                HStack {
                    Label("选择阅读字体（本机 / 本地字体）", systemImage: "textformat")
                    Spacer()
                    Text(viewModel.state.readerConfig.customFontDisplayName ?? "系统默认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Button {
                isShowingFontPicker = true
            } label: {
                Label("导入本地字体文件 (TTF / OTF / TTC)", systemImage: "doc.badge.plus")
            }

            if viewModel.state.importedFonts.isEmpty {
                Text("尚未导入自定义字体")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.state.importedFonts) { font in
                    let isSelected = viewModel.state.readerConfig.customFontName == font.postScriptName
                    HStack {
                        Button {
                            viewModel.send(.selectLocalFont(font))
                        } label: {
                            HStack {
                                Text(font.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            viewModel.send(.deleteLocalFont(font))
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                }
            }
        } header: {
            Label("自定义阅读字体", systemImage: "character.book.closed")
        } footer: {
            Text("也支持在 iOS「文件」App 中直接将字体文件放入「我的 iPhone / iPad -> Legado -> Fonts」目录。")
        }
    }

    var storageSection: some View {
        Section {
            HStack {
                Text("离线章节缓存")
                Spacer()
                Text(viewModel.state.formattedCacheSize)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                isShowingClearAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("清空所有离线章节正文")
                }
            }
        } header: {
            Label("存储与离线缓存", systemImage: "internaldrive")
        }
    }

    var purifySection: some View {
        Section {
            Toggle("启用替换净化规则", isOn: readerBinding(\.enableReplaceRule))
            Toggle("去除正文重复章节标题", isOn: readerBinding(\.removeSameTitle))
            Toggle("智能重新分段（修复断行）", isOn: readerBinding(\.reSegment))

            NavigationLink {
                ReplaceRuleManageView()
            } label: {
                Label("管理替换净化规则 (兼容 Legado JSON)", systemImage: "wand.and.stars")
            }

            NavigationLink {
                TxtTocRuleManageView()
            } label: {
                Label("TXT 目录分章规则 (兼容 txtTocRule.json)", systemImage: "list.bullet.indent")
            }
        } header: {
            Label("章节优化与净化排版规则", systemImage: "wand.and.stars")
        } footer: {
            Text("完全兼容 Legado Android 替换净化与 TXT 目录正则规则，支持从文件或剪贴板导入导出。")
        }
    }

    var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0 (iOS 18+ 原生)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("视觉风格")
                Spacer()
                Text("Apple Liquid Glass / Vibrancy")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("架构设计")
                Spacer()
                Text("MVI + Clean Architecture")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("开源致敬")
                Spacer()
                Text("Legado (阅读 3.0)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("关于应用", systemImage: "info.circle")
        }
    }
}
