import SwiftUI

// MARK: - ReaderView 内容排版与手势图层扩展

extension ReaderView {
    @ViewBuilder
    func contentLayer(width: CGFloat) -> some View {
        if viewModel.state.isLoading {
            ProgressView("正在排版正文...")
                .tint(viewModel.state.config.theme.textColor)
        } else if viewModel.state.pages.isEmpty {
            ContentUnavailableView(
                "章节内容加载失败",
                systemImage: "book.pages",
                description: Text("轻触屏幕中央呼出控制栏"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.send(.toggleHUD)
                }
        } else {
            switch viewModel.state.config.pageTurnMode {
            case .cover, .none:
                pagedContent(width: width, animated: viewModel.state.config.pageTurnMode == .cover)

            case .slide:
                slideContent(width: width)

            case .scroll:
                scrollContent
            }
        }
    }

    func pagedContent(width: CGFloat, animated: Bool) -> some View {
        ZStack {
            if let page = viewModel.state.currentPage {
                ReaderPageView(
                    page: page,
                    totalPages: viewModel.state.pages.count,
                    totalChapters: viewModel.state.chapters.count,
                    config: viewModel.state.config,
                    highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil)
                    .id("\(page.chapterIndex)_\(page.pageIndex)")
                    .transition(animated ? .opacity : .identity)
            }
            tapGestureOverlay(width: width)
        }
        .animation(animated ? .easeOut(duration: 0.16) : nil, value: viewModel.state.currentPageIndex)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontalDelta = value.translation.width
                    let verticalDelta = value.translation.height
                    guard abs(horizontalDelta) > abs(verticalDelta), abs(horizontalDelta) > 36 else { return }
                    if viewModel.state.isHUDVisible {
                        viewModel.send(.hideHUD)
                        return
                    }
                    if horizontalDelta < 0 {
                        viewModel.send(.nextPage)
                    } else {
                        viewModel.send(.prevPage)
                    }
                })
    }

    func slideContent(width: CGFloat) -> some View {
        ZStack {
            TabView(selection: Binding(
                get: { viewModel.state.currentPageIndex },
                set: { viewModel.send(.jumpToPage($0)) })) {
                    ForEach(viewModel.state.pages) { page in
                        ReaderPageView(
                            page: page,
                            totalPages: viewModel.state.pages.count,
                            totalChapters: viewModel.state.chapters.count,
                            config: viewModel.state.config,
                            highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil)
                            .tag(page.pageIndex)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

            Color.clear
                .frame(width: width * 0.4)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.send(.toggleHUD)
                }
        }
    }

    var scrollContent: some View {
        let config = viewModel.state.config
        let paragraphs = viewModel.state.currentChapterText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: config.paragraphSpacing) {
                if let chapter = viewModel.state.currentChapter {
                    Text(config.chineseConversion.convert(chapter.title))
                        .font(config.fontFamily.swiftUIFont(size: config.fontSize + 4, isBold: true))
                        .foregroundStyle(config.theme.textColor)
                        .padding(.bottom, 8)
                }

                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(renderedScrollText(paragraph))
                        .font(config.fontFamily.swiftUIFont(size: config.fontSize, isBold: config.isBoldFont))
                        .tracking(config.letterSpacing)
                        .lineSpacing(config.lineSpacing)
                        .foregroundStyle(config.theme.textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                scrollChapterFooter
                    .padding(.top, 24)
            }
            .padding(.horizontal, config.horizontalMargin)
            .padding(.top, config.topMargin)
            .padding(.bottom, config.bottomMargin + 28)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.send(.toggleHUD)
        }
    }

    private var scrollChapterFooter: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.send(.loadChapter(viewModel.state.currentChapterIndex - 1))
            } label: {
                Label("上一章", systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(viewModel.state.currentChapterIndex <= 0)

            Button {
                viewModel.send(.loadChapter(viewModel.state.currentChapterIndex + 1))
            } label: {
                HStack(spacing: 4) {
                    Text("下一章")
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(viewModel.state.currentChapterIndex + 1 >= viewModel.state.chapters.count)
        }
        .foregroundStyle(viewModel.state.config.theme.textColor)
    }

    private func renderedScrollText(_ content: String) -> AttributedString {
        var attr = AttributedString(content)
        if ttsPlayer.state != .idle, !ttsPlayer.currentSentence.isEmpty,
           let range = attr.range(of: ttsPlayer.currentSentence) {
            attr[range].backgroundColor = Color.accentColor.opacity(0.18)
            attr[range].foregroundColor = .accentColor
        }
        return attr
    }

    func tapGestureOverlay(width: CGFloat) -> some View {
        let config = viewModel.state.config
        let leftIsNext = config.leftHandMode

        return HStack(spacing: 0) {
            // 左侧 30% 热区
            Color.clear
                .contentShape(Rectangle())
                .frame(width: width * 0.3)
                .onTapGesture {
                    if viewModel.state.isHUDVisible {
                        viewModel.send(.hideHUD)
                    } else if config.tapToTurnPage {
                        viewModel.send(leftIsNext ? .nextPage : .prevPage)
                    }
                }

            // 中间 40% 热区 (呼出/隐藏 HUD)
            Color.clear
                .contentShape(Rectangle())
                .frame(width: width * 0.4)
                .onTapGesture {
                    viewModel.send(.toggleHUD)
                }

            // 右侧 30% 热区
            Color.clear
                .contentShape(Rectangle())
                .frame(width: width * 0.3)
                .onTapGesture {
                    if viewModel.state.isHUDVisible {
                        viewModel.send(.hideHUD)
                    } else if config.tapToTurnPage {
                        viewModel.send(leftIsNext ? .prevPage : .nextPage)
                    }
                }
        }
    }
}
