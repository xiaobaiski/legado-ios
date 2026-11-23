import SwiftUI

extension ReaderView {
    var tocPresentationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.state.isTocSheetVisible },
            set: {
                if !$0 {
                    tocSearchText = ""
                    viewModel.send(.closeToc)
                }
            })
    }

    var tocSheetView: some View {
        BookTocSheet(
            chapters: viewModel.state.chapters,
            durChapterIndex: viewModel.state.currentChapterIndex,
            isReverse: isTocReversed,
            searchText: tocSearchText,
            bookmarks: viewModel.state.bookmarks,
            onToggleReverse: { isTocReversed.toggle() },
            onSearchChange: { tocSearchText = $0 },
            onSelectChapter: { chapter in
                viewModel.send(.closeToc)
                viewModel.send(.loadChapter(chapter.index))
            },
            onSelectBookmark: { bookmark in
                viewModel.send(.closeToc)
                viewModel.send(.jumpToChapterAndOffset(
                    chapterIndex: bookmark.chapterIndex,
                    matchOffset: bookmark.chapterPos))
            },
            onDeleteBookmark: { viewModel.send(.deleteBookmark(id: $0.id)) })
            .preferredColorScheme(readerColorScheme)
    }

    @ViewBuilder var toastOverlayView: some View {
        if let toast = toastMessage {
            Text(toast)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
                .task(id: toast) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if toastMessage == toast {
                        toastMessage = nil
                    }
                }
        }
    }

    func hudOverlay(safeAreaTop: CGFloat) -> some View {
        ReaderHUDView(
            bookTitle: viewModel.state.book.name,
            currentChapterTitle: viewModel.state.currentChapter?.title ?? "",
            currentChapterIndex: viewModel.state.currentChapterIndex,
            totalChapters: viewModel.state.chapters.count,
            currentPageIndex: viewModel.state.currentPageIndex,
            totalPages: viewModel.state.pages.count,
            chapters: viewModel.state.chapters,
            config: viewModel.state.config,
            importedFonts: viewModel.state.importedFonts,
            safeAreaTop: safeAreaTop,
            isConfigOpen: viewModel.state.isConfigSheetVisible,
            isAutoPaging: viewModel.state.isAutoPaging,
            onBack: { dismiss() },
            onPreviousChapter: { viewModel.send(.loadChapter(viewModel.state.currentChapterIndex - 1)) },
            onNextChapter: { viewModel.send(.loadChapter(viewModel.state.currentChapterIndex + 1)) },
            onSliderChange: { viewModel.send(.loadChapter(Int($0))) },
            onPageSliderChange: { viewModel.send(.jumpToPage($0)) },
            onOpenToc: {
                tocSearchText = ""
                viewModel.send(.openToc)
            },
            onToggleConfig: {
                viewModel.send(viewModel.state.isConfigSheetVisible ? .closeConfig : .openConfig)
            },
            onUpdateConfig: { viewModel.send(.updateConfig($0)) },
            onSelectCustomFont: { viewModel.send(.selectCustomFont($0)) },
            onOpenFontImporter: { isFontChooserPresented = true },
            onToggleNightMode: {
                var updated = viewModel.state.config
                updated.toggleNightMode()
                viewModel.send(.updateConfig(updated))
            },
            onOpenTextAction: {
                viewModel.send(.hideHUD)
                isTextActionPresented = true
            },
            onResetConfig: { viewModel.send(.resetConfig) },
            onOpenMoreSettings: { viewModel.send(.openMoreSettings) },
            onToggleAutoPage: { viewModel.send(.toggleAutoPage) },
            onOpenSearch: { openSearchContentSheet() },
            isBookmarked: viewModel.state.isCurrentPageBookmarked,
            onToggleBookmark: { viewModel.send(.toggleBookmark) })
    }
}
