import SwiftUI
import UIKit

// MARK: - Node Category

enum NodeCategory: String, Codable, CaseIterable {
    case appControl   // Blue - App底层操控
    case aiLogic      // Purple - AI规划逻辑
    case fileData     // Green - 文件/数据读写
    case network      // Orange - 网络/抓包接口
    case highRisk     // Red - 高风险注入、内存分析

    var displayName: String {
        switch self {
        case .appControl: return "App操控"
        case .aiLogic: return "AI逻辑"
        case .fileData: return "文件数据"
        case .network: return "网络接口"
        case .highRisk: return "高风险"
        }
    }

    var color: UIColor {
        switch self {
        case .appControl: return UIColor(red: 0.20, green: 0.48, blue: 0.96, alpha: 1.0)  // #337AF5
        case .aiLogic:    return UIColor(red: 0.58, green: 0.34, blue: 0.92, alpha: 1.0)  // #9456EA
        case .fileData:   return UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)  // #33C759
        case .network:    return UIColor(red: 0.95, green: 0.62, blue: 0.14, alpha: 1.0)  // #F29E24
        case .highRisk:   return UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1.0)  // #EB4236
        }
    }

    var swiftUIColor: Color {
        Color(self.color)
    }

    var gradientColors: [UIColor] {
        switch self {
        case .appControl:
            return [UIColor(red: 0.15, green: 0.40, blue: 0.90, alpha: 1.0),
                    UIColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 1.0)]
        case .aiLogic:
            return [UIColor(red: 0.48, green: 0.24, blue: 0.85, alpha: 1.0),
                    UIColor(red: 0.68, green: 0.44, blue: 0.99, alpha: 1.0)]
        case .fileData:
            return [UIColor(red: 0.12, green: 0.65, blue: 0.28, alpha: 1.0),
                    UIColor(red: 0.28, green: 0.88, blue: 0.42, alpha: 1.0)]
        case .network:
            return [UIColor(red: 0.85, green: 0.52, blue: 0.08, alpha: 1.0),
                    UIColor(red: 1.00, green: 0.72, blue: 0.20, alpha: 1.0)]
        case .highRisk:
            return [UIColor(red: 0.82, green: 0.16, blue: 0.12, alpha: 1.0),
                    UIColor(red: 1.00, green: 0.35, blue: 0.30, alpha: 1.0)]
        }
    }

    var iconSystemName: String {
        switch self {
        case .appControl: return "app.badge"
        case .aiLogic:    return "brain.head.profile"
        case .fileData:   return "doc.on.doc"
        case .network:    return "network"
        case .highRisk:   return "exclamationmark.triangle"
        }
    }

    var requiresRiskConfirmation: Bool {
        self == .highRisk
    }
}

// MARK: - Port

struct NodePort: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var isInput: Bool

    init(id: UUID = UUID(), label: String, isInput: Bool) {
        self.id = id
        self.label = label
        self.isInput = isInput
    }
}

// MARK: - Risk Level

enum RiskLevel: String, Codable {
    case none       // 无风险
    case low        // 低风险 (文件操作)
    case medium     // 中风险 (网络请求)
    case high       // 高风险 (内存/注入)
    case critical   // 极高风险 (Frida注入)

    var label: String {
        switch self {
        case .none: return ""
        case .low: return "低风险"
        case .medium: return "中风险"
        case .high: return "⚠️ 高风险"
        case .critical: return "🔴 极高风险"
        }
    }

    var requiresConfirmation: Bool {
        self == .high || self == .critical
    }
}
