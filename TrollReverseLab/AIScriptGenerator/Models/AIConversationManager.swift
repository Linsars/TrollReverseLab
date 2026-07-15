import Foundation
import SwiftUI

// MARK: - AI Conversation Session

struct AIConversationSession: Codable, Identifiable {
    let id: UUID
    var appBundleId: String       // "" means general (no specific app)
    var appName: String           // display name
    var title: String             // auto-generated from first user message
    var messages: [ChatMessage]
    var scriptType: String        // "frida-js" or "lua"
    var createdAt: Date
    var updatedAt: Date

    init(appBundleId: String = "", appName: String = "通用", scriptType: String = "frida-js") {
        self.id = UUID()
        self.appBundleId = appBundleId
        self.appName = appName
        self.title = "新对话"
        self.messages = []
        self.scriptType = scriptType
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var displayTitle: String {
        if title == "新对话" && !messages.isEmpty {
            let firstUser = messages.first(where: { $0.role == "user" })
            if let first = firstUser {
                let truncated = String(first.content.prefix(30))
                return truncated + (first.content.count > 30 ? "..." : "")
            }
        }
        return title
    }

    var messageCount: Int {
        messages.count
    }

    var lastActivity: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: updatedAt)
    }
}

// MARK: - AI Conversation Manager

class AIConversationManager: ObservableObject {

    @Published var sessions: [AIConversationSession] = []
    @Published var currentSessionId: UUID?

    private let fileManager = FileManager.default

    var saveDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("AIConversations", isDirectory: true)
    }

    var saveFile: URL {
        saveDir.appendingPathComponent("sessions.json")
    }

    var currentSession: AIConversationSession? {
        guard let id = currentSessionId else { return nil }
        return sessions.first(where: { $0.id == id })
    }

    init() {
        try? fileManager.createDirectory(at: saveDir, withIntermediateDirectories: true)
        loadSessions()
    }

    // MARK: - Persistence

    private func loadSessions() {
        guard let data = try? Data(contentsOf: saveFile) else { return }
        if let decoded = try? JSONDecoder().decode([AIConversationSession].self, from: data) {
            sessions = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: saveFile)
        }
    }

    // MARK: - Session Management

    func getOrCreateSession(forAppBundleId bundleId: String?, appName: String, scriptType: ScriptType) -> AIConversationSession {
        let bid = bundleId ?? ""
        // Try to find an existing session for this app with matching script type
        if let existing = sessions.first(where: { $0.appBundleId == bid && $0.scriptType == scriptType.rawValue && $0.messages.count < 20 }) {
            currentSessionId = existing.id
            return existing
        }
        // Create new session
        var session = AIConversationSession(
            appBundleId: bid,
            appName: bid.isEmpty ? "通用" : appName,
            scriptType: scriptType.rawValue
        )
        sessions.insert(session, at: 0)
        currentSessionId = session.id
        saveSessions()
        return session
    }

    func switchToSession(_ id: UUID) {
        currentSessionId = id
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll(where: { $0.id == id })
        if currentSessionId == id {
            currentSessionId = sessions.first?.id
        }
        saveSessions()
    }

    func clearAllSessions() {
        sessions.removeAll()
        currentSessionId = nil
        saveSessions()
    }

    // MARK: - Message Management

    func appendMessages(toSession id: UUID, messages: [ChatMessage]) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages.append(contentsOf: messages)
        sessions[idx].updatedAt = Date()
        // Auto-title from first user message
        if sessions[idx].title == "新对话" {
            let firstUser = messages.first(where: { $0.role == "user" })
            if let first = firstUser {
                sessions[idx].title = String(first.content.prefix(40))
            }
        }
        saveSessions()
    }

    func updateSession(_ id: UUID, scriptType: ScriptType) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].scriptType = scriptType.rawValue
        sessions[idx].updatedAt = Date()
        saveSessions()
    }

    // MARK: - Sessions by App

    var sessionsByApp: [(String, [AIConversationSession])] {
        let grouped = Dictionary(grouping: sessions) { $0.appName }
        return grouped.sorted { $0.key < $1.key }
    }

    func sessionsForApp(_ bundleId: String) -> [AIConversationSession] {
        sessions.filter { $0.appBundleId == bundleId }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var generalSessions: [AIConversationSession] {
        sessions.filter { $0.appBundleId.isEmpty }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
