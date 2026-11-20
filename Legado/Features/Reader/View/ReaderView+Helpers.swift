import SwiftUI
import UIKit

// MARK: - ReaderView 辅助悬浮栏、键盘快捷键与系统亮度/缓存控制扩展

extension ReaderView {
    var autoPageFloatingBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("自动翻页 \(Int(viewModel.state.config.autoPageIntervalSeconds))秒")
                    .font(.caption.weight(.medium).monospacedDigit())

                Button {
                    viewModel.send(.setAutoPageInterval(viewModel.state.config.autoPageIntervalSeconds - 1))
                } label: {
                    Image(systemName: "minus.circle")
                }

                Button {
                    viewModel.send(.setAutoPageInterval(viewModel.state.config.autoPageIntervalSeconds + 1))
                } label: {
                    Image(systemName: "plus.circle")
                }

                Button("停止") {
                    viewModel.send(.toggleAutoPage)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .padding(.bottom, 22)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    func handleHardwareKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .leftArrow, .upArrow:
            viewModel.send(.prevPage)
            return .handled

        case .rightArrow, .downArrow, .space:
            viewModel.send(.nextPage)
            return .handled

        case .escape:
            viewModel.send(.toggleHUD)
            return .handled

        default:
            return .ignored
        }
    }

    func updateVolumeButtonBinding() {
        let shouldEnable = viewModel.state.config.volumeKeyPageTurn && !isTTSSpeaking
        if shouldEnable {
            volumeHandler.start(
                onVolumeUp: { viewModel.send(.prevPage) },
                onVolumeDown: { viewModel.send(.nextPage) })
        } else {
            volumeHandler.stop()
        }
    }

    func applySystemDisplaySettings() {
        let config = viewModel.state.config
        UIApplication.shared.isIdleTimerDisabled = config.keepScreenOn

        guard let screen = activeWindowScreen else { return }
        if originalBrightness == nil {
            originalBrightness = screen.brightness
        }
        if config.followSystemBrightness {
            if let originalBrightness {
                screen.brightness = originalBrightness
            }
        } else {
            screen.brightness = CGFloat(config.customBrightness)
        }
    }

    func restoreSystemDisplaySettings() {
        UIApplication.shared.isIdleTimerDisabled = false
        if let originalBrightness, let screen = activeWindowScreen {
            screen.brightness = originalBrightness
        }
    }

    var activeWindowScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first)?.screen
    }

    func setupTTSCallbacks() {
        ttsPlayer.onSentenceChanged = { _, sentence in
            if let targetPageIndex = viewModel.state.pages.firstIndex(where: { $0.contentText.contains(sentence) }),
               targetPageIndex != viewModel.state.currentPageIndex {
                viewModel.send(.jumpToPage(targetPageIndex))
            }
        }
        ttsPlayer.onRequestNextChapterAsync = { [weak viewModel] in
            guard let viewModel else { return nil }
            return await viewModel.fetchNextChapterForTTS()
        }
    }

    func startReaderCacheDownload(option: BatchDownloadOption) {
        guard !viewModel.state.book.isLocalFile else { return }
        cacheDownloadTask?.cancel()
        cacheDownloadProgress = BatchDownloadProgress(
            bookUrl: viewModel.state.book.bookUrl,
            bookName: viewModel.state.book.name,
            totalChaptersToDownload: 0,
            completedChaptersCount: 0,
            status: .downloading)

        let book = viewModel.state.book
        let chapters = viewModel.state.chapters
        cacheDownloadTask = Task {
            do {
                try await environment.batchDownloadChaptersUseCase.execute(
                    book: book,
                    chapters: chapters,
                    option: option,
                    concurrency: 3) { progress in
                        Task { @MainActor in
                            cacheDownloadProgress = progress
                        }
                    }
                await MainActor.run {
                    cacheInfo = environment.manageBookCacheUseCase.getBookCacheInfo(
                        bookUrl: book.bookUrl,
                        totalChapters: chapters.count)
                    toastMessage = "离线缓存完成！"
                }
            } catch is CancellationError {
                await MainActor.run {
                    cacheDownloadProgress?.status = .paused
                }
            } catch {
                await MainActor.run {
                    cacheDownloadProgress?.status = .failed(error.localizedDescription)
                    toastMessage = "缓存失败: \(error.localizedDescription)"
                }
            }
        }
    }
}
