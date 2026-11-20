import CoreGraphics
import Foundation

/// 阅读器点击区域动作类型（对标 Legado Android 九宫格自定义点击区域）
public enum TapZoneAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case nextPage = "下一页"
    case prevPage = "上一页"
    case toggleHUD = "呼出菜单"
    case nextChapter = "下一章"
    case prevChapter = "上一章"
    case toggleNightMode = "日/夜间切换"
    case none = "无操作"

    public var id: String {
        rawValue
    }

    public var shortLabel: String {
        switch self {
        case .nextPage: return "下一页"
        case .prevPage: return "上一页"
        case .toggleHUD: return "菜单"
        case .nextChapter: return "下一章"
        case .prevChapter: return "上一章"
        case .toggleNightMode: return "日/夜间"
        case .none: return "无"
        }
    }

    public var systemImage: String {
        switch self {
        case .nextPage: return "arrow.right"
        case .prevPage: return "arrow.left"
        case .toggleHUD: return "slider.horizontal.3"
        case .nextChapter: return "forward.end"
        case .prevChapter: return "backward.end"
        case .toggleNightMode: return "moon.stars"
        case .none: return "nosign"
        }
    }
}

/// 常用点击区域一键预设方案
public enum TapZonePreset: String, CaseIterable, Identifiable, Sendable {
    case standard = "标准左右"
    case rightHanded = "右手单手"
    case leftHanded = "左手单手"
    case fullScreenNext = "全屏下一页"

    public var id: String {
        rawValue
    }

    public var config: TapZoneConfig {
        switch self {
        case .standard:
            return .standard

        case .rightHanded:
            return .rightHanded

        case .leftHanded:
            return .leftHanded

        case .fullScreenNext:
            return .fullScreenNext
        }
    }
}

/// 3×3 九宫格点按区域自定义配置（行 0=上 / 1=中 / 2=下，列 0=左 / 1=中 / 2=右）
public struct TapZoneConfig: Equatable, Codable, Sendable {
    public var topLeft: TapZoneAction
    public var topCenter: TapZoneAction
    public var topRight: TapZoneAction
    public var middleLeft: TapZoneAction
    public var middleCenter: TapZoneAction
    public var middleRight: TapZoneAction
    public var bottomLeft: TapZoneAction
    public var bottomCenter: TapZoneAction
    public var bottomRight: TapZoneAction

    public init(
        topLeft: TapZoneAction = .prevPage,
        topCenter: TapZoneAction = .toggleHUD,
        topRight: TapZoneAction = .nextPage,
        middleLeft: TapZoneAction = .prevPage,
        middleCenter: TapZoneAction = .toggleHUD,
        middleRight: TapZoneAction = .nextPage,
        bottomLeft: TapZoneAction = .prevPage,
        bottomCenter: TapZoneAction = .nextPage,
        bottomRight: TapZoneAction = .nextPage) {
        self.topLeft = topLeft
        self.topCenter = topCenter
        self.topRight = topRight
        self.middleLeft = middleLeft
        self.middleCenter = middleCenter
        self.middleRight = middleRight
        self.bottomLeft = bottomLeft
        self.bottomCenter = bottomCenter
        self.bottomRight = bottomRight
    }

    /// 标准左右翻页（左列上一页 / 中间列菜单 / 右列下一页）
    public static let standard = TapZoneConfig(
        topLeft: .prevPage, topCenter: .toggleHUD, topRight: .nextPage,
        middleLeft: .prevPage, middleCenter: .toggleHUD, middleRight: .nextPage,
        bottomLeft: .prevPage, bottomCenter: .toggleHUD, bottomRight: .nextPage)

    /// 右手单手优化（中下与右列全部下一页，左上与左中上一页，中心菜单）
    public static let rightHanded = TapZoneConfig(
        topLeft: .prevPage, topCenter: .toggleHUD, topRight: .nextPage,
        middleLeft: .prevPage, middleCenter: .toggleHUD, middleRight: .nextPage,
        bottomLeft: .nextPage, bottomCenter: .nextPage, bottomRight: .nextPage)

    /// 左手单手模式（左列下一页，右列上一页，中心菜单）
    public static let leftHanded = TapZoneConfig(
        topLeft: .nextPage, topCenter: .toggleHUD, topRight: .prevPage,
        middleLeft: .nextPage, middleCenter: .toggleHUD, middleRight: .prevPage,
        bottomLeft: .nextPage, bottomCenter: .toggleHUD, bottomRight: .prevPage)

    /// 全屏点击下一页（仅正中呼出菜单，其余 8 区全部下一页）
    public static let fullScreenNext = TapZoneConfig(
        topLeft: .nextPage, topCenter: .nextPage, topRight: .nextPage,
        middleLeft: .nextPage, middleCenter: .toggleHUD, middleRight: .nextPage,
        bottomLeft: .nextPage, bottomCenter: .nextPage, bottomRight: .nextPage)

    public var hasMenuZone: Bool {
        allActions.contains(.toggleHUD)
    }

    public var allActions: [TapZoneAction] {
        [
            topLeft, topCenter, topRight,
            middleLeft, middleCenter, middleRight,
            bottomLeft, bottomCenter, bottomRight,
        ]
    }

    /// 根据归一化点击坐标 `(xRatio, yRatio) ∈ [0, 1]×[0, 1]` 解析对应动作
    public func action(atXRatio xRatio: CGFloat, yRatio: CGFloat) -> TapZoneAction {
        let col = xRatio < (1.0 / 3.0) ? 0 : (xRatio > (2.0 / 3.0) ? 2 : 1)
        let row = yRatio < (1.0 / 3.0) ? 0 : (yRatio > (2.0 / 3.0) ? 2 : 1)
        return action(row: row, col: col)
    }

    public func action(row: Int, col: Int) -> TapZoneAction {
        switch (row, col) {
        case (0, 0): return topLeft
        case (0, 1): return topCenter
        case (0, 2): return topRight
        case (1, 0): return middleLeft
        case (1, 1): return middleCenter
        case (1, 2): return middleRight
        case (2, 0): return bottomLeft
        case (2, 1): return bottomCenter
        default: return bottomRight
        }
    }

    public mutating func setAction(_ action: TapZoneAction, row: Int, col: Int) {
        switch (row, col) {
        case (0, 0): topLeft = action
        case (0, 1): topCenter = action
        case (0, 2): topRight = action
        case (1, 0): middleLeft = action
        case (1, 1): middleCenter = action
        case (1, 2): middleRight = action
        case (2, 0): bottomLeft = action
        case (2, 1): bottomCenter = action
        default: bottomRight = action
        }
    }
}
