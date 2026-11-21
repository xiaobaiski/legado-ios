import SwiftUI

/// 自定义主题配色与护眼暖光滤镜设置视图（对标 Legado `BgTextConfigDialog`）
public struct CustomThemeConfigView: View {
    private struct ColorPalettePreset: Identifiable {
        let id: String
        let name: String
        let bgHex: String
        let textHex: String
    }

    private static let presets: [ColorPalettePreset] = [
        ColorPalettePreset(id: "eink", name: "墨水屏灰", bgHex: "#ECECE7", textHex: "#1E1E1E"),
        ColorPalettePreset(id: "apricot", name: "暖杏纸", bgHex: "#F7ECD8", textHex: "#3A2E20"),
        ColorPalettePreset(id: "matcha", name: "豆沙绿", bgHex: "#CCE8CF", textHex: "#1F3322"),
        ColorPalettePreset(id: "slate", name: "午夜蓝", bgHex: "#16202C", textHex: "#C7D3E0"),
        ColorPalettePreset(id: "oled", name: "柔灰暗夜", bgHex: "#0B0C0E", textHex: "#9DA3AD"),
    ]

    @Binding private var config: ReaderConfig

    public init(config: Binding<ReaderConfig>) {
        _config = config
    }

    public var body: some View {
        Form {
            previewSection
            customColorSection
            eyeCareFilterSection
            presetsSection
        }
        .navigationTitle("自定义配色与护眼")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewSection: some View {
        Section("实时效果预览") {
            ZStack {
                config.effectiveBackgroundColor
                VStack(alignment: .leading, spacing: 8) {
                    Text("第一章 星海远航")
                        .font(config.resolvedSwiftUIFont(size: config.fontSize + 2, isBold: true))
                    Text("　　柔和恰当的纸面底色与对比度，能显著缓解长时间连续阅读带来的视觉疲劳。")
                        .font(config.resolvedSwiftUIFont())
                        .lineSpacing(config.lineSpacing)
                }
                .foregroundStyle(config.effectiveTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

                if config.eyeProtectionWarmth > 0 {
                    Color(red: 1.0, green: 0.62, blue: 0.12)
                        .opacity(config.eyeProtectionWarmth * 0.45)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private var customColorSection: some View {
        Section {
            Toggle(
                "启用自定义配色主题",
                isOn: Binding(
                    get: { config.theme == .custom },
                    set: { enabled in
                        if enabled {
                            config.applyTheme(.custom)
                        } else {
                            config.applyTheme(.paper)
                        }
                    }))

            ColorPicker(
                "自定义背景颜色",
                selection: Binding(
                    get: {
                        HexColorCodec.color(
                            from: config.customBackgroundHex,
                            fallback: ReaderTheme.paper.backgroundColor)
                    },
                    set: { newColor in
                        config.customBackgroundHex = HexColorCodec.hexString(from: newColor)
                        config.applyTheme(.custom)
                    }),
                supportsOpacity: false)

            ColorPicker(
                "自定义正文颜色",
                selection: Binding(
                    get: { HexColorCodec.color(from: config.customTextHex, fallback: ReaderTheme.paper.textColor) },
                    set: { newColor in
                        config.customTextHex = HexColorCodec.hexString(from: newColor)
                        config.applyTheme(.custom)
                    }),
                supportsOpacity: false)
        } header: {
            Text("自由配色")
        }
    }

    private var eyeCareFilterSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("护眼暖光滤镜（防蓝光）")
                    Spacer()
                    Text("\(Int(config.eyeProtectionWarmth * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $config.eyeProtectionWarmth, in: 0 ... 0.45, step: 0.05)
                    .tint(.orange)
            }
        } header: {
            Text("护眼滤镜")
        } footer: {
            Text("叠加一层柔和琥珀暖光于书页上方，夜间阅读更温和（所有主题通用）。")
        }
    }

    private var presetsSection: some View {
        Section("经典推荐配色方案") {
            ForEach(Self.presets) { preset in
                Button {
                    config.customBackgroundHex = preset.bgHex
                    config.customTextHex = preset.textHex
                    config.applyTheme(.custom)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(HexColorCodec.color(from: preset.bgHex, fallback: .white))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text("文")
                                    .font(.caption2.bold())
                                    .foregroundStyle(HexColorCodec.color(from: preset.textHex, fallback: .black)))
                            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))

                        Text(preset.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if config.theme == .custom &&
                            config.customBackgroundHex.caseInsensitiveCompare(preset.bgHex) == .orderedSame {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
