import SwiftUI

// MARK: - 外观与快捷开关区

extension ReaderTypographyPanel {
    var appearanceControlsSection: some View {
        VStack(spacing: 14) {
            brightnessSection
            themesGridSection
            quickToggleButtons
            footerActionRow
        }
        .padding(.vertical, 2)
    }

    private var brightnessSection: some View {
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

    private var themesGridSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ReaderTheme.allCases) { theme in
                    let isSelected = config.theme == theme
                    Button {
                        update { $0.applyTheme(theme) }
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

    private var quickToggleButtons: some View {
        HStack(spacing: 8) {
            quickPillToggle(
                title: config.theme.isDark ? "日间模式" : "夜间模式",
                icon: config.theme.isDark ? "sun.max.fill" : "moon.fill",
                isOn: config.theme.isDark) {
                    update { $0.toggleNightMode() }
                }

            quickPillToggle(
                title: "震动反馈",
                icon: config.isHapticEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash",
                isOn: config.isHapticEnabled) {
                    update { $0.isHapticEnabled.toggle() }
                }

            quickPillToggle(
                title: isAutoPaging ? "停止自动" : "自动翻页",
                icon: isAutoPaging ? "pause.circle.fill" : "play.circle",
                isOn: isAutoPaging,
                action: onToggleAutoPage)
        }
    }

    private func quickPillToggle(
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

    private var footerActionRow: some View {
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
}
