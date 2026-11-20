import SwiftUI

/// 阅读器九宫格点按区域自定义配置页面（支持一键预设 + 逐格自定义动作）
public struct TapZoneConfigView: View {
    @Binding private var tapZoneConfig: TapZoneConfig

    public init(tapZoneConfig: Binding<TapZoneConfig>) {
        _tapZoneConfig = tapZoneConfig
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                presetsSection
                interactiveGridPreview

                if !tapZoneConfig.hasMenuZone {
                    Label(
                        "当前未设置「呼出菜单」区域，点击屏幕正中将自动保底呼出菜单。",
                        systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text("轻触下方九宫格中任意区域，即可自定义该区域的点按翻页或快捷功能。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .navigationTitle("点按区域自定义")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷方案预设")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TapZonePreset.allCases) { preset in
                        let isSelected = tapZoneConfig == preset.config
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                tapZoneConfig = preset.config
                            }
                        } label: {
                            Text(preset.rawValue)
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var interactiveGridPreview: some View {
        VStack(spacing: 8) {
            ForEach(0 ..< 3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0 ..< 3, id: \.self) { col in
                        zoneCell(row: row, col: col)
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .aspectRatio(0.68, contentMode: .fit)
        .frame(maxHeight: 440)
    }

    private func zoneCell(row: Int, col: Int) -> some View {
        let current = tapZoneConfig.action(row: row, col: col)
        let tint = colorFor(action: current)

        return Menu {
            ForEach(TapZoneAction.allCases) { action in
                Button {
                    tapZoneConfig.setAction(action, row: row, col: col)
                } label: {
                    if action == current {
                        Label(action.rawValue, systemImage: "checkmark")
                    } else {
                        Label(action.rawValue, systemImage: action.systemImage)
                    }
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: current.systemImage)
                    .font(.title3.weight(.medium))
                Text(current.shortLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.32), lineWidth: 1))
        }
    }

    private func colorFor(action: TapZoneAction) -> Color {
        switch action {
        case .nextPage: return .blue
        case .prevPage: return .orange
        case .toggleHUD: return .purple
        case .nextChapter: return .teal
        case .prevChapter: return .mint
        case .toggleNightMode: return .indigo
        case .none: return .secondary
        }
    }
}
