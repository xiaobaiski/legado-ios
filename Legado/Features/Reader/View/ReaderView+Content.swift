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
            case .curl:
                curlContent(width: width)

            case .cover, .none:
                pagedContent(width: width, animated: viewModel.state.config.pageTurnMode == .cover)

            case .slide:
                slideContent(width: width)

            case .scroll:
                scrollContent
            }
        }
    }

    func curlContent(width: CGFloat) -> some View {
        let config = viewModel.state.config
        let isDual = config.isDualPageActive(for: viewModel.state.screenBounds)
        let maxSingleWidth: CGFloat? = width >= 760 ? 680 : nil

        return PageCurlReaderView(
            pages: viewModel.state.pages,
            currentPageIndex: viewModel.state.currentPageIndex,
            chapterIndex: viewModel.state.currentChapterIndex,
            totalChapters: viewModel.state.chapters.count,
            config: config,
            highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil,
            isDualPage: isDual,
            maxSingleWidth: maxSingleWidth,
            onPageChanged: { newIndex in
                viewModel.send(.jumpToPage(newIndex))
            },
            onRequestNextChapter: {
                viewModel.send(.loadChapter(viewModel.state.currentChapterIndex + 1))
            },
            onRequestPrevChapter: {
                viewModel.send(.prevPage)
            },
            onTapLocation: { xRatio, yRatio in
                handleTapAt(xRatio: xRatio, yRatio: yRatio)
            })
            .id("curl_\(isDual ? 2 : 1)")
            .ignoresSafeArea()
    }

    func pagedContent(width: CGFloat, animated: Bool) -> some View {
        let isDual = viewModel.state.config.isDualPageActive(for: viewModel.state.screenBounds)
        let maxSingleWidth: CGFloat? = width >= 760 ? 680 : nil
        let alignedLeftIndex = isDual
            ? (viewModel.state.currentPageIndex - viewModel.state.currentPageIndex % 2)
            : viewModel.state.currentPageIndex

        return ZStack {
            if isDual, alignedLeftIndex >= 0, alignedLeftIndex < viewModel.state.pages.count {
                let leftPage = viewModel.state.pages[alignedLeftIndex]
                let rightPage = alignedLeftIndex + 1 < viewModel.state.pages.count
                    ? viewModel.state.pages[alignedLeftIndex + 1]
                    : nil
                ReaderDualPageSpreadView(
                    leftPage: leftPage,
                    rightPage: rightPage,
                    totalPages: viewModel.state.pages.count,
                    totalChapters: viewModel.state.chapters.count,
                    config: viewModel.state.config,
                    highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil)
                    .id("dual_\(leftPage.chapterIndex)_\(leftPage.pageIndex)")
                    .transition(animated ? .opacity : .identity)
            } else if let page = viewModel.state.currentPage {
                ReaderPageView(
                    page: page,
                    totalPages: viewModel.state.pages.count,
                    totalChapters: viewModel.state.chapters.count,
                    config: viewModel.state.config,
                    highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil,
                    maxContentWidth: maxSingleWidth)
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
        let isDual = viewModel.state.config.isDualPageActive(for: viewModel.state.screenBounds)
        let maxSingleWidth: CGFloat? = width >= 760 ? 680 : nil
        let spreadIndices = stride(from: 0, to: viewModel.state.pages.count, by: 2).map { $0 }

        return ZStack {
            if isDual {
                TabView(selection: Binding(
                    get: { viewModel.state.currentPageIndex - viewModel.state.currentPageIndex % 2 },
                    set: { viewModel.send(.jumpToPage($0)) })) {
                        ForEach(spreadIndices, id: \.self) { leftIdx in
                            let leftPage = viewModel.state.pages[leftIdx]
                            let rightPage = leftIdx + 1 < viewModel.state.pages.count
                                ? viewModel.state.pages[leftIdx + 1]
                                : nil
                            ReaderDualPageSpreadView(
                                leftPage: leftPage,
                                rightPage: rightPage,
                                totalPages: viewModel.state.pages.count,
                                totalChapters: viewModel.state.chapters.count,
                                config: viewModel.state.config,
                                highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil)
                                .tag(leftIdx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                TabView(selection: Binding(
                    get: { viewModel.state.currentPageIndex },
                    set: { viewModel.send(.jumpToPage($0)) })) {
                        ForEach(viewModel.state.pages) { page in
                            ReaderPageView(
                                page: page,
                                totalPages: viewModel.state.pages.count,
                                totalChapters: viewModel.state.chapters.count,
                                config: viewModel.state.config,
                                highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil,
                                maxContentWidth: maxSingleWidth)
                                .tag(page.pageIndex)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
            }

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
        let maxWidth: CGFloat? = viewModel.state.screenBounds.width >= 760 ? 700 : nil

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: config.paragraphSpacing) {
                if let chapter = viewModel.state.currentChapter {
                    Text(config.chineseConversion.convert(chapter.title))
                        .font(config.resolvedSwiftUIFont(size: config.fontSize + 4, isBold: true))
                        .foregroundStyle(config.theme.textColor)
                        .padding(.bottom, 8)
                }

                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(renderedScrollText(paragraph))
                        .font(config.resolvedSwiftUIFont())
                        .tracking(config.letterSpacing)
                        .lineSpacing(config.lineSpacing)
                        .foregroundStyle(config.theme.textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                scrollChapterFooter
                    .padding(.top, 24)
            }
            .frame(maxWidth: maxWidth ?? .infinity)
            .frame(maxWidth: .infinity)
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
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            let safeWidth = max(geo.size.width, width, 1)
                            let safeHeight = max(geo.size.height, 1)
                            let xRatio = min(max(value.location.x / safeWidth, 0), 1)
                            let yRatio = min(max(value.location.y / safeHeight, 0), 1)
                            handleTapAt(xRatio: xRatio, yRatio: yRatio)
                        })
        }
    }

    func handleTapAt(xRatio: CGFloat, yRatio: CGFloat) {
        if viewModel.state.isHUDVisible {
            viewModel.send(.hideHUD)
            return
        }

        let config = viewModel.state.config
        var action = config.tapZoneConfig.action(atXRatio: xRatio, yRatio: yRatio)

        // 保底安全机制：若用户把九宫格全部设为非菜单动作，点击正中仍可呼出菜单避免卡死
        if !config.tapZoneConfig.hasMenuZone,
           xRatio >= 1.0 / 3.0, xRatio <= 2.0 / 3.0,
           yRatio >= 1.0 / 3.0, yRatio <= 2.0 / 3.0 {
            action = .toggleHUD
        }

        if !config.tapToTurnPage && action != .toggleHUD {
            return
        }

        switch action {
        case .nextPage:
            viewModel.send(.nextPage)

        case .prevPage:
            viewModel.send(.prevPage)

        case .toggleHUD:
            viewModel.send(.toggleHUD)

        case .nextChapter:
            viewModel.send(.loadChapter(viewModel.state.currentChapterIndex + 1))

        case .prevChapter:
            viewModel.send(.loadChapter(viewModel.state.currentChapterIndex - 1))

        case .toggleNightMode:
            var updated = config
            updated.toggleNightMode()
            viewModel.send(.updateConfig(updated))

        case .none:
            break
        }
    }
}
