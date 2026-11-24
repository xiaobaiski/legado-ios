import SwiftUI
import UIKit

/// 章节目录与书签抽屉组件（采用原生 UITableView 固定行高 O(1) 精准定位，打开瞬间居中聚焦当前阅读章节）
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
    @State private var scrollCommand: TocScrollCommand?
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

    private var displayedBookmarks: [Bookmark] {
        guard !searchText.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.chapterName.localizedCaseInsensitiveContains(searchText) ||
                $0.bookText.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText)
        }
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
                prompt: selectedTab == .toc ? "搜索章节名..." : "搜索书签与笔记...")
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
                TocChapterTableView(
                    chapters: displayedChapters,
                    currentChapterIndex: durChapterIndex,
                    scrollCommand: scrollCommand,
                    onSelectChapter: onSelectChapter)
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
                scrollCommand = TocScrollCommand(target: .currentChapter, animated: true)
            }

            toolbarPill(title: "顶", icon: "arrow.up.to.line") {
                scrollCommand = TocScrollCommand(target: .top, animated: true)
            }

            toolbarPill(title: "底", icon: "arrow.down.to.line") {
                scrollCommand = TocScrollCommand(target: .bottom, animated: true)
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

    @ViewBuilder
    private var bookmarkSection: some View {
        if bookmarks.isEmpty {
            ContentUnavailableView(
                "暂无书签",
                systemImage: "bookmark",
                description: Text("阅读时轻触右上角书签按钮或长按正文添加批注书签"))
        } else if displayedBookmarks.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List {
                ForEach(displayedBookmarks) { bookmark in
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

private struct TocScrollCommand: Equatable {
    enum Target: Equatable {
        case currentChapter
        case top
        case bottom
    }

    let id = UUID()
    let target: Target
    let animated: Bool
}

/// 原生 UIKit 目录列表（固定 48pt 行高 + viewDidLayoutSubviews 自动精准居中定位当前章节，彻底规避 SwiftUI List 跳回顶部问题）
private struct TocChapterTableView: UIViewControllerRepresentable {
    let chapters: [Chapter]
    let currentChapterIndex: Int
    let scrollCommand: TocScrollCommand?
    let onSelectChapter: (Chapter) -> Void

    func makeUIViewController(context _: Context) -> TocTableViewController {
        TocTableViewController(
            chapters: chapters,
            currentChapterIndex: currentChapterIndex,
            onSelectChapter: onSelectChapter)
    }

    func updateUIViewController(_ uiViewController: TocTableViewController, context _: Context) {
        uiViewController.applyUpdate(
            chapters: chapters,
            currentChapterIndex: currentChapterIndex,
            scrollCommand: scrollCommand,
            onSelectChapter: onSelectChapter)
    }
}

private final class TocTableViewController: UITableViewController {
    private static let cellReuseId = "TocChapterCell"

    private var chapters: [Chapter]
    private var currentChapterIndex: Int
    private var onSelectChapter: (Chapter) -> Void
    private var lastCommandId: UUID?
    private var didInitialScroll = false
    private var hasUserScrolled = false
    private var lastChapterSignature = ""

    init(
        chapters: [Chapter],
        currentChapterIndex: Int,
        onSelectChapter: @escaping (Chapter) -> Void) {
        self.chapters = chapters
        self.currentChapterIndex = currentChapterIndex
        self.onSelectChapter = onSelectChapter
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        tableView.backgroundColor = .clear
        tableView.rowHeight = 48
        tableView.estimatedRowHeight = 48
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.register(TocChapterCell.self, forCellReuseIdentifier: Self.cellReuseId)
        lastChapterSignature = makeSignature(chapters: chapters, currentIndex: currentChapterIndex)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didInitialScroll, tableView.bounds.height > 40, !chapters.isEmpty else { return }
        didInitialScroll = true
        scrollToTarget(.currentChapter, animated: false)
        // Sheet 弹出与 searchable 栏就位后二次居中校正，若用户未介入滑动则确保停在当前阅读章节
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hasUserScrolled else { return }
            self.scrollToTarget(.currentChapter, animated: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.hasUserScrolled else { return }
            self.scrollToTarget(.currentChapter, animated: false)
        }
    }

    override func scrollViewWillBeginDragging(_: UIScrollView) {
        hasUserScrolled = true
    }

    func applyUpdate(
        chapters: [Chapter],
        currentChapterIndex: Int,
        scrollCommand: TocScrollCommand?,
        onSelectChapter: @escaping (Chapter) -> Void) {
        self.onSelectChapter = onSelectChapter
        let signature = makeSignature(chapters: chapters, currentIndex: currentChapterIndex)
        let dataChanged = signature != lastChapterSignature
        self.chapters = chapters
        self.currentChapterIndex = currentChapterIndex

        if dataChanged {
            lastChapterSignature = signature
            tableView.reloadData()
            if !didInitialScroll && tableView.bounds.height > 40 {
                didInitialScroll = true
                scrollToTarget(.currentChapter, animated: false)
            }
        }

        if let command = scrollCommand, command.id != lastCommandId {
            lastCommandId = command.id
            hasUserScrolled = true
            scrollToTarget(command.target, animated: command.animated)
        }
    }

    private func makeSignature(chapters: [Chapter], currentIndex: Int) -> String {
        var hasher = Hasher()
        hasher.combine(chapters.count)
        hasher.combine(currentIndex)
        for chapter in chapters {
            hasher.combine(chapter.index)
            hasher.combine(chapter.title)
        }
        return "\(hasher.finalize())"
    }

    private func scrollToTarget(_ target: TocScrollCommand.Target, animated: Bool) {
        let total = tableView.numberOfRows(inSection: 0)
        guard total > 0 else { return }

        let targetRow: Int
        let position: UITableView.ScrollPosition
        switch target {
        case .currentChapter:
            guard let matchedRow = chapters.firstIndex(where: { $0.index == currentChapterIndex }) else {
                return
            }
            targetRow = matchedRow
            position = .middle

        case .top:
            targetRow = 0
            position = .top

        case .bottom:
            targetRow = total - 1
            position = .bottom
        }

        guard targetRow >= 0, targetRow < total else { return }
        tableView.scrollToRow(at: IndexPath(row: targetRow, section: 0), at: position, animated: animated)
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        chapters.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: Self.cellReuseId,
            for: indexPath) as? TocChapterCell else {
            return UITableViewCell()
        }
        let chapter = chapters[indexPath.row]
        let isCurrent = chapter.index == currentChapterIndex
        cell.configure(chapter: chapter, isCurrent: isCurrent)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < chapters.count else { return }
        onSelectChapter(chapters[indexPath.row])
    }
}

private final class TocChapterCell: UITableViewCell {
    private let indexLabel = UILabel()
    private let titleLabel = UILabel()
    private let badgeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        indexLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        indexLabel.setContentHuggingPriority(.required, for: .horizontal)
        indexLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        badgeLabel.text = "当前"
        badgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 9
        badgeLabel.layer.masksToBounds = true
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [indexLabel, titleLabel, badgeLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            indexLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38),
            badgeLabel.widthAnchor.constraint(equalToConstant: 40),
            badgeLabel.heightAnchor.constraint(equalToConstant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    func configure(chapter: Chapter, isCurrent: Bool) {
        indexLabel.text = "\(chapter.index + 1)."
        titleLabel.text = chapter.title
        if isCurrent {
            indexLabel.textColor = tintColor
            titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
            titleLabel.textColor = tintColor
            badgeLabel.isHidden = false
            badgeLabel.textColor = tintColor
            badgeLabel.backgroundColor = tintColor.withAlphaComponent(0.16)
            backgroundColor = tintColor.withAlphaComponent(0.10)
        } else {
            indexLabel.textColor = .secondaryLabel
            titleLabel.font = .systemFont(ofSize: 16, weight: .regular)
            titleLabel.textColor = .label
            badgeLabel.isHidden = true
            backgroundColor = .clear
        }
    }
}
