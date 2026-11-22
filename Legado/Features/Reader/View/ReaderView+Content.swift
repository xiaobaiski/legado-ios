import SwiftUI

// MARK: - ReaderView 内容排版与手势图层扩展

extension ReaderView {
    @ViewBuilder
    func contentLayer(width: CGFloat) -> some View {
        if viewModel.state.isLoading {
            ProgressView("正在排版正文...")
                .tint(viewModel.state.config.effectiveTextColor)
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
        } else if viewModel.state.isAutoPaging && viewModel.state.config.autoPageMode == .smoothScroll {
            smoothScrollContent(autoScroll: true)
        } else {
            switch viewModel.state.config.pageTurnMode {
            case .curl:
                curlContent(width: width)

            case .cover, .none:
                pagedContent(width: width, animated: viewModel.state.config.pageTurnMode == .cover)

            case .slide:
                slideContent(width: width)

            case .scroll:
                smoothScrollContent(autoScroll: viewModel.state.isAutoPaging)
            }
        }
    }

    func smoothScrollContent(autoScroll: Bool) -> some View {
        let config = viewModel.state.config
        let isPaused = viewModel.state.isHUDVisible
            || viewModel.state.isMoreSettingsVisible
            || viewModel.state.isTocSheetVisible
            || isTTSSpeaking
        let chapterTitle = viewModel.state.currentChapter?.title ?? ""

        return ZStack(alignment: .bottom) {
            AutoScrollReaderView(
                chapterIndex: viewModel.state.currentChapterIndex,
                chapterTitle: chapterTitle,
                contentText: viewModel.state.currentChapterText,
                titlePrefixLength: viewModel.state.pages.first?.titlePrefixLength ?? 0,
                config: config,
                highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil,
                isAutoScrolling: autoScroll,
                isPaused: isPaused,
                onTapCenter: {
                    viewModel.send(.toggleHUD)
                },
                onReachedBottom: {
                    if viewModel.state.currentChapterIndex + 1 < viewModel.state.chapters.count {
                        viewModel.send(.loadChapter(viewModel.state.currentChapterIndex + 1))
                    } else if viewModel.state.isAutoPaging {
                        viewModel.send(.toggleAutoPage)
                    }
                })
                .ignoresSafeArea()
        }
    }

    func curlContent(width: CGFloat) -> some View {
        let config = viewModel.state.config
        let isDual = config.isDualPageActive(for: viewModel.state.screenBounds)

        return PageCurlReaderView(
            bookTitle: viewModel.state.book.name,
            pages: viewModel.state.pages,
            currentPageIndex: viewModel.state.currentPageIndex,
            chapterIndex: viewModel.state.currentChapterIndex,
            totalChapters: viewModel.state.chapters.count,
            config: config,
            highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil,
            isDualPage: isDual,
            maxSingleWidth: nil,
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
                    bookTitle: viewModel.state.book.name,
                    totalPages: viewModel.state.pages.count,
                    totalChapters: viewModel.state.chapters.count,
                    config: viewModel.state.config,
                    highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil)
                    .id("dual_\(leftPage.chapterIndex)_\(leftPage.pageIndex)")
                    .transition(animated ? .opacity : .identity)
            } else if let page = viewModel.state.currentPage {
                ReaderPageView(
                    page: page,
                    bookTitle: viewModel.state.book.name,
                    totalPages: viewModel.state.pages.count,
                    totalChapters: viewModel.state.chapters.count,
                    config: viewModel.state.config,
                    highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil,
                    maxContentWidth: nil)
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
                                bookTitle: viewModel.state.book.name,
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
                                bookTitle: viewModel.state.book.name,
                                totalPages: viewModel.state.pages.count,
                                totalChapters: viewModel.state.chapters.count,
                                config: viewModel.state.config,
                                highlightedSentence: ttsPlayer.state != .idle ? ttsPlayer.currentSentence : nil,
                                maxContentWidth: nil)
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
                .onLongPressGesture(minimumDuration: 0.55) {
                    if !viewModel.state.isHUDVisible {
                        isTextActionPresented = true
                    }
                }
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
            if viewModel.state.currentChapterIndex + 1 < viewModel.state.chapters.count {
                viewModel.send(.loadChapter(viewModel.state.currentChapterIndex + 1))
            } else {
                toastMessage = "已经是最后一章了"
            }

        case .prevChapter:
            if viewModel.state.currentChapterIndex > 0 {
                viewModel.send(.loadChapter(viewModel.state.currentChapterIndex - 1))
            } else {
                toastMessage = "已经是第一章了"
            }

        case .toggleNightMode:
            var updated = config
            updated.toggleNightMode()
            viewModel.send(.updateConfig(updated))

        case .none:
            break
        }
    }
}
