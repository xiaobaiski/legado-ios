import SwiftUI

/// 章节目录与书签抽屉组件 (精准自动聚焦当前章节 + 定位/顶底/正倒序快捷工具栏)
public struct BookTocSheet: View {
    public enum Tab: String, CaseIterable, Identifiable {
        case toc = "目录"
        case bookmark = "书签"

        public var id: String {
            rawValue
        }
    }

    let chapters: [Chapter]
    let durChapterIndex: Int
    let isReverse: Bool
    let searchText: String
    let bookmarks: [Bookmark]
    let onToggleReverse: () -> Void
    let onSearchChange: (String) -> Void
    let onSelectChapter: (Chapter) -> Void
    let onSelectBookmark: (Bookmark) -> Void
    let onDeleteBookmark: (Bookmark) -> Void

    @State private var selectedTab: Tab = .toc
    @State private var scrollRequestID = UUID()
    @State private var scrollTargetIndex: Int?
    @Environment(\.dismiss) private var dismiss

    public init(
        chapters: [Chapter],
        durChapterIndex: Int,
        isReverse: Bool,
        searchText: String,
        bookmarks: [Bookmark] = [],
        onToggleReverse: @escaping () -> Void,
        onSearchChange: @escaping (String) -> Void,
        onSelectChapter: @escaping (Chapter) -> Void,
        onSelectBookmark: @escaping (Bookmark) -> Void = { _ in },
        onDeleteBookmark: @escaping (Bookmark) -> Void = { _ in }) {
        self.chapters = chapters
        self.durChapterIndex = durChapterIndex
        self.isReverse = isReverse
        self.searchText = searchText
        self.bookmarks = bookmarks
        self.onToggleReverse = onToggleReverse
        self.onSearchChange = onSearchChange
        self.onSelectChapter = onSelectChapter
        self.onSelectBookmark = onSelectBookmark
        self.onDeleteBookmark = onDeleteBookmark
    }

    private var displayedChapters: [Chapter] {
        if !isReverse && searchText.isEmpty {
            return chapters
        }
        var list = isReverse ? Array(chapters.reversed()) : chapters
        if !searchText.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSegmentedControl
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if selectedTab == .toc {
                    tocSection
                } else {
                    bookmarkSection
                }
            }
            .navigationTitle(selectedTab == .toc ? "目录" : "书签")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: Binding(
                    get: { searchText },
                    set: { onSearchChange($0) }),
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "搜索章节名...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.fraction(0.55), .medium, .large])
    }

    private var tabSegmentedControl: some View {
        Picker("视图", selection: $selectedTab) {
            ForEach(Tab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var tocSection: some View {
        VStack(spacing: 0) {
            tocToolbar
            Divider()

            if displayedChapters.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                tocList
            }
        }
    }

    private var tocToolbar: some View {
        HStack(spacing: 8) {
            Text("共 \(chapters.count) 章")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            toolbarPill(title: "定位", icon: "scope") {
                scrollTargetIndex = durChapterIndex
                scrollRequestID = UUID()
            }

            toolbarPill(title: "顶", icon: "arrow.up.to.line") {
                if let first = displayedChapters.first {
                    scrollTargetIndex = first.index
                    scrollRequestID = UUID()
                }
            }

            toolbarPill(title: "底", icon: "arrow.down.to.line") {
                if let last = displayedChapters.last {
                    scrollTargetIndex = last.index
                    scrollRequestID = UUID()
                }
            }

            toolbarPill(title: isReverse ? "倒序" : "正序", icon: "arrow.up.arrow.down") {
                onToggleReverse()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func toolbarPill(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
        .tint(.primary)
    }

    private var tocList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(displayedChapters, id: \.index) { chapter in
                    chapterRow(chapter)
                        .id(chapter.index)
                        .listRowBackground(
                            chapter.index == durChapterIndex
                                ? Color.accentColor.opacity(0.10)
                                : Color.clear)
                }
            }
            .listStyle(.plain)
            .task(id: selectedTab) {
                guard selectedTab == .toc else { return }
                await scrollToChapter(durChapterIndex, with: proxy, animated: false)
            }
            .onChange(of: scrollRequestID) { _, _ in
                guard let target = scrollTargetIndex else { return }
                Task { @MainActor in
                    await scrollToChapter(target, with: proxy, animated: true)
                }
            }
        }
    }

    @MainActor
    private func scrollToChapter(
        _ index: Int,
        with proxy: ScrollViewProxy,
        animated: Bool) async {
        guard displayedChapters.contains(where: { $0.index == index }) else { return }
        // 等待 Sheet 内的 List 完成首帧行布局后再滚动，确保长目录也能精准定位到当前章节
        await Task.yield()
        try? await Task.sleep(nanoseconds: animated ? 10_000_000 : 60_000_000)
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(index, anchor: .center)
            }
        } else {
            proxy.scrollTo(index, anchor: .center)
        }
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let isCurrent = chapter.index == durChapterIndex
        return Button {
            onSelectChapter(chapter)
        } label: {
            HStack(spacing: 10) {
                Text("\(chapter.index + 1).")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                    .frame(width: 40, alignment: .leading)

                Text(chapter.title)
                    .font(isCurrent ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                Spacer()

                if isCurrent {
                    Text("当前")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.16))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule(style: .continuous))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var bookmarkSection: some View {
        if bookmarks.isEmpty {
            ContentUnavailableView(
                "暂无书签",
                systemImage: "bookmark",
                description: Text("阅读时轻触右上角书签按钮或长按正文添加批注书签"))
        } else {
            List {
                ForEach(bookmarks) { bookmark in
                    bookmarkRow(bookmark)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDeleteBookmark(bookmark)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
        }
    }

    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        Button {
            onSelectBookmark(bookmark)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(bookmark.chapterName)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)

                    Spacer()

                    Text(bookmark.formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(bookmark.bookText)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !bookmark.content.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(bookmark.content)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
