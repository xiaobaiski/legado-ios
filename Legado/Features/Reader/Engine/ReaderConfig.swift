import SwiftUI
import UIKit

/// 阅读器内置配色主题（含自定义主题）
public enum ReaderTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case paper // 羊皮纸/暖黄
    case light // 晨曦白
    case eyeCare // 雅致护眼绿
    case warmCream // 宣纸米白
    case dark // 深空灰
    case black // OLED 纯黑
    case custom // 自定义配色

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
        case .custom: return "自定义"
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
        case .custom: return Color(red: 0.93, green: 0.93, blue: 0.91)
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
        case .custom: return Color(red: 0.12, green: 0.12, blue: 0.12)
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

/// 阅读器内置基础字体族（由用户从本机真实字体或本地文件自由选择）
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

    public func uiFont(size: CGFloat, isBold: Bool = false, weight: ReaderFontWeight? = nil) -> UIFont {
        let resolvedWeight = weight?.uiWeight ?? (isBold ? .semibold : .regular)
        return UIFont.systemFont(ofSize: size, weight: resolvedWeight)
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

/// 阅读器排版与交互偏好全局配置（对标 Legado Android 全套纯粹阅读设置）
public struct ReaderConfig: Equatable, Codable, Sendable {
    public var fontSize: CGFloat
    public var lineSpacing: CGFloat
    public var paragraphSpacing: CGFloat
    public var letterSpacing: CGFloat
    public var paragraphIndent: Int
    public var isTextJustified: Bool
    public var isBoldFont: Bool
    public var fontWeight: ReaderFontWeight
    public var fontFamily: ReaderFontFamily
    public var customFontName: String?
    public var customFontDisplayName: String?
    public var theme: ReaderTheme
    public var customBackgroundHex: String
    public var customTextHex: String
    public var eyeProtectionWarmth: Double
    public var pageTurnMode: PageTurnMode
    public var leftMargin: CGFloat
    public var rightMargin: CGFloat
    public var topMargin: CGFloat
    public var bottomMargin: CGFloat
    public var isHapticEnabled: Bool
    public var keepScreenOn: Bool
    public var keepScreenOnDuration: KeepScreenOnDuration
    public var followSystemBrightness: Bool
    public var customBrightness: Double
    public var showHeader: Bool
    public var showFooter: Bool
    public var showHeaderDivider: Bool
    public var showFooterDivider: Bool
    public var showStatusBar: Bool
    public var titleStyle: ChapterTitleStyleConfig
    public var tipConfig: HeaderFooterTipConfig
    public var progressBarBehavior: ProgressBarBehavior
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
        fontWeight: ReaderFontWeight = .regular,
        fontFamily: ReaderFontFamily = .system,
        customFontName: String? = nil,
        customFontDisplayName: String? = nil,
        theme: ReaderTheme = .paper,
        customBackgroundHex: String = "#ECECE7",
        customTextHex: String = "#1E1E1E",
        eyeProtectionWarmth: Double = 0.0,
        pageTurnMode: PageTurnMode = .cover,
        leftMargin: CGFloat = 18.0,
        rightMargin: CGFloat = 18.0,
        topMargin: CGFloat = 50.0,
        bottomMargin: CGFloat = 34.0,
        isHapticEnabled: Bool = true,
        keepScreenOn: Bool = true,
        keepScreenOnDuration: KeepScreenOnDuration = .always,
        followSystemBrightness: Bool = true,
        customBrightness: Double = 0.6,
        showHeader: Bool = true,
        showFooter: Bool = true,
        showHeaderDivider: Bool = false,
        showFooterDivider: Bool = false,
        showStatusBar: Bool = false,
        titleStyle: ChapterTitleStyleConfig = .default,
        tipConfig: HeaderFooterTipConfig = .default,
        progressBarBehavior: ProgressBarBehavior = .chapter,
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
        self.fontWeight = isBoldFont && fontWeight == .regular ? .semibold : fontWeight
        self.fontFamily = fontFamily
        self.customFontName = customFontName
        self.customFontDisplayName = customFontDisplayName
        self.theme = theme
        self.customBackgroundHex = customBackgroundHex
        self.customTextHex = customTextHex
        self.eyeProtectionWarmth = eyeProtectionWarmth
        self.pageTurnMode = pageTurnMode
        self.leftMargin = leftMargin
        self.rightMargin = rightMargin
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.isHapticEnabled = isHapticEnabled
        self.keepScreenOn = keepScreenOn
        self.keepScreenOnDuration = keepScreenOn ? keepScreenOnDuration : .system
        self.followSystemBrightness = followSystemBrightness
        self.customBrightness = customBrightness
        self.showHeader = showHeader
        self.showFooter = showFooter
        self.showHeaderDivider = showHeaderDivider
        self.showFooterDivider = showFooterDivider
        self.showStatusBar = showStatusBar
        self.titleStyle = titleStyle
        self.tipConfig = tipConfig
        self.progressBarBehavior = progressBarBehavior
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
        case isTextJustified, isBoldFont, fontWeight, fontFamily, customFontName, customFontDisplayName
        case theme, customBackgroundHex, customTextHex, eyeProtectionWarmth
        case pageTurnMode, leftMargin, rightMargin, horizontalMargin, topMargin, bottomMargin
        case isHapticEnabled, keepScreenOn, keepScreenOnDuration, followSystemBrightness, customBrightness
        case showHeader, showFooter, showHeaderDivider, showFooterDivider, showStatusBar
        case titleStyle, tipConfig, progressBarBehavior
        case tapToTurnPage, leftHandMode, volumeKeyPageTurn
        case autoPageMode, autoPageIntervalSeconds, autoScrollSpeed
        case chineseConversion, enableIPadDualPage
        case enableReplaceRule, removeSameTitle, reSegment
        case lastLightTheme, lastDarkTheme, tapZoneConfig
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let def = ReaderConfig.defaultConfig
        fontSize = try box.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? def.fontSize
        lineSpacing = try box.decodeIfPresent(CGFloat.self, forKey: .lineSpacing) ?? def.lineSpacing
        paragraphSpacing = try box.decodeIfPresent(CGFloat.self, forKey: .paragraphSpacing) ?? def.paragraphSpacing
        letterSpacing = try box.decodeIfPresent(CGFloat.self, forKey: .letterSpacing) ?? def.letterSpacing
        paragraphIndent = try box.decodeIfPresent(Int.self, forKey: .paragraphIndent) ?? def.paragraphIndent
        isTextJustified = try box.decodeIfPresent(Bool.self, forKey: .isTextJustified) ?? def.isTextJustified
        isBoldFont = try box.decodeIfPresent(Bool.self, forKey: .isBoldFont) ?? def.isBoldFont
        fontWeight = try box.decodeIfPresent(ReaderFontWeight.self, forKey: .fontWeight)
            ?? (isBoldFont ? .semibold : .regular)
        fontFamily = try box.decodeIfPresent(ReaderFontFamily.self, forKey: .fontFamily) ?? def.fontFamily
        customFontName = try box.decodeIfPresent(String.self, forKey: .customFontName)
        customFontDisplayName = try box.decodeIfPresent(String.self, forKey: .customFontDisplayName)
        theme = try box.decodeIfPresent(ReaderTheme.self, forKey: .theme) ?? def.theme
        customBackgroundHex = try box.decodeIfPresent(String.self, forKey: .customBackgroundHex)
            ?? def.customBackgroundHex
        customTextHex = try box.decodeIfPresent(String.self, forKey: .customTextHex) ?? def.customTextHex
        eyeProtectionWarmth = try box.decodeIfPresent(Double.self, forKey: .eyeProtectionWarmth) ?? 0.0
        pageTurnMode = try box.decodeIfPresent(PageTurnMode.self, forKey: .pageTurnMode) ?? def.pageTurnMode
        let legacyH = try box.decodeIfPresent(CGFloat.self, forKey: .horizontalMargin)
        leftMargin = try box.decodeIfPresent(CGFloat.self, forKey: .leftMargin) ?? legacyH ?? def.leftMargin
        rightMargin = try box.decodeIfPresent(CGFloat.self, forKey: .rightMargin) ?? legacyH ?? def.rightMargin
        topMargin = try box.decodeIfPresent(CGFloat.self, forKey: .topMargin) ?? def.topMargin
        bottomMargin = try box.decodeIfPresent(CGFloat.self, forKey: .bottomMargin) ?? def.bottomMargin
        isHapticEnabled = try box.decodeIfPresent(Bool.self, forKey: .isHapticEnabled) ?? def.isHapticEnabled
        keepScreenOn = try box.decodeIfPresent(Bool.self, forKey: .keepScreenOn) ?? def.keepScreenOn
        keepScreenOnDuration = try box.decodeIfPresent(KeepScreenOnDuration.self, forKey: .keepScreenOnDuration)
            ?? (keepScreenOn ? .always : .system)
        followSystemBrightness = try box.decodeIfPresent(Bool.self, forKey: .followSystemBrightness)
            ?? def.followSystemBrightness
        customBrightness = try box.decodeIfPresent(Double.self, forKey: .customBrightness) ?? def.customBrightness
        showHeader = try box.decodeIfPresent(Bool.self, forKey: .showHeader) ?? def.showHeader
        showFooter = try box.decodeIfPresent(Bool.self, forKey: .showFooter) ?? def.showFooter
        showHeaderDivider = try box.decodeIfPresent(Bool.self, forKey: .showHeaderDivider) ?? def.showHeaderDivider
        showFooterDivider = try box.decodeIfPresent(Bool.self, forKey: .showFooterDivider) ?? def.showFooterDivider
        showStatusBar = try box.decodeIfPresent(Bool.self, forKey: .showStatusBar) ?? def.showStatusBar
        titleStyle = try box.decodeIfPresent(ChapterTitleStyleConfig.self, forKey: .titleStyle) ?? .default
        tipConfig = try box.decodeIfPresent(HeaderFooterTipConfig.self, forKey: .tipConfig) ?? .default
        progressBarBehavior = try box.decodeIfPresent(ProgressBarBehavior.self, forKey: .progressBarBehavior)
            ?? .chapter
        tapToTurnPage = try box.decodeIfPresent(Bool.self, forKey: .tapToTurnPage) ?? def.tapToTurnPage
        leftHandMode = try box.decodeIfPresent(Bool.self, forKey: .leftHandMode) ?? def.leftHandMode
        volumeKeyPageTurn = try box.decodeIfPresent(Bool.self, forKey: .volumeKeyPageTurn) ?? def.volumeKeyPageTurn
        autoPageMode = try box.decodeIfPresent(AutoPageMode.self, forKey: .autoPageMode) ?? def.autoPageMode
        autoPageIntervalSeconds = try box.decodeIfPresent(Double.self, forKey: .autoPageIntervalSeconds)
            ?? def.autoPageIntervalSeconds
        autoScrollSpeed = try box.decodeIfPresent(Double.self, forKey: .autoScrollSpeed) ?? def.autoScrollSpeed
        chineseConversion = try box.decodeIfPresent(ChineseConversionMode.self, forKey: .chineseConversion)
            ?? def.chineseConversion
        enableIPadDualPage = try box.decodeIfPresent(Bool.self, forKey: .enableIPadDualPage) ?? def.enableIPadDualPage
        enableReplaceRule = try box.decodeIfPresent(Bool.self, forKey: .enableReplaceRule) ?? def.enableReplaceRule
        removeSameTitle = try box.decodeIfPresent(Bool.self, forKey: .removeSameTitle) ?? def.removeSameTitle
        reSegment = try box.decodeIfPresent(Bool.self, forKey: .reSegment) ?? def.reSegment
        lastLightTheme = try box.decodeIfPresent(ReaderTheme.self, forKey: .lastLightTheme) ?? def.lastLightTheme
        lastDarkTheme = try box.decodeIfPresent(ReaderTheme.self, forKey: .lastDarkTheme) ?? def.lastDarkTheme
        tapZoneConfig = try box.decodeIfPresent(TapZoneConfig.self, forKey: .tapZoneConfig)
            ?? (leftHandMode ? .leftHanded : .standard)
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(fontSize, forKey: .fontSize)
        try box.encode(lineSpacing, forKey: .lineSpacing)
        try box.encode(paragraphSpacing, forKey: .paragraphSpacing)
        try box.encode(letterSpacing, forKey: .letterSpacing)
        try box.encode(paragraphIndent, forKey: .paragraphIndent)
        try box.encode(isTextJustified, forKey: .isTextJustified)
        try box.encode(isBoldFont, forKey: .isBoldFont)
        try box.encode(fontWeight, forKey: .fontWeight)
        try box.encode(fontFamily, forKey: .fontFamily)
        try box.encodeIfPresent(customFontName, forKey: .customFontName)
        try box.encodeIfPresent(customFontDisplayName, forKey: .customFontDisplayName)
        try box.encode(theme, forKey: .theme)
        try box.encode(customBackgroundHex, forKey: .customBackgroundHex)
        try box.encode(customTextHex, forKey: .customTextHex)
        try box.encode(eyeProtectionWarmth, forKey: .eyeProtectionWarmth)
        try box.encode(pageTurnMode, forKey: .pageTurnMode)
        try box.encode(leftMargin, forKey: .leftMargin)
        try box.encode(rightMargin, forKey: .rightMargin)
        try box.encode(topMargin, forKey: .topMargin)
        try box.encode(bottomMargin, forKey: .bottomMargin)
        try box.encode(isHapticEnabled, forKey: .isHapticEnabled)
        try box.encode(keepScreenOn, forKey: .keepScreenOn)
        try box.encode(keepScreenOnDuration, forKey: .keepScreenOnDuration)
        try box.encode(followSystemBrightness, forKey: .followSystemBrightness)
        try box.encode(customBrightness, forKey: .customBrightness)
        try box.encode(showHeader, forKey: .showHeader)
        try box.encode(showFooter, forKey: .showFooter)
        try box.encode(showHeaderDivider, forKey: .showHeaderDivider)
        try box.encode(showFooterDivider, forKey: .showFooterDivider)
        try box.encode(showStatusBar, forKey: .showStatusBar)
        try box.encode(titleStyle, forKey: .titleStyle)
        try box.encode(tipConfig, forKey: .tipConfig)
        try box.encode(progressBarBehavior, forKey: .progressBarBehavior)
        try box.encode(tapToTurnPage, forKey: .tapToTurnPage)
        try box.encode(leftHandMode, forKey: .leftHandMode)
        try box.encode(volumeKeyPageTurn, forKey: .volumeKeyPageTurn)
        try box.encode(autoPageMode, forKey: .autoPageMode)
        try box.encode(autoPageIntervalSeconds, forKey: .autoPageIntervalSeconds)
        try box.encode(autoScrollSpeed, forKey: .autoScrollSpeed)
        try box.encode(chineseConversion, forKey: .chineseConversion)
        try box.encode(enableIPadDualPage, forKey: .enableIPadDualPage)
        try box.encode(enableReplaceRule, forKey: .enableReplaceRule)
        try box.encode(removeSameTitle, forKey: .removeSameTitle)
        try box.encode(reSegment, forKey: .reSegment)
        try box.encode(lastLightTheme, forKey: .lastLightTheme)
        try box.encode(lastDarkTheme, forKey: .lastDarkTheme)
        try box.encode(tapZoneConfig, forKey: .tapZoneConfig)
    }
}
