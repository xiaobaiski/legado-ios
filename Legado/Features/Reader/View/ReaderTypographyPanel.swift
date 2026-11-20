import SwiftUI

/// 阅读器液态玻璃排版与外观面板（对标 Legado：字号/字体/加粗/行距/段距/字距/边距/缩进/对齐/亮度/主题/翻页）
public struct ReaderTypographyPanel: View {
    private enum PanelTab: String, CaseIterable, Identifiable {
        case layout = "排版"
        case appearance = "外观"

        var id: String {
            rawValue
        }
    }

    let config: ReaderConfig
    let isAutoPaging: Bool
    let onUpdateConfig: (ReaderConfig) -> Void
    let onResetConfig: () -> Void
    let onOpenMoreSettings: () -> Void
    let onToggleAutoPage: () -> Void

    @State private var selectedTab: PanelTab = .layout

    public init(
        config: ReaderConfig,
        isAutoPaging: Bool = false,
        onUpdateConfig: @escaping (ReaderConfig) -> Void,
        onResetConfig: @escaping () -> Void,
        onOpenMoreSettings: @escaping () -> Void,
        onToggleAutoPage: @escaping () -> Void) {
        self.config = config
        self.isAutoPaging = isAutoPaging
        self.onUpdateConfig = onUpdateConfig
        self.onResetConfig = onResetConfig
        self.onOpenMoreSettings = onOpenMoreSettings
        self.onToggleAutoPage = onToggleAutoPage
    }

