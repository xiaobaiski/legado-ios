import SwiftUI

/// 正文章节大标题排版配置视图（对标 Legado `titleMode` / `titleSize` / `titleTopSpacing` / `titleBottomSpacing`）
public struct ChapterTitleConfigView: View {
    @Binding private var config: ReaderConfig

    public init(config: Binding<ReaderConfig>) {
        _config = config
    }

    public var body: some View {
        Form {
            previewSection
            controlsSection
        }
        .navigationTitle("正文章节标题样式")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") {
                    config.titleStyle = .default
                }
                .font(.subheadline)
            }
        }
    }

    private var previewSection: some View {
        Section("实时预览") {
            VStack(alignment: config.titleStyle.alignment == .center ? .center : .leading, spacing: 0) {
                if config.titleStyle.alignment != .hidden {
                    Text("第一章 宿命之始")
                        .font(config.resolvedSwiftUIFont(
                            size: config.fontSize + config.titleStyle.sizeDelta,
                            isBold: true))
                        .foregroundStyle(config.effectiveTextColor)
                        .multilineTextAlignment(config.titleStyle.alignment == .center ? .center : .leading)
                        .padding(.top, config.titleStyle.topSpacing)
                        .padding(.bottom, config.titleStyle.bottomSpacing)
                }

                Text("　　夜幕降临，微凉的晚风吹拂过荒野，远方的钟声缓缓响起，新的旅程自此启程。")
                    .font(config.resolvedSwiftUIFont())
                    .lineSpacing(config.lineSpacing)
                    .foregroundStyle(config.effectiveTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(config.effectiveBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private var controlsSection: some View {
        Section("标题排版参数") {
            Picker("显示位置", selection: $config.titleStyle.alignment) {
                ForEach(ChapterTitleAlignment.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if config.titleStyle.alignment != .hidden {
                sliderRow(
                    title: "标题相对字号",
                    valueText: "+\(Int(config.titleStyle.sizeDelta)) pt",
                    value: Binding(
                        get: { Double(config.titleStyle.sizeDelta) },
                        set: { config.titleStyle.sizeDelta = CGFloat($0) }),
                    range: 0 ... 12,
                    step: 1)

                sliderRow(
                    title: "标题上间距",
                    valueText: "\(Int(config.titleStyle.topSpacing)) pt",
                    value: Binding(
                        get: { Double(config.titleStyle.topSpacing) },
                        set: { config.titleStyle.topSpacing = CGFloat($0) }),
                    range: 0 ... 48,
                    step: 2)

                sliderRow(
                    title: "标题下间距",
                    valueText: "\(Int(config.titleStyle.bottomSpacing)) pt",
                    value: Binding(
                        get: { Double(config.titleStyle.bottomSpacing) },
                        set: { config.titleStyle.bottomSpacing = CGFloat($0) }),
                    range: 0 ... 48,
                    step: 2)
            }
        }
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(.accentColor)
        }
    }
}
