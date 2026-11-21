import SwiftUI
import UIKit

/// 阅读器内置配色主题
public enum ReaderTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case paper // 羊皮纸/暖黄
    case light // 晨曦白
    case eyeCare // 雅致护眼绿
    case warmCream // 宣纸米白
    case dark // 深空灰
    case black // OLED 纯黑

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .paper: return "羊皮纸"
        case .light: return "晨曦白"
        case .eyeCare: return "护眼绿"
        case .warmCream: return "宣纸米"
        case .dark: return "深空灰"
        case .black: return "极夜黑"
        }
    }

    public var backgroundColor: Color {
        switch self {
        case .paper: return Color(red: 0.96, green: 0.93, blue: 0.86)
        case .light: return Color(red: 0.98, green: 0.98, blue: 0.99)
        case .eyeCare: return Color(red: 0.90, green: 0.94, blue: 0.90)
        case .warmCream: return Color(red: 0.97, green: 0.96, blue: 0.92)
        case .dark: return Color(red: 0.14, green: 0.14, blue: 0.16)
        case .black: return Color.black
        }
    }

    public var textColor: Color {
        switch self {
        case .paper: return Color(red: 0.18, green: 0.15, blue: 0.10)
        case .light: return Color(red: 0.12, green: 0.12, blue: 0.14)
        case .eyeCare: return Color(red: 0.14, green: 0.22, blue: 0.14)
        case .warmCream: return Color(red: 0.20, green: 0.18, blue: 0.15)
        case .dark: return Color(red: 0.82, green: 0.82, blue: 0.85)
        case .black: return Color(red: 0.65, green: 0.65, blue: 0.68)
        }
    }

    public var isDark: Bool {
        self == .dark || self == .black
    }
}

/// 全局应用外观模式（跟随系统 / 日间模式 / 夜间模式）
public enum AppAppearanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "跟随系统"
    case light = "日间模式"
    case dark = "夜间模式"

    public static let storageKey = "legado_app_appearance_mode"

    public var id: String {
        rawValue
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 阅读器内置基础字体族（取消 iOS 未预装的无效宋体/楷体选项，由用户从本机真实字体或本地文件自由选择）
public enum ReaderFontFamily: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "系统默认"

    public var id: String {
        rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? Self.system.rawValue
        self = ReaderFontFamily(rawValue: raw) ?? .system
    }

    public func uiFont(size: CGFloat, isBold: Bool = false) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: isBold ? .semibold : .regular)
    }

    public func swiftUIFont(size: CGFloat, isBold: Bool = false) -> Font {
        Font(uiFont(size: size, isBold: isBold))
    }
}

/// 自动翻页方式（对标 Legado：支持定时翻页与平滑上下滚动自动阅读）
public enum AutoPageMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case paged = "定时翻页"
    case smoothScroll = "上下滚动"

    public var id: String {
        rawValue
    }
}

/// 翻页动效模式
public enum PageTurnMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case curl = "仿真"
    case cover = "覆盖"
    case slide = "滑动"
    case scroll = "连续滚动"
    case none = "无动画"

    public var id: String {
        rawValue
    }
}

/// 繁简转换模式 (对标 Legado 繁简转换)
public enum ChineseConversionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "原文"
    case toSimplified = "转为简体"
    case toTraditional = "转为繁体"

    public var id: String {
        rawValue
    }

    public func convert(_ text: String) -> String {
        switch self {
        case .none:
            return text

        case .toSimplified:
            return text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text

        case .toTraditional:
            return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
        }
    }
}

