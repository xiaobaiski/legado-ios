import SwiftUI
import UIKit

/// 原生 UIKit 仿真翻页视图（支持 iPhone 单页仿真卷页与 iPad 中脊双页拟真翻书）
public struct PageCurlReaderView: UIViewControllerRepresentable {
    let bookTitle: String
    let pages: [ReaderPage]
    let currentPageIndex: Int
    let chapterIndex: Int
    let totalChapters: Int
    let config: ReaderConfig
    let isDualPage: Bool
    let maxSingleWidth: CGFloat?
    let onPageChanged: (Int) -> Void
    let onRequestNextChapter: () -> Void
    let onRequestPrevChapter: () -> Void
    let onTapLocation: (CGFloat, CGFloat) -> Void

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIViewController(context: Context) -> UIPageViewController {
        let spine: UIPageViewController.SpineLocation = isDualPage ? .mid : .min
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: spine.rawValue])
        controller.isDoubleSided = isDualPage
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = UIColor(config.effectiveBackgroundColor)

        // 禁用 UIPageViewController 默认点击翻页手势，保留完整手指拖拽卷页，点击由自定义三区热区处理
        for recognizer in controller.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:)))
        tapRecognizer.cancelsTouchesInView = false
        controller.view.addGestureRecognizer(tapRecognizer)

        let initialControllers = context.coordinator.makeControllersFor(pageIndex: currentPageIndex)
        if !initialControllers.isEmpty {
            controller.setViewControllers(initialControllers, direction: .forward, animated: false)
        }
        context.coordinator.lastRenderedChapter = chapterIndex
        context.coordinator.lastRenderedPageIndex = context.coordinator.alignedIndex(currentPageIndex)
        context.coordinator.lastConfig = config
        context.coordinator.lastPageCount = pages.count
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        uiViewController.view.backgroundColor = UIColor(config.effectiveBackgroundColor)

        let targetAligned = coordinator.alignedIndex(currentPageIndex)
        let chapterChanged = coordinator.lastRenderedChapter != chapterIndex
        let layoutChanged = coordinator.lastConfig != config
            || coordinator.lastPageCount != pages.count
        let pageChanged = coordinator.lastRenderedPageIndex != targetAligned

        guard chapterChanged || layoutChanged || pageChanged else { return }

        let controllers = coordinator.makeControllersFor(pageIndex: targetAligned)
        guard !controllers.isEmpty else { return }

        let shouldAnimate = !chapterChanged && !layoutChanged && pageChanged
        let direction: UIPageViewController.NavigationDirection =
            targetAligned >= coordinator.lastRenderedPageIndex ? .forward : .reverse

        coordinator.lastRenderedChapter = chapterIndex
        coordinator.lastRenderedPageIndex = targetAligned
        coordinator.lastConfig = config
        coordinator.lastPageCount = pages.count

        uiViewController.setViewControllers(controllers, direction: direction, animated: shouldAnimate)
    }

    @MainActor
    public final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlReaderView
        var lastRenderedChapter = -1
        var lastRenderedPageIndex = -1
        var lastPageCount = -1
        var lastConfig: ReaderConfig?
        private var lastChapterRequestAt: Date = .distantPast

        init(parent: PageCurlReaderView) {
            self.parent = parent
        }

        private func requestChapterTurnIfAllowed(_ action: @escaping @MainActor () -> Void) {
            let now = Date()
            guard now.timeIntervalSince(lastChapterRequestAt) > 0.45 else { return }
            lastChapterRequestAt = now
            Task { @MainActor in
                action()
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let view = recognizer.view,
                  view.bounds.width > 0,
                  view.bounds.height > 0 else { return }
            let location = recognizer.location(in: view)
            let xRatio = min(max(location.x / view.bounds.width, 0), 1)
            let yRatio = min(max(location.y / view.bounds.height, 0), 1)
            parent.onTapLocation(xRatio, yRatio)
        }

        func alignedIndex(_ index: Int) -> Int {
            guard !parent.pages.isEmpty else { return 0 }
            let clamped = min(max(index, 0), parent.pages.count - 1)
            return parent.isDualPage ? (clamped - clamped % 2) : clamped
        }

        func makeControllersFor(pageIndex: Int) -> [UIViewController] {
            guard !parent.pages.isEmpty else { return [] }
            let leftIndex = alignedIndex(pageIndex)
            if parent.isDualPage {
                let leftVC = makePageController(for: leftIndex)
                let rightVC = leftIndex + 1 < parent.pages.count
                    ? makePageController(for: leftIndex + 1)
                    : makeBlankPageController(pageIndex: leftIndex + 1)
                return [leftVC, rightVC]
            }
            return [makePageController(for: leftIndex)]
        }

        private func makePageController(for index: Int) -> IndexedPageHostingController {
            let page = parent.pages[index]
            let spineEdge: ReaderPageView.SpineEdge = parent.isDualPage
                ? (index % 2 == 0 ? .trailing : .leading)
                : .none
            let view = ReaderPageView(
                page: page,
                bookTitle: parent.bookTitle,
                totalPages: parent.pages.count,
                totalChapters: parent.totalChapters,
                config: parent.config,
                maxContentWidth: parent.isDualPage ? nil : parent.maxSingleWidth,
                spineEdge: spineEdge)
            let controller = IndexedPageHostingController(pageIndex: index, rootView: view)
            controller.view.backgroundColor = UIColor(parent.config.effectiveBackgroundColor)
            return controller
        }

        private func makeBlankPageController(pageIndex: Int) -> IndexedPageHostingController {
            let dummy = ReaderPage(
                pageIndex: pageIndex,
                chapterIndex: parent.chapterIndex,
                chapterTitle: "",
                textRange: NSRange(location: 0, length: 0),
                contentText: "")
            var blankConfig = parent.config
            blankConfig.showHeader = false
            blankConfig.showFooter = false
            let view = ReaderPageView(
                page: dummy,
                bookTitle: parent.bookTitle,
                totalPages: parent.pages.count,
                totalChapters: parent.totalChapters,
                config: blankConfig,
                spineEdge: parent.isDualPage ? .leading : .none)
            let controller = IndexedPageHostingController(pageIndex: pageIndex, rootView: view)
            controller.view.backgroundColor = UIColor(parent.config.effectiveBackgroundColor)
            return controller
        }

        // MARK: - UIPageViewControllerDataSource

        public func pageViewController(
            _: UIPageViewController,
            viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let current = viewController as? IndexedPageHostingController else { return nil }
            let prevIndex = current.pageIndex - 1
            if prevIndex >= 0 && prevIndex < parent.pages.count {
                return makePageController(for: prevIndex)
            }
            if current.pageIndex == 0 && parent.chapterIndex > 0 {
                requestChapterTurnIfAllowed { [weak self] in
                    self?.parent.onRequestPrevChapter()
                }
            }
            return nil
        }

        public func pageViewController(
            _: UIPageViewController,
            viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let current = viewController as? IndexedPageHostingController else { return nil }
            let nextIndex = current.pageIndex + 1
            if nextIndex >= 0 && nextIndex < parent.pages.count {
                return makePageController(for: nextIndex)
            }
            if parent.isDualPage && nextIndex == parent.pages.count && nextIndex % 2 == 1 {
                return makeBlankPageController(pageIndex: nextIndex)
            }
            if current.pageIndex >= parent.pages.count - 1 && parent.chapterIndex + 1 < parent.totalChapters {
                requestChapterTurnIfAllowed { [weak self] in
                    self?.parent.onRequestNextChapter()
                }
            }
            return nil
        }

        // MARK: - UIPageViewControllerDelegate

        public func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating _: Bool,
            previousViewControllers _: [UIViewController],
            transitionCompleted completed: Bool) {
            guard completed,
                  let first = pageViewController.viewControllers?.first as? IndexedPageHostingController else {
                return
            }
            let newIndex = alignedIndex(first.pageIndex)
            lastRenderedPageIndex = newIndex
            parent.onPageChanged(newIndex)
        }
    }
}

private final class IndexedPageHostingController: UIHostingController<ReaderPageView> {
    let pageIndex: Int

    init(pageIndex: Int, rootView: ReaderPageView) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
