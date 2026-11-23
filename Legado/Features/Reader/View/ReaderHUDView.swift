import SwiftUI

/// 阅读器液态玻璃控制面板 (HUD Overlay)
public struct ReaderHUDView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var draggingChapterIndex: Double?

    let bookTitle: String
    let currentChapterTitle: String
    let currentChapterIndex: Int
    let totalChapters: Int
    let currentPageIndex: Int
    let totalPages: Int
    let chapters: [Chapter]
    let config: ReaderConfig
    let importedFonts: [ImportedFont]
    let safeAreaTop: CGFloat
    let isConfigOpen: Bool
    let isAutoPaging: Bool
    let onBack: () -> Void
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onSliderChange: (Double) -> Void
    let onPageSliderChange: (Int) -> Void
    let onOpenToc: () -> Void
    let onToggleConfig: () -> Void
    let onUpdateConfig: (ReaderConfig) -> Void
    let onSelectCustomFont: (ImportedFont) -> Void
    let onOpenFontImporter: () -> Void
    let onToggleNightMode: () -> Void
    let onOpenTextAction: () -> Void
    let onResetConfig: () -> Void
    let onOpenMoreSettings: () -> Void
    let onToggleAutoPage: () -> Void
    let onOpenSearch: () -> Void
    let isBookmarked: Bool
    let onToggleBookmark: () -> Void

    public init(
        bookTitle: String,
        currentChapterTitle: String,
        currentChapterIndex: Int,
        totalChapters: Int,
        currentPageIndex: Int = 0,
        totalPages: Int = 1,
        chapters: [Chapter] = [],
        config: ReaderConfig,
        importedFonts: [ImportedFont] = [],
        safeAreaTop: CGFloat = 48,
        isConfigOpen: Bool,
        isAutoPaging: Bool = false,
        onBack: @escaping () -> Void,
        onPreviousChapter: @escaping () -> Void,
        onNextChapter: @escaping () -> Void,
        onSliderChange: @escaping (Double) -> Void,
        onPageSliderChange: @escaping (Int) -> Void = { _ in },
        onOpenToc: @escaping () -> Void,
        onToggleConfig: @escaping () -> Void,
        onUpdateConfig: @escaping (ReaderConfig) -> Void = { _ in },
        onSelectCustomFont: @escaping (ImportedFont) -> Void = { _ in },
        onOpenFontImporter: @escaping () -> Void = {},
        onToggleNightMode: @escaping () -> Void = {},
        onOpenTextAction: @escaping () -> Void = {},
        onResetConfig: @escaping () -> Void = {},
        onOpenMoreSettings: @escaping () -> Void = {},
        onToggleAutoPage: @escaping () -> Void = {},
        onOpenSearch: @escaping () -> Void = {},
        isBookmarked: Bool = false,
        onToggleBookmark: @escaping () -> Void = {}) {
        self.bookTitle = bookTitle
        self.currentChapterTitle = currentChapterTitle
        self.currentChapterIndex = currentChapterIndex
        self.totalChapters = totalChapters
        self.currentPageIndex = currentPageIndex
        self.totalPages = totalPages
        self.chapters = chapters
        self.config = config
        self.importedFonts = importedFonts
        self.safeAreaTop = safeAreaTop
        self.isConfigOpen = isConfigOpen
        self.isAutoPaging = isAutoPaging
        self.onBack = onBack
        self.onPreviousChapter = onPreviousChapter
        self.onNextChapter = onNextChapter
        self.onSliderChange = onSliderChange
        self.onPageSliderChange = onPageSliderChange
        self.onOpenToc = onOpenToc
        self.onToggleConfig = onToggleConfig
        self.onUpdateConfig = onUpdateConfig
        self.onSelectCustomFont = onSelectCustomFont
        self.onOpenFontImporter = onOpenFontImporter
        self.onToggleNightMode = onToggleNightMode
        self.onOpenTextAction = onOpenTextAction
        self.onResetConfig = onResetConfig
        self.onOpenMoreSettings = onOpenMoreSettings
        self.onToggleAutoPage = onToggleAutoPage
        self.onOpenSearch = onOpenSearch
        self.isBookmarked = isBookmarked
        self.onToggleBookmark = onToggleBookmark
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
        .preferredColorScheme(config.isEffectiveDark ? .dark : .light)
        .onChange(of: currentChapterIndex) { _, _ in
            draggingChapterIndex = nil
        }
        .onChange(of: config.progressBarBehavior) { _, _ in
            draggingChapterIndex = nil
        }
    }
}