/// 阅读器排版与交互偏好全局配置
public struct ReaderConfig: Equatable, Codable, Sendable {
    public var fontSize: CGFloat
    public var lineSpacing: CGFloat
    public var paragraphSpacing: CGFloat
    public var letterSpacing: CGFloat
    public var paragraphIndent: Int
    public var isTextJustified: Bool
    public var isBoldFont: Bool
    public var fontFamily: ReaderFontFamily
    public var customFontName: String?
    public var customFontDisplayName: String?
    public var theme: ReaderTheme
    public var pageTurnMode: PageTurnMode
    public var leftMargin: CGFloat
    public var rightMargin: CGFloat
    public var topMargin: CGFloat
    public var bottomMargin: CGFloat
    public var isHapticEnabled: Bool
    public var keepScreenOn: Bool
    public var followSystemBrightness: Bool
    public var customBrightness: Double
    public var showHeader: Bool
    public var showFooter: Bool
    public var showHeaderDivider: Bool
    public var showFooterDivider: Bool
    public var showStatusBar: Bool
    public var tapToTurnPage: Bool
    public var leftHandMode: Bool
    public var volumeKeyPageTurn: Bool
    public var autoPageMode: AutoPageMode
    public var autoPageIntervalSeconds: Double
    public var autoScrollSpeed: Double
    public var chineseConversion: ChineseConversionMode
    public var enableIPadDualPage: Bool
    public var enableReplaceRule: Bool
    public var removeSameTitle: Bool
    public var reSegment: Bool
    public var lastLightTheme: ReaderTheme
    public var lastDarkTheme: ReaderTheme
    public var tapZoneConfig: TapZoneConfig

    /// 兼容旧接口的水平边距便捷属性（同步读写左右边距）
    public var horizontalMargin: CGFloat {
        get { (leftMargin + rightMargin) / 2 }
        set {
            leftMargin = newValue
            rightMargin = newValue
        }
    }

    public init(
        fontSize: CGFloat = 19.0,
        lineSpacing: CGFloat = 8.0,
        paragraphSpacing: CGFloat = 12.0,
        letterSpacing: CGFloat = 0.0,
        paragraphIndent: Int = 2,
        isTextJustified: Bool = true,
        isBoldFont: Bool = false,
        fontFamily: ReaderFontFamily = .system,
        customFontName: String? = nil,
        customFontDisplayName: String? = nil,
        theme: ReaderTheme = .paper,
        pageTurnMode: PageTurnMode = .cover,
        leftMargin: CGFloat = 18.0,
        rightMargin: CGFloat = 18.0,
        topMargin: CGFloat = 50.0,
        bottomMargin: CGFloat = 34.0,
        isHapticEnabled: Bool = true,
        keepScreenOn: Bool = true,
        followSystemBrightness: Bool = true,
        customBrightness: Double = 0.6,
        showHeader: Bool = true,
        showFooter: Bool = true,
        showHeaderDivider: Bool = false,
        showFooterDivider: Bool = false,
        showStatusBar: Bool = false,
        tapToTurnPage: Bool = true,
        leftHandMode: Bool = false,
        volumeKeyPageTurn: Bool = true,
        autoPageMode: AutoPageMode = .paged,
        autoPageIntervalSeconds: Double = 8.0,
        autoScrollSpeed: Double = 45.0,
        chineseConversion: ChineseConversionMode = .none,
        enableIPadDualPage: Bool = true,
        enableReplaceRule: Bool = true,
        removeSameTitle: Bool = true,
        reSegment: Bool = false,
        lastLightTheme: ReaderTheme = .paper,
        lastDarkTheme: ReaderTheme = .dark,
        tapZoneConfig: TapZoneConfig = .standard) {
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.letterSpacing = letterSpacing
        self.paragraphIndent = paragraphIndent
        self.isTextJustified = isTextJustified
        self.isBoldFont = isBoldFont
        self.fontFamily = fontFamily
        self.customFontName = customFontName
        self.customFontDisplayName = customFontDisplayName
        self.theme = theme
        self.pageTurnMode = pageTurnMode
        self.leftMargin = leftMargin
        self.rightMargin = rightMargin
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.isHapticEnabled = isHapticEnabled
        self.keepScreenOn = keepScreenOn
        self.followSystemBrightness = followSystemBrightness
        self.customBrightness = customBrightness
        self.showHeader = showHeader
        self.showFooter = showFooter
        self.showHeaderDivider = showHeaderDivider
        self.showFooterDivider = showFooterDivider
        self.showStatusBar = showStatusBar
        self.tapToTurnPage = tapToTurnPage
        self.leftHandMode = leftHandMode
        self.volumeKeyPageTurn = volumeKeyPageTurn
        self.autoPageMode = autoPageMode
        self.autoPageIntervalSeconds = autoPageIntervalSeconds
        self.autoScrollSpeed = autoScrollSpeed
        self.chineseConversion = chineseConversion
        self.enableIPadDualPage = enableIPadDualPage
        self.enableReplaceRule = enableReplaceRule
        self.removeSameTitle = removeSameTitle
        self.reSegment = reSegment
        self.lastLightTheme = lastLightTheme
        self.lastDarkTheme = lastDarkTheme
        self.tapZoneConfig = tapZoneConfig
    }

