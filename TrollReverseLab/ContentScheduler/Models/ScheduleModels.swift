import Foundation

// MARK: - Schedule Status

enum ScheduleStatus: String, Codable, CaseIterable {
    case planned = "planned"
    case drafting = "drafting"
    case reviewing = "reviewing"
    case completed = "completed"
    case cancelled = "cancelled"

    var displayName: String {
        switch self {
        case .planned: return "已计划"
        case .drafting: return "创作中"
        case .reviewing: return "审核中"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        }
    }

    var iconName: String {
        switch self {
        case .planned: return "calendar"
        case .drafting: return "pencil.and.outline"
        case .reviewing: return "eye"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }
}

// MARK: - Content Platform

enum ContentPlatform: String, Codable, CaseIterable {
    case wechat = "wechat"
    case weibo = "weibo"
    case xiaohongshu = "xiaohongshu"
    case douyin = "douyin"
    case bilibili = "bilibili"
    case blog = "blog"
    case other = "other"

    var displayName: String {
        switch self {
        case .wechat: return "微信"
        case .weibo: return "微博"
        case .xiaohongshu: return "小红书"
        case .douyin: return "抖音"
        case .bilibili: return "B站"
        case .blog: return "博客"
        case .other: return "其他"
        }
    }

    var iconName: String {
        switch self {
        case .wechat: return "message.fill"
        case .weibo: return "globe"
        case .xiaohongshu: return "book.fill"
        case .douyin: return "play.rectangle.fill"
        case .bilibili: return "tv.fill"
        case .blog: return "doc.richtext.fill"
        case .other: return "square.dashed"
        }
    }
}

// MARK: - Schedule Item

/// A single content creation schedule item.
/// Offline reminder only — no automated posting.
/// All publishing is done manually by the user.
struct ScheduleItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var platform: ContentPlatform
    var plannedDate: Date
    var status: ScheduleStatus
    var notes: String
    var tags: [String]
    var reminderEnabled: Bool
    var reminderIdentifier: String?   // UNNotificationIdentifier
    var completedDate: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        title: String = "",
        platform: ContentPlatform = .wechat,
        plannedDate: Date = Date().addingTimeInterval(86400),  // default tomorrow
        notes: String = "",
        tags: [String] = [],
        reminderEnabled: Bool = true
    ) {
        self.id = UUID()
        self.title = title
        self.platform = platform
        self.plannedDate = plannedDate
        self.status = .planned
        self.notes = notes
        self.tags = tags
        self.reminderEnabled = reminderEnabled
        self.reminderIdentifier = nil
        self.completedDate = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isOverdue: Bool {
        return plannedDate < Date() && status != .completed && status != .cancelled
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(plannedDate)
    }

    var isUpcoming: Bool {
        plannedDate > Date() && status == .planned
    }
}

// MARK: - Schedule Statistics

struct ScheduleStats {
    let total: Int
    let planned: Int
    let inProgress: Int
    let completed: Int
    let overdue: Int

    var completionRate: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}
