import SwiftUI

/// 页眉与页脚 6 槽位自定义配置视图（对标 Legado `TipConfigDialog`）
public struct HeaderFooterConfigView: View {
    @Binding private var config: ReaderConfig

    public init(config: Binding<ReaderConfig>) {
        _config = config
    }

    public var body: some View {
        Form {
            previewSection
            headerSlotsSection
            footerSlotsSection
            detailSection
        }
        .navigationTitle("页眉与页脚自定义")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") {
                    config.tipConfig = .default
                    config.showHeader = true
                    config.showFooter = true
                    config.showHeaderDivider = false
                    config.showFooterDivider = false
                }
                .font(.subheadline)
            }
        }
    }

    private var previewSection: some View {
        Section("实时预览") {
            VStack(spacing: 12) {
                if config.showHeader {
                    VStack(spacing: 4) {
                        HStack {
                            Text(sampleText(for: config.tipConfig.headerLeft))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(sampleText(for: config.tipConfig.headerCenter))
                                .frame(maxWidth: .infinity, alignment: .center)
                            Text(sampleText(for: config.tipConfig.headerRight))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: config.tipConfig.tipFontSize))
                        .foregroundStyle(config.effectiveTextColor.opacity(0.58))
                        .lineLimit(1)

                        if config.showHeaderDivider {
                            Rectangle()
                                .fill(config.effectiveTextColor.opacity(0.18))
                                .frame(height: 0.5)
                        }
                    }
                }

                Text("　　春风拂过书页，每一处页眉与页脚信息都可按你的阅读习惯自由编排。")
                    .font(.footnote)
                    .foregroundStyle(config.effectiveTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)

                if config.showFooter {
                    VStack(spacing: 4) {
                        if config.showFooterDivider {
                            Rectangle()
                                .fill(config.effectiveTextColor.opacity(0.18))
                                .frame(height: 0.5)
                        }

                        HStack {
                            Text(sampleText(for: config.tipConfig.footerLeft))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(sampleText(for: config.tipConfig.footerCenter))
                                .frame(maxWidth: .infinity, alignment: .center)
                            Text(sampleText(for: config.tipConfig.footerRight))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: config.tipConfig.tipFontSize))
                        .foregroundStyle(config.effectiveTextColor.opacity(0.58))
                        .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .background(config.effectiveBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private var headerSlotsSection: some View {
        Section("页眉显示内容") {
            Toggle("显示页眉", isOn: $config.showHeader)
            if config.showHeader {
                slotPicker("页眉左侧", selection: $config.tipConfig.headerLeft)
                slotPicker("页眉居中", selection: $config.tipConfig.headerCenter)
                slotPicker("页眉右侧", selection: $config.tipConfig.headerRight)
                Toggle("显示页眉分隔线", isOn: $config.showHeaderDivider)
            }
        }
    }

    private var footerSlotsSection: some View {
        Section("页脚显示内容") {
            Toggle("显示页脚", isOn: $config.showFooter)
            if config.showFooter {
                slotPicker("页脚左侧", selection: $config.tipConfig.footerLeft)
                slotPicker("页脚居中", selection: $config.tipConfig.footerCenter)
                slotPicker("页脚右侧", selection: $config.tipConfig.footerRight)
                Toggle("显示页脚分隔线", isOn: $config.showFooterDivider)
            }
        }
    }

    private var detailSection: some View {
        Section("样式细节") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("页眉 / 页脚字号")
                    Spacer()
                    Text("\(Int(config.tipConfig.tipFontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(config.tipConfig.tipFontSize) },
                        set: { config.tipConfig.tipFontSize = CGFloat($0) }),
                    in: 9 ... 16,
                    step: 1)
                    .tint(.accentColor)
            }

            Toggle("阅读时显示系统状态栏", isOn: $config.showStatusBar)
        }
    }

    private func slotPicker(_ title: String, selection: Binding<ReadTipItem>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ReadTipItem.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
    }

    private func sampleText(for item: ReadTipItem) -> String {
        switch item {
        case .none: return ""
        case .bookTitle: return "星辰大海"
        case .chapterTitle: return "第一章 启航"
        case .time: return "21:30"
        case .battery: return "88%"
        case .pageAndTotal: return "3/12"
        case .chapterProgress: return "25%"
        case .bookProgress: return "42.5%"
        case .chapterIndex: return "12/380"
        case .remainingPages: return "余9页"
        }
    }
}
