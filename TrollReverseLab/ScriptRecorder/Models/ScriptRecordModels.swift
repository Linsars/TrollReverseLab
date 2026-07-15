import Foundation
import CoreGraphics

// MARK: - Recorded Action Type

/// Types of user interactions that can be recorded for learning purposes.
/// Used for studying iOS app interaction flows and UI automation techniques.
enum RecordedActionType: String, Codable, CaseIterable {
    case tap = "tap"
    case longPress = "longPress"
    case swipe = "swipe"
    case textInput = "textInput"
    case wait = "wait"
    case screenshot = "screenshot"
    case note = "note"

    var displayName: String {
        switch self {
        case .tap: return "点击"
        case .longPress: return "长按"
        case .swipe: return "滑动"
        case .textInput: return "输入"
        case .wait: return "等待"
        case .screenshot: return "截图"
        case .note: return "注释"
        }
    }

    var iconName: String {
        switch self {
        case .tap: return "hand.tap"
        case .longPress: return "hand.tap.fill"
        case .swipe: return "arrow.left.and.right"
        case .textInput: return "keyboard"
        case .wait: return "clock"
        case .screenshot: return "camera"
        case .note: return "note.text"
        }
    }

    var educationalNote: String {
        switch self {
        case .tap:
            return "UITouch 事件: 系统将触摸事件传递给 hitTest 返回的最上层视图"
        case .longPress:
            return "UILongPressGestureRecognizer: 持续按压超过最小时间阈值触发"
        case .swipe:
            return "UIPanGestureRecognizer: 追踪多点触摸位移，计算速度和方向"
        case .textInput:
            return "UIResponder.chain: 文本输入通过 becomeFirstResponder 唤起键盘"
        case .wait:
            return "RunLoop: 等待期间主线程 RunLoop 持续处理事件源"
        case .screenshot:
            return "UIGraphicsImageRenderer: 捕获当前视图层级渲染结果"
        case .note:
            return "教学注释: 用于记录操作目的和学习要点"
        }
    }
}

// MARK: - Recorded Action

/// A single recorded user interaction action.
struct RecordedAction: Identifiable, Codable {
    let id: UUID
    var type: RecordedActionType
    var x: CGFloat
    var y: CGFloat
    var endX: CGFloat?       // for swipe
    var endY: CGFloat?       // for swipe
    var textContent: String? // for textInput / note
    var duration: Double?    // for wait / longPress (seconds)
    var label: String        // user annotation
    var timestamp: Double    // relative time from recording start
    var order: Int           // sequence order

    init(
        type: RecordedActionType,
        x: CGFloat = 0,
        y: CGFloat = 0,
        endX: CGFloat? = nil,
        endY: CGFloat? = nil,
        textContent: String? = nil,
        duration: Double? = nil,
        label: String = "",
        timestamp: Double = 0,
        order: Int = 0
    ) {
        self.id = UUID()
        self.type = type
        self.x = x
        self.y = y
        self.endX = endX
        self.endY = endY
        self.textContent = textContent
        self.duration = duration
        self.label = label
        self.timestamp = timestamp
        self.order = order
    }

    /// Human-readable description for the action list
    var description: String {
        switch type {
        case .tap:
            return "点击 (\(Int(x)), \(Int(y)))"
        case .longPress:
            let dur = duration ?? 1.0
            return "长按 (\(Int(x)), \(Int(y))) \(String(format: "%.1f", dur))s"
        case .swipe:
            if let ex = endX, let ey = endY {
                return "滑动 (\(Int(x)), \(Int(y))) -> (\(Int(ex)), \(Int(ey)))"
            }
            return "滑动 (\(Int(x)), \(Int(y)))"
        case .textInput:
            let preview = (textContent ?? "").prefix(20)
            return "输入: \(preview)"
        case .wait:
            let dur = duration ?? 1.0
            return "等待 \(String(format: "%.1f", dur))s"
        case .screenshot:
            return "截图标记"
        case .note:
            return "注释: \((textContent ?? "").prefix(30))"
        }
    }
}

// MARK: - Script Record

/// A complete recorded interaction script for learning purposes.
/// Playback is manual-only — no automated unattended execution.
struct ScriptRecord: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var targetBundleId: String
    var targetAppName: String
    var actions: [RecordedAction]
    var createdAt: Date
    var updatedAt: Date
    var lastPlayedAt: Date?

    init(
        name: String = "新建录制脚本",
        description: String = "",
        targetBundleId: String = "",
        targetAppName: String = "",
        actions: [RecordedAction] = []
    ) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.targetBundleId = targetBundleId
        self.targetAppName = targetAppName
        self.actions = actions
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastPlayedAt = nil
    }

    var actionCount: Int { actions.count }
    var totalDuration: Double {
        actions.last?.timestamp ?? 0
    }
}
