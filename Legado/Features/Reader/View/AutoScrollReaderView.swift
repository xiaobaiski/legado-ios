import SwiftUI
import UIKit

/// 原生高性能连续上下滚动与匀速自动滚动视图（基于 UITextView + CADisplayLink，支持进度双向定位与触摸暂停）
public struct AutoScrollReaderView: UIViewRepresentable {
    let chapterIndex: Int
    let chapterTitle: String
    let contentText: String
    let titlePrefixLength: Int
    let initialOffset: Int
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let config: ReaderConfig
    let isAutoScrolling: Bool
    let isPaused: Bool
    let onTapCenter: () -> Void
    let onLongPress: () -> Void
    let onScrollOffsetChanged: (Int) -> Void
    let onPullPrevChapter: () -> Void
    let onReachedBottom: () -> Void

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = false
        textView.backgroundColor = UIColor(config.effectiveBackgroundColor)
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInsetAdjustmentBehavior = .never
        textView.delegate = context.coordinator

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        textView.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.55
        textView.addGestureRecognizer(longPress)

        context.coordinator.textView = textView
        context.coordinator.applyContentIfNeeded(to: textView, resetOffset: true)
        context.coordinator.syncDisplayLink()
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        let chapterChanged = coordinator.lastChapterIndex != chapterIndex
        let externalJump = !coordinator.isApplyingLocalOffset
            && coordinator.lastAppliedExternalOffset != initialOffset
            && abs(coordinator.lastReportedOffset - initialOffset) > 120
        coordinator.parent = self
        uiView.backgroundColor = UIColor(config.effectiveBackgroundColor)
        coordinator.applyContentIfNeeded(to: uiView, resetOffset: chapterChanged || externalJump)
        coordinator.syncDisplayLink()
    }

    public static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
        coordinator.emitCurrentOffset(from: textView)
        coordinator.stopDisplayLink()
    }

    @MainActor
    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoScrollReaderView
        weak var textView: UITextView?
        var lastChapterIndex = -1
        var lastAppliedExternalOffset = 0
        var lastReportedOffset = 0
        var isApplyingLocalOffset = false
        private var lastRenderKey: ScrollRenderKey?
        nonisolated(unsafe) private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private var lastOffsetSyncAt: CFTimeInterval = 0
        private var lastChapterEdgeTriggerAt: Date = .distantPast
        private var reachedBottomTriggered = false
        private var bottomDwellAccumulator: CFTimeInterval = 0

        deinit {
            displayLink?.invalidate()
            displayLink = nil
        }

        init(parent: AutoScrollReaderView) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.onTapCenter()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            parent.onLongPress()
        }

        func applyContentIfNeeded(to textView: UITextView, resetOffset: Bool) {
            let renderKey = ScrollRenderKey(
                chapterIndex: parent.chapterIndex,
                titlePrefixLength: parent.titlePrefixLength,
                contentText: parent.contentText,
                config: parent.config)
            let topInset = max(parent.config.topMargin, parent.safeAreaTop + 8)
            let bottomInset = max(parent.config.bottomMargin, parent.safeAreaBottom + 16) + 56
            textView.textContainerInset = UIEdgeInsets(
                top: topInset,
                left: parent.config.leftMargin,
                bottom: bottomInset,
                right: parent.config.rightMargin)

            let contentChanged = renderKey != lastRenderKey
            if contentChanged {
                lastRenderKey = renderKey
                lastChapterIndex = parent.chapterIndex
                textView.attributedText = TextLayoutEngine.shared.createAttributedString(
                    content: parent.contentText,
                    config: parent.config,
                    titlePrefixLength: parent.titlePrefixLength)
            }

            if resetOffset || (contentChanged && parent.initialOffset > 0 && lastReportedOffset == 0) {
                lastAppliedExternalOffset = parent.initialOffset
                lastReportedOffset = parent.initialOffset
                reachedBottomTriggered = false
                bottomDwellAccumulator = 0
                scrollTextView(textView, toCharacterOffset: parent.initialOffset)
            }
        }

        private func scrollTextView(_ textView: UITextView, toCharacterOffset offset: Int) {
            let targetY: CGFloat
            let totalLen = textView.attributedText.length
            let clamped = min(max(offset, 0), max(totalLen - 1, 0))
            if clamped > 0, totalLen > 0 {
                textView.layoutManager.ensureLayout(for: textView.textContainer)
                let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: clamped)
                let rect = textView.layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: glyphIndex, length: 1),
                    in: textView.textContainer)
                let maxY = max(textView.contentSize.height - textView.bounds.height, 0)
                targetY = min(max(rect.minY, 0), maxY)
            } else {
                targetY = 0
            }

            DispatchQueue.main.async { [weak self, weak textView] in
                guard let textView else { return }
                let maxY = max(textView.contentSize.height - textView.bounds.height, 0)
                textView.setContentOffset(CGPoint(x: 0, y: min(targetY, maxY)), animated: false)
                self?.lastAppliedExternalOffset = offset
            }
        }

        func emitCurrentOffset(from textView: UITextView) {
            let totalLen = textView.attributedText.length
            guard totalLen > 0 else { return }
            let probe = CGPoint(
                x: textView.textContainerInset.left + 4,
                y: max(0, textView.contentOffset.y + textView.textContainerInset.top + 4))
            var fraction: CGFloat = 0
            let index = textView.layoutManager.characterIndex(
                for: probe,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: &fraction)
            let clamped = min(max(index, 0), max(totalLen - 1, 0))
            guard abs(clamped - lastReportedOffset) >= 10 || (clamped == 0 && lastReportedOffset > 0) else {
                return
            }
            lastReportedOffset = clamped
            lastAppliedExternalOffset = clamped
            isApplyingLocalOffset = true
            parent.onScrollOffsetChanged(clamped)
            isApplyingLocalOffset = false
        }

        // MARK: - UIScrollViewDelegate

        public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard let textView = scrollView as? UITextView else { return }
            emitCurrentOffset(from: textView)
            if !parent.isAutoScrolling {
                checkPullChapterEdge(scrollView)
            }
            if !decelerate {
                emitCurrentOffset(from: textView)
            }
        }

        public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            if let textView = scrollView as? UITextView {
                emitCurrentOffset(from: textView)
            }
        }

        private func checkPullChapterEdge(_ scrollView: UIScrollView) {
            let now = Date()
            guard now.timeIntervalSince(lastChapterEdgeTriggerAt) > 0.8 else { return }
            let y = scrollView.contentOffset.y
            let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
            if y < -64 {
                lastChapterEdgeTriggerAt = now
                parent.onPullPrevChapter()
            } else if maxY > 0 && (y - maxY) > 64 {
                lastChapterEdgeTriggerAt = now
                parent.onReachedBottom()
            }
        }

        func syncDisplayLink() {
            if parent.isAutoScrolling && !parent.isPaused {
                startDisplayLink()
            } else {
                stopDisplayLink()
            }
        }

        private func startDisplayLink() {
            guard displayLink == nil else { return }
            lastTimestamp = 0
            lastOffsetSyncAt = 0
            let proxy = WeakDisplayLinkProxy(target: self)
            let link = CADisplayLink(target: proxy, selector: #selector(WeakDisplayLinkProxy.handleTick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = 0
        }

        fileprivate func stepScrollTick(timestamp: CFTimeInterval) {
            guard let textView, parent.isAutoScrolling, !parent.isPaused else { return }
            if textView.isTracking || textView.isDragging || textView.isDecelerating {
                lastTimestamp = timestamp
                return
            }

            if lastTimestamp == 0 {
                lastTimestamp = timestamp
                lastOffsetSyncAt = timestamp
                return
            }

            let deltaTime = min(max(timestamp - lastTimestamp, 0), 0.05)
            lastTimestamp = timestamp

            let maxOffsetY = max(textView.contentSize.height - textView.bounds.height, 0)
            let currentY = textView.contentOffset.y

            if currentY >= maxOffsetY - 1 {
                bottomDwellAccumulator += deltaTime
                if !reachedBottomTriggered && bottomDwellAccumulator >= 0.8 {
                    reachedBottomTriggered = true
                    emitCurrentOffset(from: textView)
                    parent.onReachedBottom()
                }
                return
            }

            bottomDwellAccumulator = 0
            reachedBottomTriggered = false
            let speed = CGFloat(max(parent.config.autoScrollSpeed, 10))
            let nextY = min(currentY + speed * CGFloat(deltaTime), maxOffsetY)
            textView.contentOffset = CGPoint(x: 0, y: nextY)

            if timestamp - lastOffsetSyncAt >= 1.5 {
                lastOffsetSyncAt = timestamp
                emitCurrentOffset(from: textView)
            }
        }
    }
}

/// 弱引用 CADisplayLink 代理：彻底打破 CADisplayLink -> Coordinator 强引用环
private final class WeakDisplayLinkProxy: NSObject, @unchecked Sendable {
    weak var target: AutoScrollReaderView.Coordinator?

    init(target: AutoScrollReaderView.Coordinator) {
        self.target = target
    }

    @objc func handleTick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        guard let target else {
            link.invalidate()
            return
        }
        MainActor.assumeIsolated {
            target.stepScrollTick(timestamp: timestamp)
        }
    }
}

private struct ScrollRenderKey: Equatable {
    let chapterIndex: Int
    let titlePrefixLength: Int
    let contentText: String
    let config: ReaderConfig
}
