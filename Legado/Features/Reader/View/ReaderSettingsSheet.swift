import SwiftUI

/// 阅读器更多设置原生抽屉（震动开关、屏幕常亮、点击/左手翻页、自动翻页、繁简转换、页眉页脚与上下边距）
public struct ReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let config: ReaderConfig
    let isAutoPaging: Bool
    let onUpdateConfig: (ReaderConfig) -> Void
    let onToggleAutoPage: () -> Void
    let onSetAutoPageInterval: (Double) -> Void
    let onResetConfig: () -> Void

    public init(
        config: ReaderConfig,
        isAutoPaging: Bool,
        onUpdateConfig: @escaping (ReaderConfig) -> Void,
        onToggleAutoPage: @escaping () -> Void,
        onSetAutoPageInterval: @escaping (Double) -> Void,
        onResetConfig: @escaping () -> Void) {
        self.config = config
        self.isAutoPaging = isAutoPaging
        self.onUpdateConfig = onUpdateConfig
        self.onToggleAutoPage = onToggleAutoPage
        self.onSetAutoPageInterval = onSetAutoPageInterval
        self.onResetConfig = onResetConfig
    }

    public var body: some View {
        NavigationStack {
            Form {
                interactionSection
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
        } header: {
            Label("交互与触感", systemImage: "hand.tap")
        } footer: {
            Text("关闭「触感震动反馈」将全局关闭震动；开启「左手模式」后点击左侧为下一页、右侧为上一页。")
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
