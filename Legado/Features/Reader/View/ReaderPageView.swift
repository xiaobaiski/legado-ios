import CoreText
import SwiftUI
import UIKit

/// 单页排版内容呈现视图（使用 CoreText 与分页引擎像素级一致绘制，缓存 CTFramesetter 避免冗余重绘）
public struct ReaderPageView: View {
    public enum SpineEdge: Sendable {
        case none
        case trailing // 左页右侧紧邻书脊
        case leading  // 右页左侧紧邻书脊
    }

    let page: ReaderPage
    let totalPages: Int
    let totalChapters: Int
    let config: ReaderConfig
    let highlightedSentence: String?
    let maxContentWidth: CGFloat?
    let spineEdge: SpineEdge

    public init(
        page: ReaderPage,
        totalPages: Int,
        totalChapters: Int = 1,
        config: ReaderConfig,
        highlightedSentence: String? = nil,
        maxContentWidth: CGFloat? = nil,
        spineEdge: SpineEdge = .none) {
        self.page = page
        self.totalPages = totalPages
        self.totalChapters = totalChapters
        self.config = config
        self.highlightedSentence = highlightedSentence
        self.maxContentWidth = maxContentWidth
        self.spineEdge = spineEdge
    }

    private var bookProgressPercent: String {
        let safeChapters = max(totalChapters, 1)
        let safePages = max(totalPages, 1)
        let chapterBase = Double(page.chapterIndex) / Double(safeChapters)
        let inChapter = Double(page.pageIndex + 1) / Double(safePages) / Double(safeChapters)
        let total = min(max((chapterBase + inChapter) * 100.0, 0), 100)
        return String(format: "%.1f%%", total)
    }

    private var leadingPadding: CGFloat {
        config.horizontalMargin + (spineEdge == .leading ? 16 : 0)
    }

    private var trailingPadding: CGFloat {
        config.horizontalMargin + (spineEdge == .trailing ? 16 : 0)
    }

    public var body: some View {
        let topHeight = TextLayoutEngine.effectiveTopMargin(for: config)
        let bottomHeight = TextLayoutEngine.effectiveBottomMargin(for: config)
        let halfCanvasPad = TextLayoutEngine.verticalCanvasPadding / 2

        ZStack {
            VStack(spacing: 0) {
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
                    .padding(.leading, leadingPadding)
                    .padding(.trailing, trailingPadding)
                    .padding(.bottom, 2)
                    .frame(height: topHeight, alignment: .bottom)
                } else {
                    Spacer().frame(height: topHeight)
                }

                CoreTextPageCanvas(
                    content: page.contentText,
                    config: config,
                    highlightedSentence: highlightedSentence)
                    .frame(maxWidth: maxContentWidth ?? .infinity, maxHeight: .infinity)
                    .padding(.leading, leadingPadding)
                    .padding(.trailing, trailingPadding)
                    .padding(.vertical, halfCanvasPad)

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
                    .padding(.leading, leadingPadding)
                    .padding(.trailing, trailingPadding)
                    .padding(.top, 2)
                    .frame(height: bottomHeight, alignment: .top)
                } else {
                    Spacer().frame(height: bottomHeight)
                }
            }

            // iPad 双页模式书脊柔光折痕阴影
            if spineEdge != .none {
                spineShadowOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(config.theme.backgroundColor)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var spineShadowOverlay: some View {
        let shadowAlpha = config.theme.isDark ? 0.22 : 0.06
        HStack(spacing: 0) {
            if spineEdge == .leading {
                LinearGradient(
                    colors: [Color.black.opacity(shadowAlpha), .clear],
                    startPoint: .leading,
                    endPoint: .trailing)
                    .frame(width: 18)
                Spacer()
            } else if spineEdge == .trailing {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(shadowAlpha)],
                    startPoint: .leading,
                    endPoint: .trailing)
                    .frame(width: 18)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var batteryBadge: some View {
        let level = BatteryMonitor.currentLevel
        if level >= 0 {
            Image(systemName: batterySymbol(for: level))
                .font(.caption2)
                .foregroundStyle(config.theme.textColor.opacity(0.48))
        }
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

@MainActor
private enum BatteryMonitor {
    private static var isEnabled = false

    static var currentLevel: Float {
        if !isEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
            isEnabled = true
        }
        return UIDevice.current.batteryLevel
    }
}

/// CoreText 同步排版绘制画布（仅在内容或排版参数实际变化时重建 CTFramesetter，消除 HUD 闪烁重绘）
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
        uiView.updateIfNeeded(
            content: content,
            config: config,
            highlightedSentence: highlightedSentence)
    }
}

private final class CoreTextDrawView: UIView {
    private struct RenderKey: Equatable {
        let content: String
        let config: ReaderConfig
        let highlightedSentence: String?
    }

    private var lastKey: RenderKey?
    private var cachedFramesetter: CTFramesetter?

    func updateIfNeeded(content: String, config: ReaderConfig, highlightedSentence: String?) {
        let key = RenderKey(content: content, config: config, highlightedSentence: highlightedSentence)
        guard key != lastKey else { return }
        lastKey = key
        let attributed = TextLayoutEngine.shared.createAttributedString(
            content: content,
            config: config,
            highlightedSentence: highlightedSentence)
        cachedFramesetter = attributed.length > 0
            ? CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
            : nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let framesetter = cachedFramesetter,
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)

        let path = CGPath(rect: bounds, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

/// iPad 大屏双页并排阅读视图（左右双栏 + 拟真纸书中央书脊柔光折痕，宽度与 TextLayoutEngine 精确一致）
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
                highlightedSentence: highlightedSentence,
                spineEdge: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let rightPage {
                ReaderPageView(
                    page: rightPage,
                    totalPages: totalPages,
                    totalChapters: totalChapters,
                    config: config,
                    highlightedSentence: highlightedSentence,
                    spineEdge: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                config.theme.backgroundColor
                    .overlay(alignment: .leading) {
                        LinearGradient(
                            colors: [Color.black.opacity(config.theme.isDark ? 0.22 : 0.06), .clear],
                            startPoint: .leading,
                            endPoint: .trailing)
                            .frame(width: 18)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
        .overlay {
            Rectangle()
                .fill(config.theme.textColor.opacity(0.08))
                .frame(width: 0.5)
                .padding(.vertical, 28)
        }
        .background(config.theme.backgroundColor)
        .ignoresSafeArea()
    }
}
