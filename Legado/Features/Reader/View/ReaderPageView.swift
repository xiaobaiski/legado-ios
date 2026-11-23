import CoreText
import SwiftUI
import UIKit

/// 单页排版内容呈现视图（支持 6 槽位自定义页眉页脚、正文章节大标题、自定义配色与 CoreText 零冗余绘制）
public struct ReaderPageView: View {
    public enum SpineEdge: Sendable {
        case none
        case trailing // 左页右侧紧邻书脊
        case leading  // 右页左侧紧邻书脊
    }

    let page: ReaderPage
    let bookTitle: String
    let totalPages: Int
    let totalChapters: Int
    let config: ReaderConfig
    let maxContentWidth: CGFloat?
    let spineEdge: SpineEdge

    public init(
        page: ReaderPage,
        bookTitle: String = "",
        totalPages: Int,
        totalChapters: Int = 1,
        config: ReaderConfig,
        maxContentWidth: CGFloat? = nil,
        spineEdge: SpineEdge = .none) {
        self.page = page
        self.bookTitle = bookTitle
        self.totalPages = totalPages
        self.totalChapters = totalChapters
        self.config = config
        self.maxContentWidth = maxContentWidth
        self.spineEdge = spineEdge
    }

    private var leadingPadding: CGFloat {
        config.leftMargin + (spineEdge == .leading ? 16 : 0)
    }

    private var trailingPadding: CGFloat {
        config.rightMargin + (spineEdge == .trailing ? 16 : 0)
    }

