import SwiftUI
import UIKit

// MARK: - ReaderView 辅助悬浮栏、键盘快捷键与系统亮度/缓存控制扩展

extension ReaderView {
    var autoPageFloatingBar: some View {
        let config = viewModel.state.config
        let isScrollMode = config.autoPageMode == .smoothScroll || config.pageTurnMode == .scroll

        return VStack {
            Spacer()
            HStack(spacing: 10) {
                Button {
                    var updated = config
                    updated.autoPageMode = isScrollMode ? .paged : .smoothScroll
                    viewModel.send(.updateConfig(updated))
                } label: {
                    Label(
                        isScrollMode ? "上下滚动" : "定时翻页",
                        systemImage: isScrollMode ? "arrow.up.and.down.text.horizontal" : "play.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 14)

                Text(
                    isScrollMode
                        ? "速度 \(Int(config.autoScrollSpeed))"
                        : "\(Int(config.autoPageIntervalSeconds))秒/页")
                    .font(.caption.weight(.medium).monospacedDigit())

                Button {
                    if isScrollMode {
                        var updated = config
                        updated.autoScrollSpeed = max(updated.autoScrollSpeed - 10, 15)
                        viewModel.send(.updateConfig(updated))
                    } else {
                        viewModel.send(.setAutoPageInterval(config.autoPageIntervalSeconds - 1))
                    }
                } label: {
                    Image(systemName: "minus.circle")
                }

                Button {
                    if isScrollMode {
                        var updated = config
                        updated.autoScrollSpeed = min(updated.autoScrollSpeed + 10, 140)
                        viewModel.send(.updateConfig(updated))
                    } else {
                        viewModel.send(.setAutoPageInterval(config.autoPageIntervalSeconds + 1))
                    }
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

    func flushReadingSession() {
        guard let start = readingSessionStart else { return }
        readingSessionStart = nil
        let elapsed = Date().timeIntervalSince(start)
        ReadRecordStore.shared.recordSession(
            bookName: viewModel.state.book.name,
            bookAuthor: viewModel.state.book.author,
            durationSeconds: elapsed)
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
        let shouldEnable = viewModel.state.config.volumeKeyPageTurn
        if shouldEnable {
            volumeHandler.start(
                onVolumeUp: { [weak viewModel] in viewModel?.send(.prevPage) },
                onVolumeDown: { [weak viewModel] in viewModel?.send(.nextPage) })
        } else {
            volumeHandler.stop()
        }
    }

    func applySystemDisplaySettings() {
        scheduleScreenKeepOnTimer()
        let config = viewModel.state.config

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

    func scheduleScreenKeepOnTimer() {
        screenKeepOnTask?.cancel()
        screenKeepOnTask = nil
        let duration = viewModel.state.config.keepScreenOnDuration
        switch duration {
        case .system:
            UIApplication.shared.isIdleTimerDisabled = false

        case .always:
            UIApplication.shared.isIdleTimerDisabled = true

        case .minutes5, .minutes10, .minutes30:
            UIApplication.shared.isIdleTimerDisabled = true
            let seconds = UInt64(duration.rawValue) * 60
            screenKeepOnTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    func restoreSystemDisplaySettings() {
        screenKeepOnTask?.cancel()
        screenKeepOnTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if let originalBrightness, let screen = activeWindowScreen {
            screen.brightness = originalBrightness
        }
    }

    var activeWindowScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first)?.screen
    }

    func openSearchContentSheet() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            viewModel.send(.hideHUD)
            isSearchContentPresented = true
        }
    }
}
