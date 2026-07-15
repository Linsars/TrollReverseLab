import SwiftUI
import UIKit
import Foundation
import Combine

// MARK: - Script Recorder Manager

class ScriptRecorderManager: ObservableObject {

    @Published var scripts: [ScriptRecord] = []
    @Published var currentScript: ScriptRecord?
    @Published var isRecording: Bool = false
    @Published var isPlaying: Bool = false
    @Published var recordingStartTime: Date?
    @Published var liveActions: [RecordedAction] = []
    @Published var playbackIndex: Int = 0
    @Published var showAddActionSheet: Bool = false
    @Published var pendingActionType: RecordedActionType = .tap

    private let fileManager = FileManager.default

    var saveDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ScriptRecords", isDirectory: true)
    }

    init() {
        createDirectories()
        loadScripts()
    }

    // MARK: - Directory Setup

    private func createDirectories() {
        try? fileManager.createDirectory(at: saveDir, withIntermediateDirectories: true)
    }

    // MARK: - Persistence

    private func loadScripts() {
        let file = saveDir.appendingPathComponent("scripts.json")
        guard fileManager.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file) else { return }
        if let decoded = try? JSONDecoder().decode([ScriptRecord].self, from: data) {
            scripts = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func saveScripts() {
        let file = saveDir.appendingPathComponent("scripts.json")
        if let data = try? JSONEncoder().encode(scripts) {
            try? data.write(to: file)
        }
    }

    // MARK: - Recording

    func startRecording(targetBundleId: String, targetAppName: String) {
        isRecording = true
        recordingStartTime = Date()
        liveActions = []
        currentScript = ScriptRecord(
            name: "录制 \(formatDate(Date()))",
            targetBundleId: targetBundleId,
            targetAppName: targetAppName
        )
    }

    func stopRecording() -> ScriptRecord? {
        guard var script = currentScript else { return nil }
        script.actions = liveActions
        script.updatedAt = Date()

        scripts.insert(script, at: 0)
        saveScripts()

        isRecording = false
        recordingStartTime = nil
        currentScript = nil
        liveActions = []

        return script
    }

    func cancelRecording() {
        isRecording = false
        recordingStartTime = nil
        currentScript = nil
        liveActions = []
    }

    // MARK: - Add Actions During Recording

    func addAction(_ action: RecordedAction) {
        guard isRecording else { return }
        var newAction = action
        newAction.order = liveActions.count
        if let startTime = recordingStartTime {
            newAction.timestamp = Date().timeIntervalSince(startTime)
        }
        liveActions.append(newAction)
    }

    func addTap(x: CGFloat, y: CGFloat, label: String = "") {
        addAction(RecordedAction(type: .tap, x: x, y: y, label: label))
    }

    func addSwipe(x: CGFloat, y: CGFloat, endX: CGFloat, endY: CGFloat, label: String = "") {
        addAction(RecordedAction(type: .swipe, x: x, y: y, endX: endX, endY: endY, label: label))
    }

    func addTextInput(text: String, label: String = "") {
        addAction(RecordedAction(type: .textInput, textContent: text, label: label))
    }

    func addWait(duration: Double, label: String = "") {
        addAction(RecordedAction(type: .wait, duration: duration, label: label))
    }

    func addNote(text: String) {
        addAction(RecordedAction(type: .note, textContent: text, label: "教学注释"))
    }

    func removeAction(at index: Int) {
        guard index < liveActions.count else { return }
        liveActions.remove(at: index)
        // Reorder
        for i in 0..<liveActions.count {
            liveActions[i].order = i
        }
    }

    // MARK: - Script CRUD

    func createScript(name: String, targetBundleId: String = "", targetAppName: String = "") -> ScriptRecord {
        let script = ScriptRecord(name: name, targetBundleId: targetBundleId, targetAppName: targetAppName)
        scripts.insert(script, at: 0)
        saveScripts()
        return script
    }

    func updateScript(_ script: ScriptRecord) {
        var updated = script
        updated.updatedAt = Date()
        if let idx = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts[idx] = updated
            saveScripts()
        }
    }

    func deleteScript(_ script: ScriptRecord) {
        scripts.removeAll { $0.id == script.id }
        saveScripts()
    }

    func addActionToScript(_ script: ScriptRecord, action: RecordedAction) {
        var updated = script
        var newAction = action
        newAction.order = updated.actions.count
        updated.actions.append(newAction)
        updateScript(updated)
    }

    func removeActionFromScript(_ script: ScriptRecord, at index: Int) {
        var updated = script
        guard index < updated.actions.count else { return }
        updated.actions.remove(at: index)
        // Reorder
        for i in 0..<updated.actions.count {
            updated.actions[i].order = i
        }
        updateScript(updated)
    }

    // MARK: - Playback (Manual - Educational Simulation)

    /// Simulates playback for learning purposes.
    /// Does NOT actually perform automated actions on the device.
    func startPlayback(script: ScriptRecord) {
        currentScript = script
        isPlaying = true
        playbackIndex = 0
    }

    func playbackNextStep() -> RecordedAction? {
        guard isPlaying, let script = currentScript else { return nil }
        guard playbackIndex < script.actions.count else {
            stopPlayback()
            return nil
        }
        let action = script.actions[playbackIndex]
        playbackIndex += 1
        return action
    }

    func stopPlayback() {
        isPlaying = false
        playbackIndex = 0
        if var script = currentScript {
            script.lastPlayedAt = Date()
            updateScript(script)
        }
        currentScript = nil
    }

    var playbackProgress: Double {
        guard isPlaying, let script = currentScript, script.actionCount > 0 else { return 0 }
        return Double(playbackIndex) / Double(script.actionCount)
    }

    // MARK: - Export

    func exportAsText(_ script: ScriptRecord) -> String {
        var output = ""
        output += "脚本名称: \(script.name)\n"
        output += "目标应用: \(script.targetAppName) (\(script.targetBundleId))\n"
        output += "动作数量: \(script.actionCount)\n"
        output += "录制时长: \(String(format: "%.1f", script.totalDuration))s\n"
        output += "创建时间: \(formatDate(script.createdAt))\n"
        output += "---\n"

        for (index, action) in script.actions.enumerated() {
            output += "[\(index + 1)] \(action.type.displayName): \(action.description)\n"
            if !action.label.isEmpty {
                output += "    标注: \(action.label)\n"
            }
            output += "    教学: \(action.type.educationalNote)\n"
            output += "    时间: +\(String(format: "%.2f", action.timestamp))s\n\n"
        }

        return output
    }

    func exportAsJSON(_ script: ScriptRecord) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(script) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Generate AI context from a recorded script for learning analysis
    func aiContext(_ script: ScriptRecord) -> String {
        var context = """
        录制脚本: \(script.name)
        目标应用: \(script.targetAppName) (\(script.targetBundleId))
        动作序列:
        """
        for (index, action) in script.actions.enumerated() {
            context += "\n  \(index + 1). \(action.description) [\(action.type.educationalNote)]"
        }
        return context
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
