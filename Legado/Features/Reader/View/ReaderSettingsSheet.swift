import SwiftUI

/// 阅读器更多设置原生抽屉（震动开关、屏幕常亮、点击/左手翻页、自动翻页、繁简转换、页眉页脚与上下边距）
public struct ReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let config: ReaderConfig
    let importedFonts: [ImportedFont]
    let isAutoPaging: Bool
    let onUpdateConfig: (ReaderConfig) -> Void
    let onSelectCustomFont: (ImportedFont) -> Void
    let onDeleteCustomFont: (ImportedFont) -> Void
    let onOpenFontImporter: () -> Void
    let onToggleAutoPage: () -> Void
    let onSetAutoPageInterval: (Double) -> Void
    let onRulesChanged: () -> Void
    let onResetConfig: () -> Void

    public init(
        config: ReaderConfig,
        importedFonts: [ImportedFont] = [],
        isAutoPaging: Bool,
        onUpdateConfig: @escaping (ReaderConfig) -> Void,
        onSelectCustomFont: @escaping (ImportedFont) -> Void = { _ in },
        onDeleteCustomFont: @escaping (ImportedFont) -> Void = { _ in },
        onOpenFontImporter: @escaping () -> Void = {},
        onToggleAutoPage: @escaping () -> Void,
        onSetAutoPageInterval: @escaping (Double) -> Void,
        onRulesChanged: @escaping () -> Void = {},
        onResetConfig: @escaping () -> Void) {
        self.config = config
        self.importedFonts = importedFonts
        self.isAutoPaging = isAutoPaging
        self.onUpdateConfig = onUpdateConfig
        self.onSelectCustomFont = onSelectCustomFont
        self.onDeleteCustomFont = onDeleteCustomFont
        self.onOpenFontImporter = onOpenFontImporter
        self.onToggleAutoPage = onToggleAutoPage
        self.onSetAutoPageInterval = onSetAutoPageInterval
        self.onRulesChanged = onRulesChanged
        self.onResetConfig = onResetConfig
    }

    public var body: some View {
        NavigationStack {
            Form {
                interactionSection
                autoPageSection
                purifyAndChapterSection
                localFontsSection
                displaySection
                resetSection
            }
            .navigationTitle("更多阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .preferredColorScheme(config.theme.isDark ? .dark : .light)
        .presentationDetents([.medium, .large])
    }
}

private extension ReaderSettingsSheet {
    var interactionSection: some View {
        Section {
            Toggle(
                "夜间模式",
                isOn: Binding(
                    get: { config.theme.isDark },
                    set: { wantDark in
                        if wantDark != config.theme.isDark {
                            update { $0.toggleNightMode() }
                        }
                    }))

            Toggle(
                "触感震动反馈",
                isOn: binding(\.isHapticEnabled))

            Toggle(
                "阅读时屏幕常亮",
                isOn: binding(\.keepScreenOn))

            Toggle(
                "点击屏幕翻页",
                isOn: binding(\.tapToTurnPage))

            NavigationLink {
                TapZoneConfigView(tapZoneConfig: binding(\.tapZoneConfig))
            } label: {
                HStack {
                    Label("点按区域自定义", systemImage: "square.grid.3x3")
                    Spacer()
                    Text(tapZoneSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(
                "音量键翻页",
                isOn: binding(\.volumeKeyPageTurn))

            Toggle(
                "iPad 大屏双页分栏",
                isOn: binding(\.enableIPadDualPage))
        } header: {
            Label("交互与夜间模式", systemImage: "hand.tap")
        } footer: {
            Text("支持 3×3 九宫格自定义点按区域；开启「音量键翻页」后按音量+上一页、音量-下一页（朗读时自动恢复音量调节）。")
        }
    }

    var tapZoneSummary: String {
        if let preset = TapZonePreset.allCases.first(where: { $0.config == config.tapZoneConfig }) {
            return preset.rawValue
        }
        return "自定义"
    }

    var purifyAndChapterSection: some View {
        Section {
            Toggle("启用替换净化规则", isOn: binding(\.enableReplaceRule))
            Toggle("去除正文重复章节标题", isOn: binding(\.removeSameTitle))
            Toggle("智能重新分段（修复断行）", isOn: binding(\.reSegment))

            NavigationLink {
                ReplaceRuleManageView(onRulesChanged: onRulesChanged)
            } label: {
                Label("管理替换净化规则 (Legado JSON)", systemImage: "wand.and.stars")
            }

            NavigationLink {
                TxtTocRuleManageView()
            } label: {
                Label("TXT 目录分章规则 (txtTocRule)", systemImage: "list.bullet.indent")
            }
        } header: {
            Label("章节优化与净化排版", systemImage: "wand.and.stars")
        } footer: {
            Text("兼容 Legado Android 替换净化与 TXT 目录正则规则，修改后自动实时刷新当前章节排版。")
        }
    }

    var localFontsSection: some View {
        Section {
            Button {
                onOpenFontImporter()
            } label: {
                HStack {
                    Label("选择或导入字体", systemImage: "textformat.alt")
                    Spacer()
                    Text(config.customFontDisplayName ?? "系统默认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ForEach(importedFonts) { font in
                let isSelected = config.customFontName == font.postScriptName
                HStack {
                    Button {
                        onSelectCustomFont(font)
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
                        onDeleteCustomFont(font)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
            }
        } header: {
            Label("自定义字体", systemImage: "character.book.closed")
        } footer: {
            Text("支持直接从「文件」App 导入字体，也可将字体文件放入「我的 iPhone / iPad -> Legado -> Fonts」目录。")
        }
    }

    var autoPageSection: some View {
        Section {
            Toggle(
                "开启自动翻页",
                isOn: Binding(
                    get: { isAutoPaging },
                    set: { _ in onToggleAutoPage() }))

            Picker("自动翻页方式", selection: binding(\.autoPageMode)) {
                ForEach(AutoPageMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            if config.autoPageMode == .smoothScroll {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("上下滚动速度")
                        Spacer()
                        Text("\(Int(config.autoScrollSpeed)) pt/秒")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { config.autoScrollSpeed },
                            set: { val in update { $0.autoScrollSpeed = val } }),
                        in: 15 ... 140,
                        step: 5)
                        .tint(.accentColor)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("翻页间隔")
                        Spacer()
                        Text("\(Int(config.autoPageIntervalSeconds)) 秒/页")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { config.autoPageIntervalSeconds },
                            set: { onSetAutoPageInterval($0) }),
                        in: 3 ... 30,
                        step: 1)
                        .tint(.accentColor)
                }
            }
        } header: {
            Label("自动阅读", systemImage: "play.circle")
        } footer: {
            Text("「上下滚动」采用丝滑匀速滚屏并自动跨章，手指触摸屏幕时自动暂停、松手恢复。")
        }
    }

    var displaySection: some View {
        Section {
            Picker("繁简转换", selection: binding(\.chineseConversion)) {
                ForEach(ChineseConversionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("显示页眉（章节标题与时间）", isOn: binding(\.showHeader))
            Toggle("显示页脚（页码、总进度与电量）", isOn: binding(\.showFooter))
            Toggle("显示页眉分隔线", isOn: binding(\.showHeaderDivider))
            Toggle("显示页脚分隔线", isOn: binding(\.showFooterDivider))
            Toggle("阅读时显示系统状态栏", isOn: binding(\.showStatusBar))
        } header: {
            Label("页眉、页脚与文字显示", systemImage: "rectangle.topthird.inset.filled")
        } footer: {
            Text("上、下、左、右边距可在阅读器底部「排版 -> 边距」面板中实时拖动预览。")
        }
    }

    var resetSection: some View {
        Section {
            Button(role: .destructive) {
                onResetConfig()
            } label: {
                Label("恢复默认阅读排版与设置", systemImage: "arrow.counterclockwise")
            }
        }
    }

    func binding<T>(_ keyPath: WritableKeyPath<ReaderConfig, T>) -> Binding<T> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { newValue in
                update { $0[keyPath: keyPath] = newValue }
            })
    }

    func update(_ mutate: (inout ReaderConfig) -> Void) {
        var next = config
        mutate(&next)
        onUpdateConfig(next)
    }
}
