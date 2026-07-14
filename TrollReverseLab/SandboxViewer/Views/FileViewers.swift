//
//  FileViewers.swift
//  TrollReverseLab
//
//  Module 1: Built-in viewers for JSON, Plist, SQLite, and Hex data formats.
//  Used for studying local sandbox data structures and verifying parameter
//  modifications in offline save files.
//

import Foundation
import SwiftUI
import SQLite3

// MARK: - File Viewer Sheet Router

struct FileViewerSheet: View {
    let entry: SandboxFileEntry
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            Group {
                switch entry.fileType {
                case .json:
                    JSONViewerView(filePath: entry.path)
                case .plist:
                    PlistViewerView(filePath: entry.path)
                case .sqlite:
                    SQLiteViewerView(filePath: entry.path)
                case .text:
                    TextViewerView(filePath: entry.path)
                default:
                    HexViewerView(filePath: entry.path)
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") { presentationMode.wrappedValue.dismiss() }
            )
        }
    }
}

// MARK: - JSON Viewer

/// Renders JSON data with syntax highlighting and collapsible tree structure.
struct JSONViewerView: View {
    let filePath: String
    @State private var jsonString: String = ""
    @State private var parseError: String?
    @State private var parsedObject: Any?
    @State private var expandedPaths: Set<String> = []

    var body: some View {
        ScrollView {
            if let error = parseError {
                Text("Parse error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            } else if let jsonString = jsonString as String?, !jsonString.isEmpty {
                if let parsed = parsedObject {
                    JSONTreeView(data: parsed, key: "root", level: 0, expandedPaths: $expandedPaths)
                        .padding()
                } else {
                    Text(jsonString)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
            } else {
                ProgressView("Loading JSON...")
                    .padding()
            }
        }
        .onAppear { loadJSON() }
    }

    private func loadJSON() {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            parseError = "Cannot read file"
            return
        }

        do {
            let parsed = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
            parsedObject = parsed

            let prettyData = try JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted, .sortedKeys])
            jsonString = String(data: prettyData, encoding: .utf8) ?? ""
        } catch {
            parseError = error.localizedDescription
        }
    }
}

/// Recursive tree view for JSON data with expand/collapse.
struct JSONTreeView: View {
    let data: Any
    let key: String
    let level: Int
    @Binding var expandedPaths: Set<String>

    private var path: String { key }

    private var isExpanded: Bool {
        expandedPaths.contains(path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let dict = data as? [String: Any] {
                HStack {
                    Button {
                        toggleExpanded()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                            Text("\"\(key)\"")
                                .foregroundColor(.purple)
                            Text(": {\(dict.count) keys}")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, CGFloat(level) * 16)

                if isExpanded {
                    ForEach(dict.keys.sorted(), id: \.self) { subKey in
                        JSONTreeView(
                            data: dict[subKey] ?? "null",
                            key: "\(path).\(subKey)",
                            level: level + 1,
                            expandedPaths: $expandedPaths
                        )
                    }
                }
            } else if let array = data as? [Any] {
                HStack {
                    Button {
                        toggleExpanded()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                            Text("\"\(key)\"")
                                .foregroundColor(.purple)
                            Text(": [\n(array.count) items]")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, CGFloat(level) * 16)

                if isExpanded {
                    ForEach(Array(array.enumerated()), id: \.offset) { index, item in
                        JSONTreeView(
                            data: item,
                            key: "\(path)[\(index)]",
                            level: level + 1,
                            expandedPaths: $expandedPaths
                        )
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Text("\"\(key)\"")
                        .foregroundColor(.purple)
                    Text(":")
                    Text(formatValue(data))
                        .foregroundColor(valueColor(data))
                }
                .font(.system(.body, design: .monospaced))
                .padding(.leading, CGFloat(level) * 16)
            }
        }
    }

    private func toggleExpanded() {
        if isExpanded {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    private func formatValue(_ value: Any) -> String {
        if let str = value as? String {
            return "\"\(str)\""
        } else if let num = value as? NSNumber {
            return num.stringValue
        } else if value is NSNull {
            return "null"
        }
        return "\(value)"
    }

    private func valueColor(_ value: Any) -> Color {
        if value is String { return .green }
        if value is NSNumber { return .orange }
        if value is NSNull { return .gray }
        return .primary
    }
}

// MARK: - Plist Viewer

/// Renders plist data in a tree format showing keys and values.
struct PlistViewerView: View {
    let filePath: String
    @State private var plistData: [String: Any]?
    @State private var parseError: String?

    var body: some View {
        ScrollView {
            if let error = parseError {
                Text("Parse error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            } else if let data = plistData {
                PlistTreeView(data: data, level: 0)
                    .padding()
            } else {
                ProgressView("Loading plist...")
                    .padding()
            }
        }
        .onAppear { loadPlist() }
    }

    private func loadPlist() {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            parseError = "Cannot read file"
            return
        }

        do {
            if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                plistData = plist
            } else {
                parseError = "Plist root is not a dictionary"
            }
        } catch {
            parseError = error.localizedDescription
        }
    }
}

struct PlistTreeView: View {
    let data: [String: Any]
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(data.keys.sorted(), id: \.self) { key in
                PlistValueView(key: key, value: data[key] ?? "", level: level)
            }
        }
    }
}

struct PlistValueView: View {
    let key: String
    let value: Any
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.purple)
                Text(":")

                if let dict = value as? [String: Any] {
                    Text("{\(dict.count) keys}")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let array = value as? [Any] {
                    Text("[\(array.count) items]")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let data = value as? Data {
                    Text("<Data: \(data.count) bytes>")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.orange)
                } else {
                    Text("\(value)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
            .padding(.leading, CGFloat(level) * 16)

            if let dict = value as? [String: Any] {
                PlistTreeView(data: dict, level: level + 1)
            }
        }
    }
}

// MARK: - SQLite Viewer

/// Opens SQLite databases and displays table list with row data.
struct SQLiteViewerView: View {
    let filePath: String
    @State private var tables: [String] = []
    @State private var selectedTable: String?
    @State private var columns: [String] = []
    @State private var rows: [[String]] = []
    @State private var dbError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let error = dbError {
                Text("Database error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            } else {
                // Table selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tables, id: \.self) { table in
                            Button {
                                loadTableData(table)
                            } label: {
                                Text(table)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedTable == table ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                Divider()

                // Table data
                if !columns.isEmpty {
                    SQLiteTableView(columns: columns, rows: rows)
                } else {
                    Text("Select a table to view data")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
        .onAppear { loadTables() }
    }

    private func loadTables() {
        var db: OpaquePointer?
        guard sqlite3_open(filePath, &db) == SQLITE_OK else {
            dbError = "Cannot open database"
            return
        }
        defer { sqlite3_close(db) }

        let query = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            dbError = "Cannot query tables"
            return
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 0) {
                tables.append(String(cString: name))
            }
        }
        sqlite3_finalize(stmt)
    }

    private func loadTableData(_ table: String) {
        selectedTable = table
        columns = []
        rows = []

        var db: OpaquePointer?
        guard sqlite3_open(filePath, &db) == SQLITE_OK else {
            dbError = "Cannot open database"
            return
        }
        defer { sqlite3_close(db) }

        let query = "SELECT * FROM \"\(table)\" LIMIT 100"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            dbError = "Cannot query table: \(table)"
            return
        }

        let columnCount = sqlite3_column_count(stmt)
        for i in 0..<columnCount {
            if let name = sqlite3_column_name(stmt, i) {
                columns.append(String(cString: name))
            }
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String] = []
            for i in 0..<columnCount {
                let text: String
                if let cString = sqlite3_column_text(stmt, i) {
                    text = String(cString: cString)
                } else {
                    text = "NULL"
                }
                row.append(text)
            }
            rows.append(row)
        }
        sqlite3_finalize(stmt)
    }
}

struct SQLiteTableView: View {
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    ForEach(columns, id: \.self) { col in
                        Text(col)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .frame(minWidth: 100, alignment: .leading)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                    }
                }

