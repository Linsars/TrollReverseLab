//
//  SandboxFileBrowser.swift
//  TrollReverseLab
//
//  Module 1: File browser for navigating TrollStore app sandbox directories.
//  Supports Documents, Library, Library/Preferences, and tmp folders.
//  Provides built-in viewers for JSON, Plist, SQLite, and Hex formats.
//
//  CONSTRAINT: Read-only browsing for local data format research.
//  No modification of online verification data or DRM-protected content.
//

import Foundation
import SwiftUI

/// Represents a file or directory entry in the sandbox browser.
public struct SandboxFileEntry: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let modificationDate: Date?
    public let fileType: SandboxFileType
}

public enum SandboxFileType: String, CaseIterable {
    case json
    case plist
    case sqlite
    case hex
    case text
    case image
    case directory
    case unknown

    public var icon: String {
        switch self {
        case .json: return "curlybraces"
        case .plist: return "doc.text"
        case .sqlite: return "cylinder.split.1x2"
        case .hex: return "number.square"
        case .text: return "doc.plaintext"
        case .image: return "photo"
        case .directory: return "folder"
        case .unknown: return "doc"
        }
    }

    public var displayName: String {
        switch self {
        case .json: return "JSON"
        case .plist: return "Plist"
        case .sqlite: return "SQLite"
        case .hex: return "Hex"
        case .text: return "Text"
        case .image: return "Image"
        case .directory: return "Directory"
        case .unknown: return "Unknown"
        }
    }
}

/// Browser that navigates sandbox directories and lists file entries.
public final class SandboxFileBrowser {

    private let fileManager = FileManager.default

    public init() {}

    /// Lists all files and directories at the given path.
    public func listDirectory(at path: String) -> [SandboxFileEntry] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else {
            return []
        }

        var results: [SandboxFileEntry] = []

        for entry in entries {
            let fullPath = (path as NSString).appendingPathComponent(entry)
            let attrs = try? fileManager.attributesOfItem(atPath: fullPath)

            let isDirectory = (attrs?[.type] as? FileAttributeType) == .typeDirectory
            let size = (attrs?[.size] as? Int64) ?? 0
            let modDate = attrs?[.modificationDate] as? Date

            let fileType: SandboxFileType
            if isDirectory {
                fileType = .directory
            } else {
                fileType = detectFileType(filename: entry)
            }

            results.append(SandboxFileEntry(
                id: fullPath,
                name: entry,
                path: fullPath,
                isDirectory: isDirectory,
                size: size,
                modificationDate: modDate,
                fileType: fileType
            ))
        }

        // Directories first, then files alphabetically
        return results.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Detects file type based on extension for selecting the appropriate viewer.
    public func detectFileType(filename: String) -> SandboxFileType {
        let ext = (filename as NSString).pathExtension.lowercased()

        switch ext {
        case "json":
            return .json
        case "plist":
            return .plist
        case "sqlite", "db", "sqlite3", "realm":
            return .sqlite
        case "txt", "log", "csv", "xml", "yaml", "yml", "lua", "js":
            return .text
        case "png", "jpg", "jpeg", "gif", "bmp", "webp":
            return .image
        default:
            // Check if it's a binary file
            return .unknown
        }
    }

    /// Reads file content as Data for the viewer to process.
    public func readFile(at path: String) -> Data? {
        return fileManager.contents(atPath: path)
    }
}

// MARK: - SwiftUI Views

/// Main sandbox browser view showing the file list.
public struct SandboxBrowserView: View {
    let app: TrollStoreApp
    @State private var currentPath: String
    @State private var entries: [SandboxFileEntry] = []
    @State private var selectedEntry: SandboxFileEntry?
    @State private var navigationStack: [String] = []

    private let browser = SandboxFileBrowser()

    public init(app: TrollStoreApp) {
        self.app = app
        _currentPath = State(initialValue: app.containerPath)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Path breadcrumb
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(breadcrumbItems(), id: \.path) { item in
                        Button(item.name) {
                            navigateTo(item.path)
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)

                        if item.path != currentPath {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color(.secondarySystemBackground))

            Divider()

            // Quick access buttons
            HStack(spacing: 12) {
                quickAccessButton("Documents", path: app.documentsPath)
                quickAccessButton("Library", path: app.libraryPath)
                quickAccessButton("Preferences", path: app.preferencesPath)
                quickAccessButton("tmp", path: (app.containerPath as NSString).appendingPathComponent("tmp"))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // File list
            List(entries) { entry in
                Button {
                    if entry.isDirectory {
                        navigateTo(entry.path)
                    } else {
                        selectedEntry = entry
                    }
                } label: {
                    FileRowView(entry: entry)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            FileViewerSheet(entry: entry)
        }
        .onAppear {
            refresh()
        }
    }

    // MARK: - Actions

    private func refresh() {
        entries = browser.listDirectory(at: currentPath)
    }

    private func navigateTo(_ path: String) {
        navigationStack.append(currentPath)
        currentPath = path
        refresh()
    }

    private func navigateBack() {
        if let previous = navigationStack.popLast() {
            currentPath = previous
            refresh()
        }
    }

    private func quickAccessButton(_ title: String, path: String) -> some View {
        Button {
            currentPath = path
            navigationStack = []
            refresh()
        } label: {
            Label(title, systemImage: "folder.badge.gearshape")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
        }
    }

    private func breadcrumbItems() -> [(name: String, path: String)] {
        var items: [(name: String, path: String)] = []
        let containerName = app.displayName
        items.append((containerName, app.containerPath))

        if currentPath != app.containerPath {
            let relative = currentPath.replacingOccurrences(of: app.containerPath + "/", with: "")
            let components = relative.split(separator: "/")
            var buildPath = app.containerPath
            for component in components {
                buildPath = (buildPath as NSString).appendingPathComponent(String(component))
                items.append((String(component), buildPath))
            }
        }

        return items
    }
}

/// File row displaying icon, name, size, and date.
struct FileRowView: View {
    let entry: SandboxFileEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.fileType.icon)
                .foregroundColor(entry.isDirectory ? .accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .lineLimit(1)

                if !entry.isDirectory {
                    Text(formatSize(entry.size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
