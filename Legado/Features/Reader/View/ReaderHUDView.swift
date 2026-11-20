import SwiftUI

/// 阅读器液态玻璃控制面板 (HUD Overlay)
public struct ReaderHUDView: View {
    let bookTitle: String
    let currentChapterTitle: String
    let currentChapterIndex: Int
    let totalChapters: Int
    let config: ReaderConfig
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
        config: ReaderConfig,
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
        self.config = config
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
                        isAutoPaging: isAutoPaging,
                        onUpdateConfig: onUpdateConfig,
                        onResetConfig: onResetConfig,
                        onOpenMoreSettings: onOpenMoreSettings,
                        onToggleAutoPage: onToggleAutoPage)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                bottomControlBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - 顶部导航条

    private var topBar: some View {
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
        .padding(.horizontal, 16)
        .padding(.top, 54)
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onPreviousChapter) {
                    Image(systemName: "backward.fill")
                        .font(.caption)
                }
                .disabled(currentChapterIndex <= 0)

                Slider(
                    value: Binding(
                        get: { Double(currentChapterIndex) },
                        set: { onSliderChange($0) }),
                    in: 0 ... Double(max(totalChapters - 1, 1)),
                    step: 1)
                    .tint(.accentColor)

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