    private enum CodingKeys: String, CodingKey {
        case fontSize, lineSpacing, paragraphSpacing, letterSpacing, paragraphIndent
        case isTextJustified, isBoldFont, fontFamily, customFontName, customFontDisplayName
        case theme, pageTurnMode, leftMargin, rightMargin, horizontalMargin, topMargin, bottomMargin
        case isHapticEnabled, keepScreenOn, followSystemBrightness, customBrightness
        case showHeader, showFooter, showHeaderDivider, showFooterDivider, showStatusBar
        case tapToTurnPage, leftHandMode, volumeKeyPageTurn
        case autoPageMode, autoPageIntervalSeconds, autoScrollSpeed
        case chineseConversion, enableIPadDualPage
        case enableReplaceRule, removeSameTitle, reSegment
        case lastLightTheme, lastDarkTheme, tapZoneConfig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ReaderConfig.defaultConfig
        self.fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? defaults.fontSize
        self.lineSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .lineSpacing) ?? defaults.lineSpacing
        self.paragraphSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .paragraphSpacing)
            ?? defaults.paragraphSpacing
        self.letterSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .letterSpacing)
            ?? defaults.letterSpacing
        self.paragraphIndent = try container.decodeIfPresent(Int.self, forKey: .paragraphIndent)
            ?? defaults.paragraphIndent
        self.isTextJustified = try container.decodeIfPresent(Bool.self, forKey: .isTextJustified)
            ?? defaults.isTextJustified
        self.isBoldFont = try container.decodeIfPresent(Bool.self, forKey: .isBoldFont) ?? defaults.isBoldFont
        self.fontFamily = try container.decodeIfPresent(ReaderFontFamily.self, forKey: .fontFamily)
            ?? defaults.fontFamily
        self.customFontName = try container.decodeIfPresent(String.self, forKey: .customFontName)
        self.customFontDisplayName = try container.decodeIfPresent(String.self, forKey: .customFontDisplayName)
        self.theme = try container.decodeIfPresent(ReaderTheme.self, forKey: .theme) ?? defaults.theme
        self.pageTurnMode = try container.decodeIfPresent(PageTurnMode.self, forKey: .pageTurnMode)
            ?? defaults.pageTurnMode
        let legacyHorizontal = try container.decodeIfPresent(CGFloat.self, forKey: .horizontalMargin)
        self.leftMargin = try container.decodeIfPresent(CGFloat.self, forKey: .leftMargin)
            ?? legacyHorizontal
            ?? defaults.leftMargin
        self.rightMargin = try container.decodeIfPresent(CGFloat.self, forKey: .rightMargin)
            ?? legacyHorizontal
            ?? defaults.rightMargin
        self.topMargin = try container.decodeIfPresent(CGFloat.self, forKey: .topMargin) ?? defaults.topMargin
        self.bottomMargin = try container.decodeIfPresent(CGFloat.self, forKey: .bottomMargin) ?? defaults.bottomMargin
        self.isHapticEnabled = try container.decodeIfPresent(Bool.self, forKey: .isHapticEnabled)
            ?? defaults.isHapticEnabled
        self.keepScreenOn = try container.decodeIfPresent(Bool.self, forKey: .keepScreenOn) ?? defaults.keepScreenOn
        self.followSystemBrightness = try container.decodeIfPresent(Bool.self, forKey: .followSystemBrightness)
            ?? defaults.followSystemBrightness
        self.customBrightness = try container.decodeIfPresent(Double.self, forKey: .customBrightness)
            ?? defaults.customBrightness
        self.showHeader = try container.decodeIfPresent(Bool.self, forKey: .showHeader) ?? defaults.showHeader
        self.showFooter = try container.decodeIfPresent(Bool.self, forKey: .showFooter) ?? defaults.showFooter
        self.showHeaderDivider = try container.decodeIfPresent(Bool.self, forKey: .showHeaderDivider)
            ?? defaults.showHeaderDivider
        self.showFooterDivider = try container.decodeIfPresent(Bool.self, forKey: .showFooterDivider)
            ?? defaults.showFooterDivider
        self.showStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showStatusBar) ?? defaults.showStatusBar
        self.tapToTurnPage = try container.decodeIfPresent(Bool.self, forKey: .tapToTurnPage) ?? defaults.tapToTurnPage
        self.leftHandMode = try container.decodeIfPresent(Bool.self, forKey: .leftHandMode) ?? defaults.leftHandMode
        self.volumeKeyPageTurn = try container.decodeIfPresent(Bool.self, forKey: .volumeKeyPageTurn)
            ?? defaults.volumeKeyPageTurn
        self.autoPageMode = try container.decodeIfPresent(AutoPageMode.self, forKey: .autoPageMode)
            ?? defaults.autoPageMode
        self.autoPageIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .autoPageIntervalSeconds)
            ?? defaults.autoPageIntervalSeconds
        self.autoScrollSpeed = try container.decodeIfPresent(Double.self, forKey: .autoScrollSpeed)
            ?? defaults.autoScrollSpeed
        self.chineseConversion = try container.decodeIfPresent(ChineseConversionMode.self, forKey: .chineseConversion)
            ?? defaults.chineseConversion
        self.enableIPadDualPage = try container.decodeIfPresent(Bool.self, forKey: .enableIPadDualPage)
            ?? defaults.enableIPadDualPage
        self.enableReplaceRule = try container.decodeIfPresent(Bool.self, forKey: .enableReplaceRule)
            ?? defaults.enableReplaceRule
        self.removeSameTitle = try container.decodeIfPresent(Bool.self, forKey: .removeSameTitle)
            ?? defaults.removeSameTitle
        self.reSegment = try container.decodeIfPresent(Bool.self, forKey: .reSegment)
            ?? defaults.reSegment
        self.lastLightTheme = try container.decodeIfPresent(ReaderTheme.self, forKey: .lastLightTheme)
            ?? defaults.lastLightTheme
        self.lastDarkTheme = try container.decodeIfPresent(ReaderTheme.self, forKey: .lastDarkTheme)
            ?? defaults.lastDarkTheme
        let decodedTapZone = try container.decodeIfPresent(TapZoneConfig.self, forKey: .tapZoneConfig)
        self.tapZoneConfig = decodedTapZone ?? (self.leftHandMode ? .leftHanded : .standard)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(lineSpacing, forKey: .lineSpacing)
        try container.encode(paragraphSpacing, forKey: .paragraphSpacing)
        try container.encode(letterSpacing, forKey: .letterSpacing)
        try container.encode(paragraphIndent, forKey: .paragraphIndent)
        try container.encode(isTextJustified, forKey: .isTextJustified)
        try container.encode(isBoldFont, forKey: .isBoldFont)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encodeIfPresent(customFontName, forKey: .customFontName)
        try container.encodeIfPresent(customFontDisplayName, forKey: .customFontDisplayName)
        try container.encode(theme, forKey: .theme)
        try container.encode(pageTurnMode, forKey: .pageTurnMode)
        try container.encode(leftMargin, forKey: .leftMargin)
        try container.encode(rightMargin, forKey: .rightMargin)
        try container.encode(topMargin, forKey: .topMargin)
        try container.encode(bottomMargin, forKey: .bottomMargin)
        try container.encode(isHapticEnabled, forKey: .isHapticEnabled)
        try container.encode(keepScreenOn, forKey: .keepScreenOn)
        try container.encode(followSystemBrightness, forKey: .followSystemBrightness)
        try container.encode(customBrightness, forKey: .customBrightness)
        try container.encode(showHeader, forKey: .showHeader)
        try container.encode(showFooter, forKey: .showFooter)
        try container.encode(showHeaderDivider, forKey: .showHeaderDivider)
        try container.encode(showFooterDivider, forKey: .showFooterDivider)
        try container.encode(showStatusBar, forKey: .showStatusBar)
        try container.encode(tapToTurnPage, forKey: .tapToTurnPage)
        try container.encode(leftHandMode, forKey: .leftHandMode)
        try container.encode(volumeKeyPageTurn, forKey: .volumeKeyPageTurn)
        try container.encode(autoPageMode, forKey: .autoPageMode)
        try container.encode(autoPageIntervalSeconds, forKey: .autoPageIntervalSeconds)
        try container.encode(autoScrollSpeed, forKey: .autoScrollSpeed)
        try container.encode(chineseConversion, forKey: .chineseConversion)
        try container.encode(enableIPadDualPage, forKey: .enableIPadDualPage)
        try container.encode(enableReplaceRule, forKey: .enableReplaceRule)
        try container.encode(removeSameTitle, forKey: .removeSameTitle)
        try container.encode(reSegment, forKey: .reSegment)
        try container.encode(lastLightTheme, forKey: .lastLightTheme)
        try container.encode(lastDarkTheme, forKey: .lastDarkTheme)
        try container.encode(tapZoneConfig, forKey: .tapZoneConfig)
    }

    public static let defaultConfig = ReaderConfig()

    /// 一键切换阅读器日间 / 夜间模式（自动记忆上一次日间与夜间主题配色）
    public mutating func toggleNightMode() {
        if theme.isDark {
            lastDarkTheme = theme
            theme = lastLightTheme.isDark ? .paper : lastLightTheme
        } else {
            lastLightTheme = theme
            theme = lastDarkTheme.isDark ? lastDarkTheme : .dark
        }
    }

    /// 切换主题并同步更新日间/夜间记忆主题
    public mutating func applyTheme(_ newTheme: ReaderTheme) {
        theme = newTheme
        if newTheme.isDark {
            lastDarkTheme = newTheme
        } else {
            lastLightTheme = newTheme
        }
    }

    /// 判断给定画布尺寸下是否启用 iPad 横屏大屏双页并排阅读（对标 Apple Books：横屏双页、竖屏居中单页）
    public func isDualPageActive(for bounds: CGRect) -> Bool {
        enableIPadDualPage && pageTurnMode != .scroll && bounds.width >= 820 && bounds.width >= bounds.height
    }

    /// 解析当前最终使用的 UIFont（优先自定义本地字体，失败回退内置字体）
    public func resolvedUIFont(size: CGFloat? = nil, isBold: Bool? = nil) -> UIFont {
        let targetSize = size ?? fontSize
        let targetBold = isBold ?? isBoldFont
        if let customName = customFontName, !customName.isEmpty,
           let baseFont = UIFont(name: customName, size: targetSize) {
            if targetBold,
               let boldDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: boldDescriptor, size: targetSize)
            }
            return baseFont
        }
        return fontFamily.uiFont(size: targetSize, isBold: targetBold)
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
            chineseConversion != other.chineseConversion ||
            enableIPadDualPage != other.enableIPadDualPage ||
            enableReplaceRule != other.enableReplaceRule ||
            removeSameTitle != other.removeSameTitle ||
            reSegment != other.reSegment ||
            (pageTurnMode == .scroll) != (other.pageTurnMode == .scroll)
    }
}

