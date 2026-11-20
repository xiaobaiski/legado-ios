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
        self.onResetConfig = onResetConfig
    }

    public var body: some View {
        NavigationStack {
            Form {
                interactionSection
                localFontsSection
                autoPageSection
                typographyDetailSection
                displaySection
                resetSection
            }
            .scrollContentBackground(.hidden)
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
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }
}

private extension ReaderSettingsSheet {
    var interactionSection: some View {
        Section {
            Toggle(
                "触感震动反馈",
                isOn: binding(\.isHapticEnabled))

            Toggle(
                "阅读时屏幕常亮",
                isOn: binding(\.keepScreenOn))

            Toggle(
                "点击屏幕翻页",
                isOn: binding(\.tapToTurnPage))

            Toggle(
                "左手翻页模式",
                isOn: binding(\.leftHandMode))

            Toggle(
                "音量键翻页",
                isOn: binding(\.volumeKeyPageTurn))

            Toggle(
                "iPad 大屏双页分栏",
                isOn: binding(\.enableIPadDualPage))
        } header: {
            Label("交互与触感", systemImage: "hand.tap")
        } footer: {
            Text("开启「音量键翻页」后按音量+上一页、音量-下一页（朗读听书时自动恢复音量调节）。")
        }
    }

    var localFontsSection: some View {
        Section {
            Button {
                onOpenFontImporter()
            } label: {
                Label("导入本地字体 (TTF / OTF / TTC)", systemImage: "textformat.alt")
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
                "自动翻页",
                isOn: Binding(
                    get: { isAutoPaging },
                    set: { _ in onToggleAutoPage() }))

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
        } header: {
            Label("自动阅读", systemImage: "play.circle")
        }
    }

    var typographyDetailSection: some View {
        Section {
            Picker("繁简转换", selection: binding(\.chineseConversion)) {
                ForEach(ChineseConversionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("顶部边距")
                    Spacer()
                    Text("\(Int(config.topMargin)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(config.topMargin) },
                        set: { val in update { $0.topMargin = CGFloat(val) } }),
                    in: 32 ... 80,
                    step: 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("底部边距")
                    Spacer()
                    Text("\(Int(config.bottomMargin)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(config.bottomMargin) },
                        set: { val in update { $0.bottomMargin = CGFloat(val) } }),
                    in: 24 ... 72,
                    step: 2)
            }
        } header: {
            Label("文本与边距细节", systemImage: "text.alignleft")
        }
    }

    var displaySection: some View {
        Section {
            Toggle("显示页眉（章节标题与时间）", isOn: binding(\.showHeader))
            Toggle("显示页脚（页码、总进度与电量）", isOn: binding(\.showFooter))
            Toggle("阅读时显示系统状态栏", isOn: binding(\.showStatusBar))
        } header: {
            Label("页眉与页脚", systemImage: "rectangle.topthird.inset.filled")
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
