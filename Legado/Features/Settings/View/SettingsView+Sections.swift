import SwiftUI

// MARK: - SettingsView 辅助分区扩展

extension SettingsView {
    var readingPreferencesSection: some View {
        Section {
            Toggle("触感震动反馈", isOn: readerBinding(\.isHapticEnabled))
            Toggle("阅读时屏幕常亮", isOn: readerBinding(\.keepScreenOn))
            Toggle("点击屏幕翻页", isOn: readerBinding(\.tapToTurnPage))
            Toggle("左手翻页模式", isOn: readerBinding(\.leftHandMode))

            Picker("繁简转换", selection: readerBinding(\.chineseConversion)) {
                ForEach(ChineseConversionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("显示页眉（章节名与时间）", isOn: readerBinding(\.showHeader))
            Toggle("显示页脚（页码、总进度与电量）", isOn: readerBinding(\.showFooter))

            Button(role: .destructive) {
                viewModel.send(.resetReaderConfig)
            } label: {
                Label("恢复默认阅读排版", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Label("阅读与交互偏好", systemImage: "book.pages")
        } footer: {
            Text("字号、字体、行距、段距、字距、边距与主题配色可在阅读器「排版」面板中实时调节并自动保存。")
        }
    }

    private func readerBinding<T>(_ keyPath: WritableKeyPath<ReaderConfig, T>) -> Binding<T> {
        Binding(
            get: { viewModel.state.readerConfig[keyPath: keyPath] },
            set: { newValue in
                var updated = viewModel.state.readerConfig
                updated[keyPath: keyPath] = newValue
                viewModel.send(.updateReaderConfig(updated))
            })
    }

    var storageSection: some View {
        Section {
            HStack {
                Text("离线章节缓存")
                Spacer()
                Text(viewModel.state.formattedCacheSize)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                isShowingClearAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("清空所有离线章节正文")
                }
            }
        } header: {
            Label("存储与离线缓存", systemImage: "internaldrive")
        }
    }

    var purifySection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("智能去广告与防盗水印净化")
                        .font(.subheadline.weight(.medium))
                    Text("自动剔除“本章未完请翻页”、推广外链与乱码广告行")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            }
        } header: {
            Label("正文净化规则", systemImage: "wand.and.stars")
        }
    }

    var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0 (iOS 18+ 原生)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("视觉风格")
                Spacer()
                Text("Apple Liquid Glass / Vibrancy")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("架构设计")
                Spacer()
                Text("MVI + Clean Architecture")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("开源致敬")
                Spacer()
                Text("Legado (阅读 3.0)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("关于应用", systemImage: "info.circle")
        }
    }
}
