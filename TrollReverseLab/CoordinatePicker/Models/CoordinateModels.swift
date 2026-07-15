import SwiftUI
import UIKit

// MARK: - Action Type

enum CoordinateActionType: String, Codable, CaseIterable {
    case tap = "tap"            // 单击
    case longPress = "longPress" // 长按
    case swipe = "swipe"        // 区间滑动
    case textInput = "textInput" // 文本输入
    case waitLoad = "waitLoad"  // 等待加载

    var displayName: String {
        switch self {
        case .tap: return "单击"
        case .longPress: return "长按"
        case .swipe: return "滑动"
        case .textInput: return "输入"
        case .waitLoad: return "等待"
        }
    }

    var iconName: String {
        switch self {
        case .tap: return "hand.tap"
        case .longPress: return "hand.tap.fill"
        case .swipe: return "arrow.left.and.right"
        case .textInput: return "keyboard"
        case .waitLoad: return "clock"
        }
    }

    var color: UIColor {
        switch self {
        case .tap: return UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        case .longPress: return UIColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
        case .swipe: return UIColor(red: 0.3, green: 0.8, blue: 0.5, alpha: 1.0)
        case .textInput: return UIColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 1.0)
        case .waitLoad: return UIColor(white: 0.5, alpha: 1.0)
        }
    }
}

// MARK: - Screen Coordinate

struct ScreenCoordinate: Identifiable, Codable {
    let id: UUID
    var x: CGFloat
    var y: CGFloat
    var actionType: CoordinateActionType
    var label: String             // 用户备注名称
    var endX: CGFloat?            // 滑动终点X
    var endY: CGFloat?            // 滑动终点Y
    var textContent: String?      // 文本输入内容
    var waitDuration: Double?     // 等待时长(秒)
    var tolerance: Int            // 像素容错范围 (默认15)
    var screenshotPath: String?   // 关联截图路径

    init(
        id: UUID = UUID(),
        x: CGFloat,
        y: CGFloat,
        actionType: CoordinateActionType,
        label: String = "",
        endX: CGFloat? = nil,
        endY: CGFloat? = nil,
        textContent: String? = nil,
        waitDuration: Double? = nil,
        tolerance: Int = 15,
        screenshotPath: String? = nil
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.actionType = actionType
        self.label = label
        self.endX = endX
        self.endY = endY
        self.textContent = textContent
        self.waitDuration = waitDuration
        self.tolerance = tolerance
        self.screenshotPath = screenshotPath
    }

    /// Tolerance-adjusted center point with random offset
    var adjustedPoint: CGPoint {
        let offsetX = CGFloat.random(in: -CGFloat(tolerance)...CGFloat(tolerance))
        let offsetY = CGFloat.random(in: -CGFloat(tolerance)...CGFloat(tolerance))
        return CGPoint(x: x + offsetX, y: y + offsetY)
    }

    /// AI-friendly summary string
    var aiSummary: String {
        var s = "[\(actionType.displayName)] \(label.isEmpty ? "未命名" : label) @ (\(Int(x)), \(Int(y)))"
        if actionType == .swipe, let ex = endX, let ey = endY {
            s += " -> (\(Int(ex)), \(Int(ey)))"
        }
        if actionType == .textInput, let text = textContent {
            s += " text=\"\(text)\""
        }
        if actionType == .waitLoad, let dur = waitDuration {
            s += " \(String(format: "%.1f", dur))s"
        }
        s += " ±\(tolerance)px"
        return s
    }
}

// MARK: - Coordinate Group (per App)

struct CoordinateGroup: Identifiable, Codable {
    let id: UUID
    var appName: String
    var bundleId: String
    var coordinates: [ScreenCoordinate]
    var createdAt: Date
    var updatedAt: Date
    var screenshotPath: String?  // 标注截图路径

    init(
        id: UUID = UUID(),
        appName: String,
        bundleId: String,
        coordinates: [ScreenCoordinate] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        screenshotPath: String? = nil
    ) {
        self.id = id
        self.appName = appName
        self.bundleId = bundleId
        self.coordinates = coordinates
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.screenshotPath = screenshotPath
    }

    var coordinateCount: Int { coordinates.count }

    /// Export as text for AI context
    var aiExport: String {
        var lines = ["App: \(appName) (\(bundleId))"]
        lines.append("坐标点位 (\(coordinateCount) 个):")
        for (i, coord) in coordinates.enumerated() {
            lines.append("  \(i + 1). \(coord.aiSummary)")
        }
        return lines.joined(separator: "\n")
    }
}
