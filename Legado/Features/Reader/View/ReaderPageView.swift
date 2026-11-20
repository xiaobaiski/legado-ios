import CoreText
import SwiftUI
import UIKit

/// 单页排版内容呈现视图（使用 CoreText 与分页引擎像素级一致绘制，支持段距/行距/字距/字体/对齐）
public struct ReaderPageView: View {
    let page: ReaderPage
    let totalPages: Int
    let totalChapters: Int
    let config: ReaderConfig
    let highlightedSentence: String?
    let maxContentWidth: CGFloat?

    public init(
        page: ReaderPage,
        totalPages: Int,
        totalChapters: Int = 1,
        config: ReaderConfig,
        highlightedSentence: String? = nil,
        maxContentWidth: CGFloat? = nil) {
        self.page = page
        self.totalPages = totalPages
        self.totalChapters = totalChapters
        self.config = config
        self.highlightedSentence = highlightedSentence
        self.maxContentWidth = maxContentWidth
    }

    private var bookProgressPercent: String {
        let safeChapters = max(totalChapters, 1)
        let safePages = max(totalPages, 1)
        let chapterBase = Double(page.chapterIndex) / Double(safeChapters)
        let inChapter = Double(page.pageIndex + 1) / Double(safePages) / Double(safeChapters)
        let total = min(max((chapterBase + inChapter) * 100.0, 0), 100)
        return String(format: "%.1f%%", total)
    }

    public var body: some View {
        let topHeight = TextLayoutEngine.effectiveTopMargin(for: config)
        let bottomHeight = TextLayoutEngine.effectiveBottomMargin(for: config)
        let halfCanvasPad = TextLayoutEngine.verticalCanvasPadding / 2

        VStack(spacing: 0) {
            // 页顶：章节标题与当前时间
            if config.showHeader {
                HStack {
                    Text(config.chineseConversion.convert(page.chapterTitle))
                        .font(.caption2)
                        .foregroundStyle(config.theme.textColor.opacity(0.48))
                        .lineLimit(1)

                    Spacer()

                    Text(Date(), format: .dateTime.hour().minute())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(config.theme.textColor.opacity(0.48))
                }
                .frame(maxWidth: maxContentWidth ?? .infinity)
                .padding(.horizontal, config.horizontalMargin)
                .padding(.bottom, 2)
                .frame(height: topHeight, alignment: .bottom)
            } else {
                Spacer().frame(height: topHeight)
            }

            // 正文区域：基于 CoreText 精确渲染，高度与 TextLayoutEngine.contentRenderRect 像素级一致
            CoreTextPageCanvas(
                content: page.contentText,
                config: config,
                highlightedSentence: highlightedSentence)
                .frame(maxWidth: maxContentWidth ?? .infinity, maxHeight: .infinity)
                .padding(.horizontal, config.horizontalMargin)
                .padding(.vertical, halfCanvasPad)

            // 页脚：页码、全书总进度与电池状态
            if config.showFooter {
                HStack(spacing: 10) {
                    Text("第 \(page.pageIndex + 1) / \(max(totalPages, 1)) 页")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(config.theme.textColor.opacity(0.48))

                    Spacer()

                    Text(bookProgressPercent)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(config.theme.textColor.opacity(0.48))

                    batteryBadge
                }
                .frame(maxWidth: maxContentWidth ?? .infinity)
                .padding(.horizontal, config.horizontalMargin)
                .padding(.top, 2)
                .frame(height: bottomHeight, alignment: .top)
            } else {
                Spacer().frame(height: bottomHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(config.theme.backgroundColor)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var batteryBadge: some View {
        let level = batteryLevel
        if level >= 0 {
            Image(systemName: batterySymbol(for: level))
                .font(.caption2)
                .foregroundStyle(config.theme.textColor.opacity(0.48))
        }
    }

    private var batteryLevel: Float {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
    }

    private func batterySymbol(for level: Float) -> String {
        switch level {
        case ..<0.15: return "battery.0percent"
        case ..<0.40: return "battery.25percent"
        case ..<0.65: return "battery.50percent"
        case ..<0.90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// CoreText 同步排版绘制画布（与 TextLayoutEngine 分页共用同一 NSAttributedString）
private struct CoreTextPageCanvas: UIViewRepresentable {
    let content: String
    let config: ReaderConfig
    let highlightedSentence: String?

    func makeUIView(context _: Context) -> CoreTextDrawView {
        let view = CoreTextDrawView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.contentMode = .redraw
        return view
    }

    func updateUIView(_ uiView: CoreTextDrawView, context _: Context) {
        uiView.attributedText = TextLayoutEngine.shared.createAttributedString(
            content: content,
            config: config,
            highlightedSentence: highlightedSentence)
    }
}

private final class CoreTextDrawView: UIView {
    var attributedText: NSAttributedString? {
        didSet {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let attributedText,
              attributedText.length > 0,
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let path = CGPath(rect: bounds, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

/// iPad 大屏双页并排阅读视图（左右双栏 + 中央轻书脊分隔线）
public struct ReaderDualPageSpreadView: View {
    let leftPage: ReaderPage
    let rightPage: ReaderPage?
    let totalPages: Int
    let totalChapters: Int
    let config: ReaderConfig
    let highlightedSentence: String?

    public init(
        leftPage: ReaderPage,
        rightPage: ReaderPage?,
        totalPages: Int,
        totalChapters: Int,
        config: ReaderConfig,
        highlightedSentence: String? = nil) {
        self.leftPage = leftPage
        self.rightPage = rightPage
        self.totalPages = totalPages
        self.totalChapters = totalChapters
        self.config = config
        self.highlightedSentence = highlightedSentence
    }

    public var body: some View {
        HStack(spacing: 0) {
            ReaderPageView(
                page: leftPage,
                totalPages: totalPages,
                totalChapters: totalChapters,
                config: config,
                highlightedSentence: highlightedSentence)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 居中柔和书脊分隔区（32pt 与 TextLayoutEngine centerGutter 精确对应）
            ZStack {
                config.theme.backgroundColor
                Rectangle()
                    .fill(config.theme.textColor.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 36)
            }
            .frame(width: 32)
            .ignoresSafeArea()

            if let rightPage {
                ReaderPageView(
                    page: rightPage,
                    totalPages: totalPages,
                    totalChapters: totalChapters,
                    config: config,
                    highlightedSentence: highlightedSentence)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                config.theme.backgroundColor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
        .background(config.theme.backgroundColor)
        .ignoresSafeArea()
    }
}