    public var body: some View {
        VStack(spacing: 12) {
            Picker("设置分组", selection: $selectedTab) {
                ForEach(PanelTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(showsIndicators: false) {
                if selectedTab == .layout {
                    layoutControlsSection
                } else {
                    appearanceControlsSection
                }
            }
            .frame(maxHeight: 310)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

// MARK: - 排版控制区

private extension ReaderTypographyPanel {
    var layoutControlsSection: some View {
        VStack(spacing: 12) {
            fontSizeRow
            fontFamilyRow
            spacingSliders
            indentAndAlignmentRow
            pageTurnModeRow
        }
        .padding(.vertical, 2)
    }

    var fontSizeRow: some View {
        HStack(spacing: 10) {
            Text("字号")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            Button {
                update { $0.fontSize = max($0.fontSize - 1, 12) }
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text("\(Int(config.fontSize))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 30)

            Button {
                update { $0.fontSize = min($0.fontSize + 1, 36) }
            } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Button {
                update { $0.isBoldFont.toggle() }
            } label: {
                Text("加粗")
                    .font(.caption.weight(config.isBoldFont ? .bold : .regular))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        config.isBoldFont ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    .foregroundStyle(config.isBoldFont ? Color.accentColor : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .tint(.primary)
    }

    var fontFamilyRow: some View {
        HStack(spacing: 8) {
            Text("字体")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            ForEach(ReaderFontFamily.allCases) { family in
                let isSelected = config.fontFamily == family
                Button {
                    update { $0.fontFamily = family }
                } label: {
                    Text(family.rawValue)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10)))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    isSelected ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.12),
                                    lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var spacingSliders: some View {
        VStack(spacing: 8) {
            sliderRow(
                title: "行距",
                valueText: "\(Int(config.lineSpacing))",
                value: Binding(
                    get: { Double(config.lineSpacing) },
                    set: { newValue in update { $0.lineSpacing = CGFloat(newValue) } }),
                range: 0 ... 24,
                step: 1)

            sliderRow(
                title: "段距",
                valueText: "\(Int(config.paragraphSpacing))",
                value: Binding(
                    get: { Double(config.paragraphSpacing) },
                    set: { newValue in update { $0.paragraphSpacing = CGFloat(newValue) } }),
                range: 0 ... 32,
                step: 1)

            sliderRow(
                title: "字距",
                valueText: String(format: "%.1f", config.letterSpacing),
                value: Binding(
                    get: { Double(config.letterSpacing) },
                    set: { newValue in update { $0.letterSpacing = CGFloat(newValue) } }),
                range: -1 ... 6,
                step: 0.5)

            sliderRow(
                title: "边距",
                valueText: "\(Int(config.horizontalMargin))",
                value: Binding(
                    get: { Double(config.horizontalMargin) },
                    set: { newValue in update { $0.horizontalMargin = CGFloat(newValue) } }),
                range: 8 ... 40,
                step: 2)
        }
    }

    var indentAndAlignmentRow: some View {
        HStack(spacing: 8) {
            Text("缩进")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            ForEach([0, 1, 2], id: \.self) { indent in
                let isSelected = config.paragraphIndent == indent
                let label = indent == 0 ? "无" : "\(indent)字"
                Button {
                    update { $0.paragraphIndent = indent }
                } label: {
                    Text(label)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            Button {
                update { $0.isTextJustified.toggle() }
            } label: {
                Label(
                    config.isTextJustified ? "两端对齐" : "左对齐",
                    systemImage: config.isTextJustified ? "text.justify" : "text.alignleft")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    var pageTurnModeRow: some View {
        HStack(spacing: 8) {
            Text("翻页")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            ForEach(PageTurnMode.allCases) { mode in
                let isSelected = config.pageTurnMode == mode
                Button {
                    update { $0.pageTurnMode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10)))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    isSelected ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.12),
                                    lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            Slider(value: value, in: range, step: step)
                .tint(.accentColor)

            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

// MARK: - 外观与快捷开关区

private extension ReaderTypographyPanel {
    var appearanceControlsSection: some View {
        VStack(spacing: 14) {
            brightnessSection
            themesGridSection
            quickToggleButtons
            footerActionRow
        }
        .padding(.vertical, 2)
    }

    var brightnessSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { config.customBrightness },
                    set: { newVal in
                        update {
                            $0.followSystemBrightness = false
                            $0.customBrightness = newVal
                        }
                    }),
                in: 0.05 ... 1.0)
                .tint(.accentColor)

            Image(systemName: "sun.max.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                update { $0.followSystemBrightness.toggle() }
            } label: {
                Text("系统")
                    .font(.caption.weight(config.followSystemBrightness ? .semibold : .regular))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                config.followSystemBrightness
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.secondary.opacity(0.12)))
                    .foregroundStyle(config.followSystemBrightness ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
        }
    }

    var themesGridSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ReaderTheme.allCases) { theme in
                    let isSelected = config.theme == theme
                    Button {
                        update { $0.theme = theme }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(theme.backgroundColor)
                                    .frame(width: 38, height: 38)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                                                lineWidth: isSelected ? 2.5 : 0.8))

                                Text("文")
                                    .font(.caption.bold())
                                    .foregroundStyle(theme.textColor)
                            }

                            Text(theme.name)
                                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    var quickToggleButtons: some View {
        HStack(spacing: 8) {
            quickPillToggle(
                title: "震动反馈",
                icon: config.isHapticEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash",
                isOn: config.isHapticEnabled) {
                    update { $0.isHapticEnabled.toggle() }
                }

            quickPillToggle(
                title: "屏幕常亮",
                icon: config.keepScreenOn ? "sun.max" : "moon.zzz",
                isOn: config.keepScreenOn) {
                    update { $0.keepScreenOn.toggle() }
                }

            quickPillToggle(
                title: isAutoPaging ? "停止自动" : "自动翻页",
                icon: isAutoPaging ? "pause.circle.fill" : "play.circle",
                isOn: isAutoPaging,
                action: onToggleAutoPage)
        }
    }

    func quickPillToggle(
        title: String,
        icon: String,
        isOn: Bool,
        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(isOn ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10)))
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    var footerActionRow: some View {
        HStack(spacing: 10) {
            Button(action: onOpenMoreSettings) {
                Label("更多阅读设置", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onResetConfig) {
                Label("恢复默认", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    func update(_ mutate: (inout ReaderConfig) -> Void) {
        var next = config
        mutate(&next)
        onUpdateConfig(next)
    }
}
