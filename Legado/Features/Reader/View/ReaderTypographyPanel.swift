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
    let importedFonts: [ImportedFont]
    let isAutoPaging: Bool
    let onUpdateConfig: (ReaderConfig) -> Void
    let onSelectCustomFont: (ImportedFont) -> Void
    let onOpenFontImporter: () -> Void
    let onResetConfig: () -> Void
    let onOpenMoreSettings: () -> Void
    let onToggleAutoPage: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: PanelTab = .layout

    public init(
        config: ReaderConfig,
        importedFonts: [ImportedFont] = [],
        isAutoPaging: Bool = false,
        onUpdateConfig: @escaping (ReaderConfig) -> Void,
        onSelectCustomFont: @escaping (ImportedFont) -> Void = { _ in },
        onOpenFontImporter: @escaping () -> Void = {},
        onResetConfig: @escaping () -> Void,
        onOpenMoreSettings: @escaping () -> Void,
        onToggleAutoPage: @escaping () -> Void) {
        self.config = config
        self.importedFonts = importedFonts
        self.isAutoPaging = isAutoPaging
        self.onUpdateConfig = onUpdateConfig
        self.onSelectCustomFont = onSelectCustomFont
        self.onOpenFontImporter = onOpenFontImporter
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
            .frame(maxHeight: horizontalSizeClass == .regular ? 380 : 310)
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
        let importedPostScriptNames = Set(importedFonts.map(\.postScriptName))

        return HStack(spacing: 8) {
            Text("字体")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    fontChip(title: "系统默认", isSelected: config.customFontName == nil) {
                        update {
                            $0.customFontName = nil
                            $0.customFontDisplayName = nil
                            $0.fontFamily = .system
                        }
                    }

                    if let customPS = config.customFontName,
                       !customPS.isEmpty,
                       !importedPostScriptNames.contains(customPS) {
                        fontChip(title: config.customFontDisplayName ?? customPS, isSelected: true) {
                            onOpenFontImporter()
                        }
                    }

                    ForEach(importedFonts) { font in
                        let isSelected = config.customFontName == font.postScriptName
                        fontChip(title: font.displayName, isSelected: isSelected) {
                            onSelectCustomFont(font)
                        }
                    }

                    Button(action: onOpenFontImporter) {
                        Label("选择字体", systemImage: "textformat")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.12)))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func fontChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PageTurnMode.allCases) { mode in
                        let isSelected = config.pageTurnMode == mode
                        Button {
                            update { $0.pageTurnMode = mode }
                        } label: {
                            Text(mode.rawValue)
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(
                                            isSelected
                                                ? Color.accentColor.opacity(0.15)
                                                : Color.secondary.opacity(0.10)))
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

extension ReaderTypographyPanel {
    func update(_ mutate: (inout ReaderConfig) -> Void) {
        var next = config
        mutate(&next)
        onUpdateConfig(next)
    }
}