// MARK: - HUD 子视图扩展

private extension ReaderHUDView {
    var topBar: some View {
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

                Spacer(minLength: 8)

                circleIconButton(systemName: "magnifyingglass", action: onOpenSearch)
                    .accessibilityLabel("搜索")

                circleIconButton(
                    systemName: isBookmarked ? "bookmark.fill" : "bookmark",
                    foreground: isBookmarked ? Color.accentColor : .primary,
                    action: onToggleBookmark)

                if horizontalSizeClass == .regular {
                    circleIconButton(systemName: "text.quote", action: onOpenTextAction)
                    circleIconButton(systemName: "gearshape", action: onOpenMoreSettings)
                }

                moreMenuButton
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

    var moreMenuButton: some View {
        Menu {
            Button(action: onOpenTextAction) {
                Label("正文摘录与净化", systemImage: "text.quote")
            }

            Button(action: onToggleAutoPage) {
                Label(
                    isAutoPaging ? "停止自动翻页" : "开启自动翻页",
                    systemImage: isAutoPaging ? "pause.circle.fill" : "play.circle")
            }

            Button(action: onOpenMoreSettings) {
                Label("更多阅读设置", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
        }
    }

    func circleIconButton(
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

    var bottomControlBar: some View {
        let isPageMode = config.progressBarBehavior == .page && totalPages > 1
        let itemTotal = isPageMode ? totalPages : totalChapters
        let currentItem = isPageMode ? currentPageIndex : currentChapterIndex
        let maxIndex = max(itemTotal - 1, 1)
        let activeIndex = Int(draggingChapterIndex ?? Double(currentItem))
        let clampedIndex = min(max(activeIndex, 0), max(itemTotal - 1, 0))
        let previewTitle = isPageMode
            ? "\(currentChapterTitle) · 第 \(clampedIndex + 1) 页"
            : (clampedIndex < chapters.count ? chapters[clampedIndex].title : currentChapterTitle)
        let progressPct = itemTotal > 1
            ? Double(clampedIndex) / Double(itemTotal - 1) * 100.0
            : 100.0
        let isScrubbing = draggingChapterIndex != nil

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(previewTitle)
                    .font(.caption.weight(isScrubbing ? .semibold : .medium))
                    .foregroundStyle(isScrubbing ? Color.accentColor : .primary)
                    .lineLimit(1)
                Spacer()
                Text("\(clampedIndex + 1)/\(max(itemTotal, 1)) · \(String(format: "%.1f%%", progressPct))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isScrubbing ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isScrubbing ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
            .clipShape(Capsule(style: .continuous))

            HStack(spacing: 12) {
                Button(action: onPreviousChapter) {
                    Image(systemName: "backward.fill")
                        .font(.caption)
                }
                .disabled(currentChapterIndex <= 0)

                Slider(
                    value: Binding(
                        get: { draggingChapterIndex ?? Double(currentItem) },
                        set: { newValue in
                            draggingChapterIndex = newValue
                        }),
                    in: 0 ... Double(maxIndex),
                    step: 1,
                    onEditingChanged: { isEditing in
                        if !isEditing, let target = draggingChapterIndex {
                            let targetInt = min(max(Int(target.rounded()), 0), max(itemTotal - 1, 0))
                            draggingChapterIndex = nil
                            if isPageMode {
                                if targetInt != currentPageIndex {
                                    onPageSliderChange(targetInt)
                                }
                            } else if targetInt != currentChapterIndex {
                                onSliderChange(Double(targetInt))
                            }
                        }
                    })
                    .tint(.accentColor)
                    .disabled(itemTotal <= 1)

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

    var quickActionsBar: some View {
        HStack {
            quickActionButton(title: "目录", systemImage: "list.bullet", action: onOpenToc)
            quickActionButton(
                title: "排版",
                systemImage: "textformat.size",
                isActive: isConfigOpen,
                action: onToggleConfig)
            quickActionButton(
                title: config.isEffectiveDark ? "日间" : "夜间",
                systemImage: config.isEffectiveDark ? "sun.max.fill" : "moon.fill",
                isActive: config.isEffectiveDark,
                action: onToggleNightMode)
            quickActionButton(title: "设置", systemImage: "slider.horizontal.3", action: onOpenMoreSettings)
        }
        .tint(.primary)
        .padding(.vertical, 4)
    }

    func quickActionButton(
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
