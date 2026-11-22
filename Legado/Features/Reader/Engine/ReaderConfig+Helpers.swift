import SwiftUI
import UIKit

// MARK: - ReaderConfig 计算属性、字体解析与分页差异检查扩展

extension ReaderConfig {
    public static let defaultConfig = ReaderConfig()

    /// 当前生效背景色（自定义主题自动取 `customBackgroundHex`）
    public var effectiveBackgroundColor: Color {
        theme == .custom
            ? HexColorCodec.color(from: customBackgroundHex, fallback: theme.backgroundColor)
            : theme.backgroundColor
    }

    /// 当前生效正文颜色（自定义主题自动取 `customTextHex`）
    public var effectiveTextColor: Color {
        theme == .custom
            ? HexColorCodec.color(from: customTextHex, fallback: theme.textColor)
            : theme.textColor
    }

    /// 当前主题是否属于暗色（用于同步阅读器 HUD/弹窗暗黑外观与夜间模式判断）
    public var isEffectiveDark: Bool {
        theme == .custom ? HexColorCodec.isDarkColor(hex: customBackgroundHex) : theme.isDark
    }

    /// 一键切换阅读器日间 / 夜间模式（自动记忆上一次日间与夜间主题配色）
    public mutating func toggleNightMode() {
        if isEffectiveDark {
            if theme != .custom {
                lastDarkTheme = theme
            }
            theme = lastLightTheme.isDark ? .paper : lastLightTheme
        } else {
            if theme != .custom {
                lastLightTheme = theme
            }
            theme = lastDarkTheme.isDark ? lastDarkTheme : .dark
        }
    }

    /// 切换主题并同步更新日间/夜间记忆主题
    public mutating func applyTheme(_ newTheme: ReaderTheme) {
        theme = newTheme
        guard newTheme != .custom else { return }
        if newTheme.isDark {
            lastDarkTheme = newTheme
        } else {
            lastLightTheme = newTheme
        }
    }

    /// 判断给定画布尺寸下是否启用 iPad 横屏大屏双页并排阅读
    public func isDualPageActive(for bounds: CGRect) -> Bool {
        enableIPadDualPage && pageTurnMode != .scroll && bounds.width >= 820 && bounds.width >= bounds.height
    }

    /// 解析当前最终使用的 UIFont（优先自定义本地字体 + 精细字重，失败回退系统字体）
    public func resolvedUIFont(size: CGFloat? = nil, isBold: Bool? = nil) -> UIFont {
        let targetSize = size ?? fontSize
        let targetBold = isBold ?? (isBoldFont || fontWeight.isBoldLike)
        if let customName = customFontName, !customName.isEmpty,
           let baseFont = UIFont(name: customName, size: targetSize) {
            if targetBold,
               let boldDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: boldDescriptor, size: targetSize)
            }
            return baseFont
        }
        let effectiveWeight: ReaderFontWeight? = isBold == true ? .bold : (isBoldFont ? .semibold : fontWeight)
        return fontFamily.uiFont(size: targetSize, isBold: targetBold, weight: effectiveWeight)
    }

    /// 解析当前最终使用的 SwiftUI Font
    public func resolvedSwiftUIFont(size: CGFloat? = nil, isBold: Bool? = nil) -> Font {
        Font(resolvedUIFont(size: size, isBold: isBold))
    }

    /// 判断变更是否影响排版分页（用于决定是否需要重新执行 CoreText 分页）
    public func requiresRepagination(comparedTo other: ReaderConfig) -> Bool {
        fontSize != other.fontSize ||
            lineSpacing != other.lineSpacing ||
            paragraphSpacing != other.paragraphSpacing ||
            letterSpacing != other.letterSpacing ||
            paragraphIndent != other.paragraphIndent ||
            isTextJustified != other.isTextJustified ||
            isBoldFont != other.isBoldFont ||
            fontWeight != other.fontWeight ||
            fontFamily != other.fontFamily ||
            customFontName != other.customFontName ||
            leftMargin != other.leftMargin ||
            rightMargin != other.rightMargin ||
            topMargin != other.topMargin ||
            bottomMargin != other.bottomMargin ||
            showHeader != other.showHeader ||
            showFooter != other.showFooter ||
            showHeaderDivider != other.showHeaderDivider ||
            showFooterDivider != other.showFooterDivider ||
            titleStyle != other.titleStyle ||
            tipConfig.tipFontSize != other.tipConfig.tipFontSize ||
            chineseConversion != other.chineseConversion ||
            enableIPadDualPage != other.enableIPadDualPage ||
            enableReplaceRule != other.enableReplaceRule ||
            removeSameTitle != other.removeSameTitle ||
            reSegment != other.reSegment ||
            (pageTurnMode == .scroll) != (other.pageTurnMode == .scroll)
    }
}
