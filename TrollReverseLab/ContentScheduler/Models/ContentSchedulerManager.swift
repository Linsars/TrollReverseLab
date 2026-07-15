import SwiftUI
import Foundation
import UserNotifications
import Combine

// MARK: - Content Scheduler Manager

class ContentSchedulerManager: ObservableObject {

    @Published var items: [ScheduleItem] = []
    @Published var showAddSheet: Bool = false
    @Published var showEditSheet: Bool = false
    @Published var editingItem: ScheduleItem?

    private let fileManager = FileManager.default

    var saveDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ContentSchedules", isDirectory: true)
    }

    init() {
        createDirectories()
        loadItems()
    }

    // MARK: - Directory Setup

    private func createDirectories() {
        try? fileManager.createDirectory(at: saveDir, withIntermediateDirectories: true)
    }

    // MARK: - Persistence

    private func loadItems() {
        let file = saveDir.appendingPathComponent("schedules.json")
        guard fileManager.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file) else { return }
        if let decoded = try? JSONDecoder().decode([ScheduleItem].self, from: data) {
            items = decoded.sorted { $0.plannedDate < $1.plannedDate }
        }
    }

    private func saveItems() {
        let file = saveDir.appendingPathComponent("schedules.json")
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: file)
        }
    }

    // MARK: - CRUD

    func addItem(_ item: ScheduleItem) {
        items.append(item)
        items.sort { $0.plannedDate < $1.plannedDate }
        saveItems()
        if item.reminderEnabled {
            scheduleReminder(for: item)
        }
    }

    func updateItem(_ item: ScheduleItem) {
        var updated = item
        updated.updatedAt = Date()
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            // Cancel old reminder if exists
            if let oldId = items[idx].reminderIdentifier {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [oldId])
            }
            items[idx] = updated
            items.sort { $0.plannedDate < $1.plannedDate }
            saveItems()
            if updated.reminderEnabled {
                scheduleReminder(for: updated)
            }
        }
    }

    func deleteItem(_ item: ScheduleItem) {
        // Cancel reminder
        if let reminderId = item.reminderIdentifier {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderId])
        }
        items.removeAll { $0.id == item.id }
        saveItems()
    }

    func updateStatus(_ item: ScheduleItem, status: ScheduleStatus) {
        var updated = item
        updated.status = status
        if status == .completed {
            updated.completedDate = Date()
            // Cancel reminder for completed items
            if let reminderId = updated.reminderIdentifier {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderId])
            }
            updated.reminderEnabled = false
        }
        updateItem(updated)
    }

    // MARK: - Local Notification

    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    private func scheduleReminder(for item: ScheduleItem) {
        let content = UNMutableNotificationContent()
        content.title = "创作提醒: \(item.title)"
        content.body = "平台: \(item.platform.displayName) | 状态: \(item.status.displayName)"
        content.sound = .default
        content.userInfo = ["scheduleId": item.id.uuidString]

        // Trigger 1 hour before planned time
        let triggerDate = item.plannedDate.addingTimeInterval(-3600)
        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        let reminderId = "schedule_\(item.id.uuidString)"
        let request = UNNotificationRequest(identifier: reminderId, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if error == nil {
                DispatchQueue.main.async {
                    if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[idx].reminderIdentifier = reminderId
                        self.saveItems()
                    }
                }
            }
        }
    }

    func cancelReminder(for item: ScheduleItem) {
        if let reminderId = item.reminderIdentifier {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderId])
        }
    }

    // MARK: - Filtering

    var todayItems: [ScheduleItem] {
        items.filter { $0.isToday }
    }

    var upcomingItems: [ScheduleItem] {
        items.filter { $0.plannedDate > Date() && $0.status == .planned }
    }

    var overdueItems: [ScheduleItem] {
        items.filter { $0.isOverdue }
    }

    var completedItems: [ScheduleItem] {
        items.filter { $0.status == .completed }
    }

    func itemsForDate(_ date: Date) -> [ScheduleItem] {
        Calendar.current.isDate(date, inSameDayAs: date)
        return items.filter { Calendar.current.isDate($0.plannedDate, inSameDayAs: date) }
    }

    // MARK: - Statistics

    var stats: ScheduleStats {
        ScheduleStats(
            total: items.count,
            planned: items.filter { $0.status == .planned }.count,
            inProgress: items.filter { $0.status == .drafting || $0.status == .reviewing }.count,
            completed: items.filter { $0.status == .completed }.count,
            overdue: items.filter { $0.isOverdue }.count
        )
    }
}
