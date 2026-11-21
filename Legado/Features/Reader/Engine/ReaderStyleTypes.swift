import CoreGraphics
import SwiftUI
import UIKit

/// 正文章节大标题对齐与显隐模式（对标 Legado `titleMode`）
public enum ChapterTitleAlignment: String, CaseIterable, Identifiable, Codable, Sendable {
    case left = "居左"
    case center = "居中"
    case hidden = "隐藏"

    public var id: String {
        rawValue
    }
}

/// 正文章节大标题排版配置（对标 Legado `TipConfigDialog` 标题样式设置）
public struct ChapterTitleStyleConfig: Equatable, Codable, Sendable {
    public var alignment: ChapterTitleAlignment
    public var sizeDelta: CGFloat
    public var topSpacing: CGFloat
    public var bottomSpacing: CGFloat

    public init(
        alignment: ChapterTitleAlignment = .left,
        sizeDelta: CGFloat = 4,
        topSpacing: CGFloat = 6,
        bottomSpacing: CGFloat = 14) {
        self.alignment = alignment
        self.sizeDelta = sizeDelta
        self.topSpacing = topSpacing
        self.bottomSpacing = bottomSpacing
    }

    public static let `default` = ChapterTitleStyleConfig()
}

/// 页眉 / 页脚单槽位可展示的信息项（对标 Legado `ReadTipConfig`）
public enum ReadTipItem: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "无"
    case bookTitle = "书名"
    case chapterTitle = "章节名"
    case time = "当前时间"
    case battery = "电池电量"
    case pageAndTotal = "本章页码"
    case chapterProgress = "本章进度"
    case bookProgress = "全书进度"
    case chapterIndex = "章节序号"
    case remainingPages = "本章余页"

    public var id: String {
        rawValue
    }
}

/// 页眉 / 页脚 6 槽位自定义信息栏配置（对标 Legado `ReadTipConfig`）
public struct HeaderFooterTipConfig: Equatable, Codable, Sendable {
    public var headerLeft: ReadTipItem
    public var headerCenter: ReadTipItem
    public var headerRight: ReadTipItem
    public var footerLeft: ReadTipItem
    public var footerCenter: ReadTipItem
    public var footerRight: ReadTipItem
    public var tipFontSize: CGFloat

    public init(
        headerLeft: ReadTipItem = .chapterTitle,
        headerCenter: ReadTipItem = .none,
        headerRight: ReadTipItem = .time,
        footerLeft: ReadTipItem = .pageAndTotal,
        footerCenter: ReadTipItem = .none,
        footerRight: ReadTipItem = .bookProgress,
        tipFontSize: CGFloat = 11) {
        self.headerLeft = headerLeft
        self.headerCenter = headerCenter
        self.headerRight = headerRight
        self.footerLeft = footerLeft
        self.footerCenter = footerCenter
        self.footerRight = footerRight
        self.tipFontSize = tipFontSize
    }

    public static let `default` = HeaderFooterTipConfig()
}

/// 精细字体字重档位（对标 Legado 字体粗细调节）
public enum ReaderFontWeight: String, CaseIterable, Identifiable, Codable, Sendable {
    case light = "细体"
    case regular = "常规"
    case medium = "中等"
    case semibold = "半粗"
    case bold = "粗体"

    public var id: String {
        rawValue
    }

    public var uiWeight: UIFont.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    public var isBoldLike: Bool {
        self == .semibold || self == .bold
    }
}

/// 屏幕常亮时长选项（对标 Legado `keep_light`）
public enum KeepScreenOnDuration: Int, CaseIterable, Identifiable, Codable, Sendable {
    case system = 0
    case minutes5 = 5
    case minutes10 = 10
    case minutes30 = 30
    case always = -1

    public var id: Int {
        rawValue
    }

    public var title: String {
        switch self {
        case .system: return "跟随系统"
        case .minutes5: return "5 分钟"
        case .minutes10: return "10 分钟"
        case .minutes30: return "30 分钟"
        case .always: return "始终常亮"
        }
    }
}

/// HUD 底部进度条拖动行为（对标 Legado `progressBarBehavior`）
public enum ProgressBarBehavior: String, CaseIterable, Identifiable, Codable, Sendable {
    case chapter = "按章节跳转"
    case page = "按本章页码跳转"

    public var id: String {
        rawValue
    }
}

/// 十六进制 RGB 颜色编解码工具（支持自定义阅读主题背景与正文配色）
public enum HexColorCodec {
    public static func color(from hex: String, fallback: Color) -> Color {
        guard let comps = rgbComponents(from: hex) else { return fallback }
        return Color(red: comps.red, green: comps.green, blue: comps.blue)
    }

    public static func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#F5EDD8"
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(min(max(red, 0), 1) * 255)),
            Int(round(min(max(green, 0), 1) * 255)),
            Int(round(min(max(blue, 0), 1) * 255)))
    }

    /// 依据相对亮度判断背景色是否属于深色主题
    public static func isDarkColor(hex: String) -> Bool {
        guard let comps = rgbComponents(from: hex) else { return false }
        let luminance = 0.299 * comps.red + 0.587 * comps.green + 0.114 * comps.blue
        return luminance < 0.48
    }

    private static func rgbComponents(from hex: String) -> (red: Double, green: Double, blue: Double)? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return (red, green, blue)
    }
}