                Divider()

                // Rows
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                            Text(value)
                                .font(.system(.caption, design: .monospaced))
                                .frame(minWidth: 100, alignment: .leading)
                                .padding(8)
                                .lineLimit(2)
                        }
                    }
                    Divider()
                }
            }
        }
    }
}

// MARK: - Hex Viewer

/// Displays binary file content in hex dump format with ASCII sidebar.
struct HexViewerView: View {
    let filePath: String
    @State private var hexData: [(offset: Int, hex: String, ascii: String)] = []
    @State private var loadError: String?

    private let bytesPerLine = 16

    var body: some View {
        ScrollView {
            if let error = loadError {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hexData.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 12) {
                            // Offset
                            Text(String(format: "%08X", line.offset))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            // Hex bytes
                            Text(line.hex)
                                .font(.system(.caption, design: .monospaced))

                            // ASCII representation
                            Text(line.ascii)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.accentColor)
                        }
                        .padding(.vertical, 1)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .onAppear { loadHex() }
    }

    private func loadHex() {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            loadError = "Cannot read file"
            return
        }

        // Limit to first 64KB for performance
        let maxBytes = 65536
        let displayData = data.count > maxBytes ? data.prefix(maxBytes) : data

        var offset = 0
        for chunk in displayData.chunked(by: bytesPerLine) {
            let hexStrings = chunk.map { String(format: "%02X", $0) }
            let hexLine = hexStrings.joined(separator: " ")

            let asciiLine = chunk.map { byte -> String in
                if byte >= 32 && byte < 127 {
                    return String(format: "%c", byte)
                } else {
                    return "."
                }
            }.joined()

            hexData.append((offset: offset, hex: hexLine, ascii: asciiLine))
            offset += chunk.count
        }

        if data.count > maxBytes {
            hexData.append((offset: offset, hex: "...", ascii: "(\(data.count - maxBytes) more bytes)"))
        }
    }
}

// MARK: - Text Viewer

struct TextViewerView: View {
    let filePath: String
    @State private var content: String = ""
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            if let error = loadError {
                Text(error).foregroundColor(.red).padding()
            } else {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .onAppear { loadText() }
    }

    private func loadText() {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            loadError = "Cannot read file"
            return
        }
        content = String(data: data, encoding: .utf8) ?? "[Binary data — use Hex viewer]"
    }
}

// MARK: - Helpers

extension Sequence {
    func chunked(by chunkSize: Int) -> [[Element]] {
        var result: [[Element]] = []
        var current: [Element] = []
        for element in self {
            current.append(element)
            if current.count >= chunkSize {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
