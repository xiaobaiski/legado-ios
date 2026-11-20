import SwiftUI

/// 阅读器液态玻璃控制面板 (HUD Overlay)
public struct ReaderHUDView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var draggingChapterIndex: Double?

    let bookTitle: String
    let currentChapterTitle: String
    let currentChapterIndex: Int
    let totalChapters: Int
    let chapters: [Chapter]
    let config: ReaderConfig
    let importedFonts: [ImportedFont]
    let safeAreaTop: CGFloat
    let isConfigOpen: Bool
    let isAutoPaging: Bool
    let isLocalFile: Bool
    let onBack: () -> Void
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onSliderChange: (Double) -> Void
    let onOpenToc: () -> Void
    let onToggleConfig: () -> Void
    let onUpdateConfig: (ReaderConfig) -> Void
    let onSelectCustomFont: (ImportedFont) -> Void
    let onOpenFontImporter: () -> Void
    let onToggleNightMode: () -> Void
    let onResetConfig: () -> Void
    let onOpenMoreSettings: () -> Void
    let onToggleAutoPage: () -> Void
    let onStartTTS: () -> Void
    let onOpenChangeSource: () -> Void
    let onOpenSearch: () -> Void
    let isBookmarked: Bool
    let onToggleBookmark: () -> Void
    public let onOpenCache: () -> Void

    public init(
        bookTitle: String,
        currentChapterTitle: String,
        currentChapterIndex: Int,
        totalChapters: Int,
        chapters: [Chapter] = [],
        config: ReaderConfig,
        importedFonts: [ImportedFont] = [],
        safeAreaTop: CGFloat = 48,
        isConfigOpen: Bool,
        isAutoPaging: Bool = false,
        isLocalFile: Bool = false,
        onBack: @escaping () -> Void,
        onPreviousChapter: @escaping () -> Void,
        onNextChapter: @escaping () -> Void,
        onSliderChange: @escaping (Double) -> Void,
        onOpenToc: @escaping () -> Void,
        onToggleConfig: @escaping () -> Void,
        onUpdateConfig: @escaping (ReaderConfig) -> Void = { _ in },
        onSelectCustomFont: @escaping (ImportedFont) -> Void = { _ in },
        onOpenFontImporter: @escaping () -> Void = {},
        onToggleNightMode: @escaping () -> Void = {},
        onResetConfig: @escaping () -> Void = {},
        onOpenMoreSettings: @escaping () -> Void = {},
        onToggleAutoPage: @escaping () -> Void = {},
        onStartTTS: @escaping () -> Void = {},
        onOpenChangeSource: @escaping () -> Void = {},
        onOpenSearch: @escaping () -> Void = {},
        isBookmarked: Bool = false,
        onToggleBookmark: @escaping () -> Void = {},
        onOpenCache: @escaping () -> Void = {}) {
        self.bookTitle = bookTitle
        self.currentChapterTitle = currentChapterTitle
        self.currentChapterIndex = currentChapterIndex
        self.totalChapters = totalChapters
        self.chapters = chapters
        self.config = config
        self.importedFonts = importedFonts
        self.safeAreaTop = safeAreaTop
        self.isConfigOpen = isConfigOpen
        self.isAutoPaging = isAutoPaging
        self.isLocalFile = isLocalFile
        self.onBack = onBack
        self.onPreviousChapter = onPreviousChapter
        self.onNextChapter = onNextChapter
        self.onSliderChange = onSliderChange
        self.onOpenToc = onOpenToc
        self.onToggleConfig = onToggleConfig
        self.onUpdateConfig = onUpdateConfig
        self.onSelectCustomFont = onSelectCustomFont
        self.onOpenFontImporter = onOpenFontImporter
        self.onToggleNightMode = onToggleNightMode
        self.onResetConfig = onResetConfig
        self.onOpenMoreSettings = onOpenMoreSettings
        self.onToggleAutoPage = onToggleAutoPage
        self.onStartTTS = onStartTTS
        self.onOpenChangeSource = onOpenChangeSource
        self.onOpenSearch = onOpenSearch
        self.isBookmarked = isBookmarked
        self.onToggleBookmark = onToggleBookmark
        self.onOpenCache = onOpenCache
    }

    public var body: some View {
        VStack {
            topBar

            Spacer()

            VStack(spacing: 12) {
                if isConfigOpen {
                    ReaderTypographyPanel(
                        config: config,
                        importedFonts: importedFonts,
                        isAutoPaging: isAutoPaging,
                        onUpdateConfig: onUpdateConfig,
                        onSelectCustomFont: onSelectCustomFont,
                        onOpenFontImporter: onOpenFontImporter,
                        onResetConfig: onResetConfig,
                        onOpenMoreSettings: onOpenMoreSettings,
                        onToggleAutoPage: onToggleAutoPage)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                bottomControlBar
            }
            .frame(maxWidth: horizontalSizeClass == .regular ? 620 : .infinity)
            .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
            .padding(.bottom, horizontalSizeClass == .regular ? 28 : 24)
        }
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(config.theme.isDark ? .dark : .light)
    }

    // MARK: - 顶部导航条

    private var topBar: some View {
        HStack {
            HStack(spacing: 10) {
                circleIconButton(systemName: "chevron.left", action: onBack)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(currentChapterTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                circleIconButton(
                    systemName: config.theme.isDark ? "sun.max.fill" : "moon.fill",
                    foreground: config.theme.isDark ? .yellow : .primary,
                    action: onToggleNightMode)

                circleIconButton(systemName: "magnifyingglass", action: onOpenSearch)

                if !isLocalFile {
                    circleIconButton(systemName: "arrow.down.circle", action: onOpenCache)
                }

                circleIconButton(
                    systemName: isBookmarked ? "bookmark.fill" : "bookmark",
                    foreground: isBookmarked ? Color.accentColor : .primary,
                    action: onToggleBookmark)

                circleIconButton(systemName: "gearshape", action: onOpenMoreSettings)
            }
            .frame(maxWidth: horizontalSizeClass == .regular ? 860 : .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
        .padding(.top, max(safeAreaTop, 14) + 6)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
        }
    }

    private func circleIconButton(
        systemName: String,
        foreground: Color = .primary,
        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(foreground)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
        }
    }

    // MARK: - 底部主控制栏

    private var bottomControlBar: some View {
        let maxIndex = max(totalChapters - 1, 1)
        let activeIndex = Int(draggingChapterIndex ?? Double(currentChapterIndex))
        let clampedIndex = min(max(activeIndex, 0), max(totalChapters - 1, 0))
        let previewTitle = (clampedIndex < chapters.count ? chapters[clampedIndex].title : currentChapterTitle)
        let progressPct = totalChapters > 1
            ? Double(clampedIndex) / Double(totalChapters - 1) * 100.0
            : 100.0

        return VStack(spacing: 12) {
            if draggingChapterIndex != nil {
                HStack(spacing: 8) {
                    Text(previewTitle)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(clampedIndex + 1)/\(max(totalChapters, 1)) · \(String(format: "%.1f%%", progressPct))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial)
                .clipShape(Capsule(style: .continuous))
            }

            HStack(spacing: 12) {
                Button(action: onPreviousChapter) {
                    Image(systemName: "backward.fill")
                        .font(.caption)
                }
                .disabled(currentChapterIndex <= 0)

                Slider(
                    value: Binding(
                        get: { draggingChapterIndex ?? Double(currentChapterIndex) },
                        set: { newValue in
                            draggingChapterIndex = newValue
                        }),
                    in: 0 ... Double(maxIndex),
                    step: 1,
                    onEditingChanged: { isEditing in
                        if !isEditing, let target = draggingChapterIndex {
                            let targetInt = min(max(Int(target.rounded()), 0), max(totalChapters - 1, 0))
                            draggingChapterIndex = nil
                            if targetInt != currentChapterIndex {
                                onSliderChange(Double(targetInt))
                            }
                        }
                    })
                    .tint(.accentColor)
                    .disabled(totalChapters <= 1)

                Button(action: onNextChapter) {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                }
                .disabled(currentChapterIndex >= totalChapters - 1)
            }
            .padding(.horizontal, 8)

            Divider()

            quickActionsBar
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }

    private var quickActionsBar: some View {
        HStack {
            quickActionButton(title: "目录", systemImage: "list.bullet", action: onOpenToc)
            quickActionButton(
                title: "排版",
                systemImage: "textformat.size",
                isActive: isConfigOpen,
                action: onToggleConfig)
            quickActionButton(title: "搜索", systemImage: "magnifyingglass", action: onOpenSearch)
            quickActionButton(title: "听书", systemImage: "headphones", action: onStartTTS)
            if isLocalFile {
                quickActionButton(title: "设置", systemImage: "slider.horizontal.3", action: onOpenMoreSettings)
            } else {
                quickActionButton(title: "换源", systemImage: "arrow.triangle.2.circlepath", action: onOpenChangeSource)
            }
        }
        .tint(.primary)
        .padding(.vertical, 4)
    }

    private func quickActionButton(
        title: String,
        systemImage: String,
        isActive: Bool = false,
        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity)
        }
    }
}