/// 阅读配置本地持久化存储 (UserDefaults + 内存热缓存，消除高频触感/排版读取的重复 JSON 反序列化)
public enum ReaderConfigStore {
    public static let storageKey = "legado_reader_config_v1"
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cachedStandardConfig: ReaderConfig?

    public static func load(defaults: UserDefaults = .standard) -> ReaderConfig {
        let isStandard = defaults === UserDefaults.standard
        if isStandard {
            cacheLock.lock()
            if let cached = cachedStandardConfig {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()
        }

        let decoded: ReaderConfig
        if let data = defaults.data(forKey: storageKey),
           let config = try? JSONDecoder().decode(ReaderConfig.self, from: data) {
            decoded = config
        } else {
            decoded = .defaultConfig
        }

        if isStandard {
            cacheLock.lock()
            cachedStandardConfig = decoded
            cacheLock.unlock()
        }
        return decoded
    }

    public static func save(_ config: ReaderConfig, defaults: UserDefaults = .standard) {
        if defaults === UserDefaults.standard {
            cacheLock.lock()
            cachedStandardConfig = config
            cacheLock.unlock()
        }
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: storageKey)
        }
    }

    @discardableResult
    public static func reset(defaults: UserDefaults = .standard) -> ReaderConfig {
        if defaults === UserDefaults.standard {
            cacheLock.lock()
            cachedStandardConfig = .defaultConfig
            cacheLock.unlock()
        }
        defaults.removeObject(forKey: storageKey)
        return .defaultConfig
    }

    /// 全局震动开关快捷读取（直接命中内存缓存，零磁盘/JSON 开销）
    public static var isHapticEnabled: Bool {
        load().isHapticEnabled
    }
}
