import SwiftUI

// MARK: - SettingsView 辅助分区扩展

extension SettingsView {
    var readingPreferencesSection: some View {
        Section {
            NavigationLink {
                ReadingStatsView()
            } label: {
                HStack {
                    Label("阅读统计与时长记录", systemImage: "chart.bar.xaxis")
                    Spacer()
                    Text("今日 \(ReadRecordStore.formatDuration(viewModel.state.todayReadSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("全局外观模式", selection: appearanceBinding) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("阅读器夜间模式", isOn: Binding(
                get: { viewModel.state.readerConfig.isEffectiveDark },
                set: { wantDark in
                    if wantDark != viewModel.state.readerConfig.isEffectiveDark {
                        var updated = viewModel.state.readerConfig
                        updated.toggleNightMode()
                        viewModel.send(.updateReaderConfig(updated))
                    }
                }))

            Toggle("触感震动反馈", isOn: readerBinding(\.isHapticEnabled))

            Picker(
                "屏幕常亮时长",
                selection: Binding(
                    get: { viewModel.state.readerConfig.keepScreenOnDuration },
                    set: { duration in
                        var updated = viewModel.state.readerConfig
                        updated.keepScreenOnDuration = duration
                        updated.keepScreenOn = duration != .system
                        viewModel.send(.updateReaderConfig(updated))
                    })) {
                        ForEach(KeepScreenOnDuration.allCases) { duration in
                            Text(duration.title).tag(duration)
                        }
                    }

            Picker("底部进度条行为", selection: readerBinding(\.progressBarBehavior)) {
                ForEach(ProgressBarBehavior.allCases) { behavior in
                    Text(behavior.rawValue).tag(behavior)
                }
            }

            Toggle("点击屏幕翻页", isOn: readerBinding(\.tapToTurnPage))

            NavigationLink {
                TapZoneConfigView(tapZoneConfig: readerBinding(\.tapZoneConfig))
            } label: {
                Label("点按区域自定义 (九宫格)", systemImage: "square.grid.3x3")
            }

            NavigationLink {
                ChapterTitleConfigView(config: fullReaderConfigBinding)
            } label: {
                Label("正文章节标题样式", systemImage: "textformat.size.larger")
            }

            NavigationLink {
                HeaderFooterConfigView(config: fullReaderConfigBinding)
            } label: {
                Label("页眉与页脚自定义 (6 槽位)", systemImage: "rectangle.topthird.inset.filled")
            }

            NavigationLink {
                CustomThemeConfigView(config: fullReaderConfigBinding)
            } label: {
                Label("自定义配色与护眼滤镜", systemImage: "paintpalette")
            }

            Toggle("音量键翻页", isOn: readerBinding(\.volumeKeyPageTurn))
            Toggle("iPad 大屏双页分栏", isOn: readerBinding(\.enableIPadDualPage))

            Picker("自动翻页方式", selection: readerBinding(\.autoPageMode)) {
                ForEach(AutoPageMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Picker("繁简转换", selection: readerBinding(\.chineseConversion)) {
                ForEach(ChineseConversionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Button(role: .destructive) {
                viewModel.send(.resetReaderConfig)
            } label: {
                Label("恢复默认阅读排版", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Label("阅读与外观偏好", systemImage: "book.pages")
        } footer: {
            Text("字号、字体、行距、段距、字距、四边边距与主题配色可在阅读器底部「排版」面板中实时调节并自动保存。")
        }
    }

    private var fullReaderConfigBinding: Binding<ReaderConfig> {
        Binding(
            get: { viewModel.state.readerConfig },
            set: { viewModel.send(.updateReaderConfig($0)) })
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

    var purifySection: some View {
        Section {
            Toggle("启用替换净化规则", isOn: readerBinding(\.enableReplaceRule))
            Toggle("去除正文重复章节标题", isOn: readerBinding(\.removeSameTitle))
            Toggle("智能重新分段（修复断行）", isOn: readerBinding(\.reSegment))

            NavigationLink {
                ReplaceRuleManageView(onRulesChanged: { viewModel.send(.notifyRulesChanged) })
            } label: {
                Label("管理替换净化规则 (兼容 Legado JSON)", systemImage: "wand.and.stars")
            }

            NavigationLink {
                TxtTocRuleManageView(onRulesChanged: { viewModel.send(.notifyRulesChanged) })
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
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.1"
                Text("\(version) (iOS 18+ 纯净阅读版)")
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
