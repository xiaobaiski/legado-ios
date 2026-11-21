import SwiftUI
import UIKit

/// 原生高性能连续上下滚动与匀速自动滚动视图（基于 UITextView + CADisplayLink，支持 60/120Hz 丝滑自动滚屏与触摸暂停）
public struct AutoScrollReaderView: UIViewRepresentable {
    let chapterIndex: Int
    let chapterTitle: String
    let contentText: String
    let config: ReaderConfig
    let highlightedSentence: String?
    let isAutoScrolling: Bool
    let isPaused: Bool
    let onTapCenter: () -> Void
    let onReachedBottom: () -> Void

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = false
        textView.backgroundColor = UIColor(config.theme.backgroundColor)
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInsetAdjustmentBehavior = .never
        textView.delegate = context.coordinator

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        textView.addGestureRecognizer(tap)

        context.coordinator.textView = textView
        context.coordinator.applyContentIfNeeded(to: textView, resetOffset: true)
        context.coordinator.syncDisplayLink()
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        let chapterChanged = coordinator.lastChapterIndex != chapterIndex
        coordinator.parent = self
        uiView.backgroundColor = UIColor(config.theme.backgroundColor)
        coordinator.applyContentIfNeeded(to: uiView, resetOffset: chapterChanged)
        coordinator.syncDisplayLink()
    }

    public static func dismantleUIView(_: UITextView, coordinator: Coordinator) {
        coordinator.stopDisplayLink()
    }

    @MainActor
    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoScrollReaderView
        weak var textView: UITextView?
        var lastChapterIndex = -1
        private var lastRenderSignature = ""
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private var reachedBottomTriggered = false
        private var bottomDwellAccumulator: CFTimeInterval = 0

        init(parent: AutoScrollReaderView) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.onTapCenter()
        }

        func applyContentIfNeeded(to textView: UITextView, resetOffset: Bool) {
            let signature = "\(parent.chapterIndex)|\(parent.contentText.hashValue)|\(parent.config)|" +
                "\(parent.highlightedSentence ?? "")"
            textView.textContainerInset = UIEdgeInsets(
                top: max(parent.config.topMargin, 16),
                left: parent.config.leftMargin,
                bottom: max(parent.config.bottomMargin, 16) + 72,
                right: parent.config.rightMargin)

            guard signature != lastRenderSignature else { return }
            lastRenderSignature = signature
            lastChapterIndex = parent.chapterIndex

            let combined = NSMutableAttributedString()
            if !parent.chapterTitle.isEmpty {
                let titleFont = parent.config.resolvedUIFont(size: parent.config.fontSize + 4, isBold: true)
                let titleStyle = NSMutableParagraphStyle()
                titleStyle.paragraphSpacing = max(parent.config.paragraphSpacing + 8, 16)
                let titleStr = parent.config.chineseConversion.convert(parent.chapterTitle) + "\n"
                combined.append(NSAttributedString(string: titleStr, attributes: [
                    .font: titleFont,
                    .foregroundColor: UIColor(parent.config.theme.textColor),
                    .paragraphStyle: titleStyle,
                ]))
            }

            let bodyAttr = TextLayoutEngine.shared.createAttributedString(
                content: parent.contentText,
                config: parent.config,
                highlightedSentence: parent.highlightedSentence)
            combined.append(bodyAttr)
            textView.attributedText = combined

            if resetOffset {
                textView.setContentOffset(.zero, animated: false)
                reachedBottomTriggered = false
                bottomDwellAccumulator = 0
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
            let link = CADisplayLink(target: self, selector: #selector(stepScroll(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = 0
        }

        @objc private func stepScroll(_ link: CADisplayLink) {
            guard let textView, parent.isAutoScrolling, !parent.isPaused else { return }
            if textView.isTracking || textView.isDragging || textView.isDecelerating {
                lastTimestamp = link.timestamp
                return
            }

            if lastTimestamp == 0 {
                lastTimestamp = link.timestamp
                return
            }

            let dt = min(max(link.timestamp - lastTimestamp, 0), 0.05)
            lastTimestamp = link.timestamp

            let maxOffsetY = max(textView.contentSize.height - textView.bounds.height, 0)
            let currentY = textView.contentOffset.y

            if currentY >= maxOffsetY - 1 {
                bottomDwellAccumulator += dt
                if !reachedBottomTriggered && bottomDwellAccumulator >= 0.8 {
                    reachedBottomTriggered = true
                    parent.onReachedBottom()
                }
                return
            }

            bottomDwellAccumulator = 0
            reachedBottomTriggered = false
            let speed = CGFloat(max(parent.config.autoScrollSpeed, 10))
            let nextY = min(currentY + speed * CGFloat(dt), maxOffsetY)
            textView.contentOffset = CGPoint(x: 0, y: nextY)
        }
    }
}
