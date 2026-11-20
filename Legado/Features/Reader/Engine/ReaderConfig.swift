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

/// 阅读器字体族
public enum ReaderFontFamily: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "系统默认"
    case songti = "宋体"
    case kaiti = "楷体"
    case heiti = "黑体"

    public var id: String {
        rawValue
    }

    public func uiFont(size: CGFloat, isBold: Bool = false) -> UIFont {
        switch self {
        case .system:
            return UIFont.systemFont(ofSize: size, weight: isBold ? .semibold : .regular)

        case .songti:
            let name = isBold ? "STSongti-SC-Bold" : "Songti SC"
            return UIFont(name: name, size: size)
                ?? UIFont(name: "Songti SC", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: isBold ? .semibold : .regular)

        case .kaiti:
            let name = isBold ? "STKaitiSC-Bold" : "Kaiti SC"
            return UIFont(name: name, size: size)
                ?? UIFont(name: "Kaiti SC", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: isBold ? .semibold : .regular)

        case .heiti:
            let name = isBold ? "PingFangSC-Semibold" : "PingFangSC-Regular"
            return UIFont(name: name, size: size)
                ?? UIFont.systemFont(ofSize: size, weight: isBold ? .semibold : .regular)
        }
    }

    public func swiftUIFont(size: CGFloat, isBold: Bool = false) -> Font {
        Font(uiFont(size: size, isBold: isBold))
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
    public var horizontalMargin: CGFloat
    public var topMargin: CGFloat
    public var bottomMargin: CGFloat
    public var isHapticEnabled: Bool
    public var keepScreenOn: Bool
    public var followSystemBrightness: Bool
    public var customBrightness: Double
    public var showHeader: Bool
    public var showFooter: Bool
    public var showStatusBar: Bool
    public var tapToTurnPage: Bool
    public var leftHandMode: Bool
    public var volumeKeyPageTurn: Bool
    public var autoPageIntervalSeconds: Double
    public var chineseConversion: ChineseConversionMode
    public var enableIPadDualPage: Bool

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
        horizontalMargin: CGFloat = 18.0,
        topMargin: CGFloat = 50.0,
        bottomMargin: CGFloat = 42.0,
        isHapticEnabled: Bool = true,
        keepScreenOn: Bool = true,
        followSystemBrightness: Bool = true,
        customBrightness: Double = 0.6,
        showHeader: Bool = true,
        showFooter: Bool = true,
        showStatusBar: Bool = false,
        tapToTurnPage: Bool = true,
        leftHandMode: Bool = false,
        volumeKeyPageTurn: Bool = true,
        autoPageIntervalSeconds: Double = 8.0,
        chineseConversion: ChineseConversionMode = .none,
        enableIPadDualPage: Bool = true) {
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
        self.horizontalMargin = horizontalMargin
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.isHapticEnabled = isHapticEnabled
        self.keepScreenOn = keepScreenOn
        self.followSystemBrightness = followSystemBrightness
        self.customBrightness = customBrightness
        self.showHeader = showHeader
        self.showFooter = showFooter
        self.showStatusBar = showStatusBar
        self.tapToTurnPage = tapToTurnPage
        self.leftHandMode = leftHandMode
        self.volumeKeyPageTurn = volumeKeyPageTurn
        self.autoPageIntervalSeconds = autoPageIntervalSeconds
        self.chineseConversion = chineseConversion
        self.enableIPadDualPage = enableIPadDualPage
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
        self.horizontalMargin = try container.decodeIfPresent(CGFloat.self, forKey: .horizontalMargin)
            ?? defaults.horizontalMargin
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
        self.showStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showStatusBar) ?? defaults.showStatusBar
        self.tapToTurnPage = try container.decodeIfPresent(Bool.self, forKey: .tapToTurnPage) ?? defaults.tapToTurnPage
        self.leftHandMode = try container.decodeIfPresent(Bool.self, forKey: .leftHandMode) ?? defaults.leftHandMode
        self.volumeKeyPageTurn = try container.decodeIfPresent(Bool.self, forKey: .volumeKeyPageTurn)
            ?? defaults.volumeKeyPageTurn
        self.autoPageIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .autoPageIntervalSeconds)
            ?? defaults.autoPageIntervalSeconds
        self.chineseConversion = try container.decodeIfPresent(ChineseConversionMode.self, forKey: .chineseConversion)
            ?? defaults.chineseConversion
        self.enableIPadDualPage = try container.decodeIfPresent(Bool.self, forKey: .enableIPadDualPage)
            ?? defaults.enableIPadDualPage
    }

    public static let defaultConfig = ReaderConfig()

    /// 判断给定画布尺寸下是否启用 iPad 双页并排阅读
    public func isDualPageActive(for bounds: CGRect) -> Bool {
        enableIPadDualPage && pageTurnMode != .scroll && bounds.width >= 760
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
            horizontalMargin != other.horizontalMargin ||
            topMargin != other.topMargin ||
            bottomMargin != other.bottomMargin ||
            chineseConversion != other.chineseConversion ||
            enableIPadDualPage != other.enableIPadDualPage ||
            (pageTurnMode == .scroll) != (other.pageTurnMode == .scroll)
    }
}

/// 阅读配置本地持久化存储 (UserDefaults)
public enum ReaderConfigStore {
    public static let storageKey = "legado_reader_config_v1"

    public static func load(defaults: UserDefaults = .standard) -> ReaderConfig {
        guard let data = defaults.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(ReaderConfig.self, from: data) else {
            return .defaultConfig
        }
        return config
    }

    public static func save(_ config: ReaderConfig, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: storageKey)
        }
    }

    @discardableResult
    public static func reset(defaults: UserDefaults = .standard) -> ReaderConfig {
        defaults.removeObject(forKey: storageKey)
        return .defaultConfig
    }

    /// 全局震动开关快捷读取（供各模块视图统一判断是否触发触感反馈）
    public static var isHapticEnabled: Bool {
        load().isHapticEnabled
    }
}
