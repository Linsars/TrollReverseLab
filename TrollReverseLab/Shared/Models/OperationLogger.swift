import Foundation
import SwiftUI

// MARK: - Operation Log Entry

struct OperationLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let module: String         // "沙盒浏览", "抓包", "Frida", "AI脚本", etc.
    let action: String         // "启动抓包", "生成脚本", etc.
    let detail: String         // additional info
    let result: String         // "成功" / "失败" / "完成"
    let resultColor: String    // "green" / "red" / "blue" / "gray"

    init(module: String, action: String, detail: String = "", result: String = "完成", resultColor: String = "blue") {
        self.id = UUID()
        self.timestamp = Date()
        self.module = module
        self.action = action
        self.detail = detail
        self.result = result
        self.resultColor = resultColor
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Operation Logger

class OperationLogger: ObservableObject {

    @Published var entries: [OperationLogEntry] = []

    static let shared = OperationLogger()

    private let fileManager = FileManager.default
    private let maxEntries = 500

    var saveFile: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("OperationLogs", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("logs.json")
    }

    init() {
        loadLogs()
    }

    // MARK: - Logging

    func log(module: String, action: String, detail: String = "", result: String = "完成", resultColor: String = "blue") {
        let entry = OperationLogEntry(module: module, action: action, detail: detail, result: result, resultColor: resultColor)
        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxEntries {
                self.entries = Array(self.entries.prefix(self.maxEntries))
            }
            self.saveLogs()
        }
    }

    // Convenience methods
    func logSuccess(module: String, action: String, detail: String = "") {
        log(module: module, action: action, detail: detail, result: "成功", resultColor: "green")
    }

    func logFailure(module: String, action: String, detail: String = "") {
        log(module: module, action: action, detail: detail, result: "失败", resultColor: "red")
    }

    func logInfo(module: String, action: String, detail: String = "") {
        log(module: module, action: action, detail: detail, result: "完成", resultColor: "blue")
    }

    // MARK: - Persistence

    private func loadLogs() {
        guard let data = try? Data(contentsOf: saveFile) else { return }
        if let decoded = try? JSONDecoder().decode([OperationLogEntry].self, from: data) {
            entries = decoded
        }
    }

    private func saveLogs() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: saveFile)
        }
    }

    // MARK: - Management

    func clearLogs() {
        entries.removeAll()
        saveLogs()
    }

    func exportAsText() -> String {
        var output = "TrollAIBio 逆向 操作日志\n"
        output += "导出时间: \(Date())\n"
        output += "记录数量: \(entries.count)\n"
        output += String(repeating: "=", count: 60) + "\n\n"

        for entry in entries {
            output += "[\(entry.timeString)] "
            output += "[\(entry.module)] "
            output += "\(entry.action)"
            if !entry.detail.isEmpty {
                output += " - \(entry.detail)"
            }
            output += " → \(entry.result)\n"
        }
        return output
    }

    // MARK: - Filtering

    func filtered(module: String?, searchText: String) -> [OperationLogEntry] {
        var result = entries
        if let module = module, !module.isEmpty {
            result = result.filter { $0.module == module }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.action.localizedCaseInsensitiveContains(searchText) ||
                $0.detail.localizedCaseInsensitiveContains(searchText) ||
                $0.module.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var moduleNames: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            if !seen.contains(entry.module) {
                seen.insert(entry.module)
                result.append(entry.module)
            }
        }
        return result
    }

    // Statistics
    var totalActions: Int { entries.count }
    var successCount: Int { entries.filter { $0.resultColor == "green" }.count }
    var failureCount: Int { entries.filter { $0.resultColor == "red" }.count }
}