    public var body: some View {
        let topHeight = TextLayoutEngine.effectiveTopMargin(for: config)
        let bottomHeight = TextLayoutEngine.effectiveBottomMargin(for: config)
        let halfCanvasPad = TextLayoutEngine.verticalCanvasPadding / 2
        let textColor = config.effectiveTextColor
        let bgColor = config.effectiveBackgroundColor

        ZStack {
            VStack(spacing: 0) {
                if config.showHeader {
                    VStack(spacing: 3) {
                        tipBarRow(
                            left: config.tipConfig.headerLeft,
                            center: config.tipConfig.headerCenter,
                            right: config.tipConfig.headerRight,
                            textColor: textColor)

                        if config.showHeaderDivider {
                            Rectangle()
                                .fill(textColor.opacity(0.14))
                                .frame(height: 0.5)
                        }
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
                    titlePrefixLength: page.titlePrefixLength,
                    config: config)
                    .frame(maxWidth: maxContentWidth ?? .infinity, maxHeight: .infinity)
                    .padding(.leading, leadingPadding)
                    .padding(.trailing, trailingPadding)
                    .padding(.vertical, halfCanvasPad)

                if config.showFooter {
                    VStack(spacing: 3) {
                        if config.showFooterDivider {
                            Rectangle()
                                .fill(textColor.opacity(0.14))
                                .frame(height: 0.5)
                        }

                        tipBarRow(
                            left: config.tipConfig.footerLeft,
                            center: config.tipConfig.footerCenter,
                            right: config.tipConfig.footerRight,
                            textColor: textColor)
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

            if spineEdge != .none {
                spineShadowOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgColor)
        .ignoresSafeArea()
    }

    private func tipBarRow(
        left: ReadTipItem,
        center: ReadTipItem,
        right: ReadTipItem,
        textColor: Color) -> some View {
        let fontSize = config.tipConfig.tipFontSize
        let foreground = textColor.opacity(0.50)

        return HStack(spacing: 8) {
            tipSlotView(left, fontSize: fontSize, color: foreground)
                .frame(maxWidth: .infinity, alignment: .leading)

            if center != .none {
                tipSlotView(center, fontSize: fontSize, color: foreground)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            tipSlotView(right, fontSize: fontSize, color: foreground)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func tipSlotView(_ item: ReadTipItem, fontSize: CGFloat, color: Color) -> some View {
        switch item {
        case .none:
            EmptyView()

        case .bookTitle:
            Text(config.chineseConversion.convert(bookTitle))
                .font(.system(size: fontSize))
                .foregroundStyle(color)

        case .chapterTitle:
            Text(config.chineseConversion.convert(page.chapterTitle))
                .font(.system(size: fontSize))
                .foregroundStyle(color)

        case .time:
            Text(Date(), format: .dateTime.hour().minute())
                .font(.system(size: fontSize).monospacedDigit())
                .foregroundStyle(color)

        case .battery:
            batteryView(fontSize: fontSize, color: color)

        case .pageAndTotal:
            Text("\(page.pageIndex + 1)/\(max(totalPages, 1))")
                .font(.system(size: fontSize).monospacedDigit())
                .foregroundStyle(color)

        case .chapterProgress:
            let pct = Int(round(Double(page.pageIndex + 1) / Double(max(totalPages, 1)) * 100))
            Text("\(pct)%")
                .font(.system(size: fontSize).monospacedDigit())
                .foregroundStyle(color)

        case .bookProgress:
            Text(bookProgressPercent)
                .font(.system(size: fontSize).monospacedDigit())
                .foregroundStyle(color)

        case .chapterIndex:
            Text("\(page.chapterIndex + 1)/\(max(totalChapters, 1))")
                .font(.system(size: fontSize).monospacedDigit())
                .foregroundStyle(color)

        case .remainingPages:
            let left = max(totalPages - page.pageIndex - 1, 0)
            Text(left == 0 ? "本章末页" : "余\(left)页")
                .font(.system(size: fontSize).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private var bookProgressPercent: String {
        let safeChapters = max(totalChapters, 1)
        let safePages = max(totalPages, 1)
        let chapterBase = Double(page.chapterIndex) / Double(safeChapters)
        let inChapter = Double(page.pageIndex + 1) / Double(safePages) / Double(safeChapters)
        let total = min(max((chapterBase + inChapter) * 100.0, 0), 100)
        return String(format: "%.1f%%", total)
    }

    @ViewBuilder
    private func batteryView(fontSize: CGFloat, color: Color) -> some View {
        let level = BatteryMonitor.currentLevel
        if level >= 0 {
            HStack(spacing: 3) {
                Image(systemName: batterySymbol(for: level))
                Text("\(Int(round(level * 100)))%")
            }
            .font(.system(size: fontSize).monospacedDigit())
            .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private var spineShadowOverlay: some View {
        let shadowAlpha = config.isEffectiveDark ? 0.22 : 0.06
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

/// CoreText 同步排版绘制画布（仅在内容、标题长度或排版参数实际变化时重建 CTFramesetter）
private struct CoreTextPageCanvas: UIViewRepresentable {
    let content: String
    let titlePrefixLength: Int
    let config: ReaderConfig

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
            titlePrefixLength: titlePrefixLength,
            config: config)
    }
}

private final class CoreTextDrawView: UIView {
    private struct RenderKey: Equatable {
        let content: String
        let titlePrefixLength: Int
        let fontFamily: ReaderFontFamily
        let customFontName: String?
        let fontSize: CGFloat
        let fontWeight: ReaderFontWeight
        let isBoldFont: Bool
        let lineSpacing: CGFloat
        let paragraphSpacing: CGFloat
        let letterSpacing: CGFloat
        let isTextJustified: Bool
        let theme: ReaderTheme
        let customTextHex: String
        let titleStyle: ChapterTitleStyleConfig
    }

    private var lastKey: RenderKey?
    private var cachedFramesetter: CTFramesetter?
    private var cachedFrame: CTFrame?
    private var cachedFrameSize: CGSize = .zero

    func updateIfNeeded(
        content: String,
        titlePrefixLength: Int,
        config: ReaderConfig) {
        let key = RenderKey(
            content: content,
            titlePrefixLength: titlePrefixLength,
            fontFamily: config.fontFamily,
            customFontName: config.customFontName,
            fontSize: config.fontSize,
            fontWeight: config.fontWeight,
            isBoldFont: config.isBoldFont,
            lineSpacing: config.lineSpacing,
            paragraphSpacing: config.paragraphSpacing,
            letterSpacing: config.letterSpacing,
            isTextJustified: config.isTextJustified,
            theme: config.theme,
            customTextHex: config.customTextHex,
            titleStyle: config.titleStyle)
        guard key != lastKey else { return }
        lastKey = key
        let attributed = TextLayoutEngine.shared.createAttributedString(
            content: content,
            config: config,
            titlePrefixLength: titlePrefixLength)
        cachedFramesetter = attributed.length > 0
            ? CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
            : nil
        cachedFrame = nil
        cachedFrameSize = .zero
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let framesetter = cachedFramesetter,
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        if cachedFrame == nil || cachedFrameSize != bounds.size {
            let path = CGPath(rect: bounds, transform: nil)
            cachedFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            cachedFrameSize = bounds.size
        }
        guard let frame = cachedFrame else { return }

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

/// iPad 大屏双页并排阅读视图（左右双栏 + 拟真纸书中央书脊柔光折痕，宽度与 TextLayoutEngine 精确一致）
public struct ReaderDualPageSpreadView: View {
    let leftPage: ReaderPage
    let rightPage: ReaderPage?
    let bookTitle: String
    let totalPages: Int
    let totalChapters: Int
    let config: ReaderConfig

    public init(
        leftPage: ReaderPage,
        rightPage: ReaderPage?,
        bookTitle: String = "",
        totalPages: Int,
        totalChapters: Int,
        config: ReaderConfig) {
        self.leftPage = leftPage
        self.rightPage = rightPage
        self.bookTitle = bookTitle
        self.totalPages = totalPages
        self.totalChapters = totalChapters
        self.config = config
    }

    public var body: some View {
        HStack(spacing: 0) {
            ReaderPageView(
                page: leftPage,
                bookTitle: bookTitle,
                totalPages: totalPages,
                totalChapters: totalChapters,
                config: config,
                spineEdge: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let rightPage {
                ReaderPageView(
                    page: rightPage,
                    bookTitle: bookTitle,
                    totalPages: totalPages,
                    totalChapters: totalChapters,
                    config: config,
                    spineEdge: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                config.effectiveBackgroundColor
                    .overlay(alignment: .leading) {
                        LinearGradient(
                            colors: [Color.black.opacity(config.isEffectiveDark ? 0.22 : 0.06), .clear],
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
                .fill(config.effectiveTextColor.opacity(0.08))
                .frame(width: 0.5)
                .padding(.vertical, 28)
        }
        .background(config.effectiveBackgroundColor)
        .ignoresSafeArea()
    }
}
