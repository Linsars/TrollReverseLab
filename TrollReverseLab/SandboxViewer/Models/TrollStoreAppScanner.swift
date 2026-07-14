//
//  TrollStoreAppScanner.swift
//  TrollReverseLab
//
//  Module 1: Scans iOS container directories for TrollStore-installed
//  applications.
//
//  Detection strategy (pure TrollStore, no jailbreak paths):
//  - PRIMARY: Scan /var/containers/Bundle/Application/ for the official
//    TrollStore marker files: _TrollStore (standard) and _TrollStoreLite.
//    This is the exact mechanism used by TrollStore 2.1.1 / opa334.
//  - SECONDARY: Scan /var/mobile/Containers/Data/Application/ for the
//    .appInfo.plist marker used by some TrollStore variants / ReMod builds.
//  - For every discovered app, parse the bundle Info.plist, then locate the
//    matching data container by bundle ID so the sandbox browser can jump
//    between Bundle and Data containers.
//
//  CONSTRAINT: Read-only scanning for local research. No modification of
//  system data or third-party app store applications.
//

import Foundation

// MARK: - Permission Error

/// Thrown when the app cannot access sandbox directories due to missing entitlements.
/// This error is surfaced to the user with instructions to re-sign the IPA.
public enum SandboxPermissionError: Error, LocalizedError {
    case noSandboxEscape(path: String)
    case directoryAccessFailed(path: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .noSandboxEscape(let path):
            return "目录访问失败：IPA缺失 no-sandbox 沙盒逃逸权限，请重新注入完整授权重签 IPA\n路径: \(path)"
        case .directoryAccessFailed(let path, let underlying):
            return "目录访问失败 [\(path)]: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - App Model

/// Represents an installed TrollStore application discovered on the device.
public struct TrollStoreApp: Identifiable, Hashable {
    public let id: String
    public let bundleIdentifier: String
    public let displayName: String
    public let version: String
    public let bundlePath: String          // Path to the .app bundle
    public let dataContainerPath: String    // Path to the data sandbox container
    public let installDate: Date?
    public let appSize: Int64
    public let isTrollStore: Bool
    public let markerType: String

    /// Primary container path (data container, used for sandbox browsing)
    public var containerPath: String {
        dataContainerPath.isEmpty ? bundlePath : dataContainerPath
    }

    public var documentsPath: String {
        (dataContainerPath as NSString).appendingPathComponent("Documents")
    }

    public var libraryPath: String {
        (dataContainerPath as NSString).appendingPathComponent("Library")
    }

    public var preferencesPath: String {
        (libraryPath as NSString).appendingPathComponent("Preferences")
    }

    public var tmpPath: String {
        (dataContainerPath as NSString).appendingPathComponent("tmp")
    }
}

// MARK: - Diagnostics

/// Diagnostic info about the last scan — helps users troubleshoot.
public struct ScanDiagnostics {
    public var pathsScanned: [String] = []
    public var totalDirsScanned: Int = 0
    public var trollStoreApps: Int = 0
    public var markerFilesFound: Int = 0
    public var errors: [String] = []
    public var permissionError: String? = nil
    public var canAccessSandbox: Bool = false
    public var scanDuration: TimeInterval = 0
    public var markersChecked: [String] = []
    public var skippedContainers: Int = 0
}

// MARK: - Permission Check Result

/// Result of a permission self-check (Module 4).
public struct PermissionCheckResult {
    public let path: String
    public let isAccessible: Bool
    public let itemCount: Int
    public let error: String?
}

// MARK: - Scanner

/// Scanner that discovers TrollStore-installed applications by reading both
/// Bundle and Data container directories.
public final class TrollStoreAppScanner {

    // Official TrollStore marker files (opa334/TrollStore 2.1.1).
    // TS_ACTIVE_MARKER is _TrollStore for standard TrollStore and
    // _TrollStoreLite for TrollStoreLite. We check both.
    private let trollStoreMarkers = ["_TrollStore", "_TrollStoreLite"]
    // Marker used by some forks / ReMod builds in the Data container.
    private let appInfoMarker = ".appInfo.plist"

    /// Primary scan paths for TrollStore app bundle containers.
    private let bundleContainerPaths = [
        "/var/containers/Bundle/Application",
        "/private/var/containers/Bundle/Application"
    ]

    /// Secondary scan paths for Data containers (used by .appInfo.plist fallback).
    private let dataContainerPaths = [
        "/private/var/mobile/Containers/Data/Application/",
        "/var/mobile/Containers/Data/Application/"
    ]

    private let fileManager = FileManager.default
    public private(set) var diagnostics = ScanDiagnostics()

    public init() {}

    // MARK: - Public Scan API

    /// Scans container directories for TrollStore-installed apps.
    public func scanTrollStoreApps() -> [TrollStoreApp] {
        diagnostics = ScanDiagnostics()
        diagnostics.markersChecked = trollStoreMarkers + [appInfoMarker]
        let startTime = CFAbsoluteTimeGetCurrent()

        var results: [TrollStoreApp] = []
        var seenBundleIDs = Set<String>()

        // Pre-build a map of bundle ID -> data container path.
        let dataContainerMap = buildDataContainerMap()
        diagnostics.canAccessSandbox = !dataContainerMap.isEmpty

        // 1. PRIMARY: Scan bundle containers for official TrollStore markers.
        for basePath in bundleContainerPaths {
            diagnostics.pathsScanned.append(basePath)
            scanBundleContainers(
                at: basePath,
                dataContainerMap: dataContainerMap,
                into: &results,
                seenBundleIDs: &seenBundleIDs
            )
        }

        // 2. SECONDARY: Scan data containers for .appInfo.plist.
        for basePath in dataContainerPaths {
            if !diagnostics.pathsScanned.contains(basePath) {
                diagnostics.pathsScanned.append(basePath)
            }
            scanDataContainersForAppInfo(
                at: basePath,
                into: &results,
                seenBundleIDs: &seenBundleIDs
            )
        }

        diagnostics.scanDuration = CFAbsoluteTimeGetCurrent() - startTime

        return results.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    // MARK: - Bundle Container Scanning

    private func scanBundleContainers(
        at basePath: String,
        dataContainerMap: [String: String],
        into results: inout [TrollStoreApp],
        seenBundleIDs: inout Set<String>
    ) {
        guard dirExistsAndAccessible(at: basePath) else {
            diagnostics.errors.append("无法访问 bundle 容器根目录: \(basePath)")
            return
        }

        guard let allDirs = enumerateSubdirectories(at: basePath) else {
            diagnostics.permissionError = SandboxPermissionError.noSandboxEscape(path: basePath).localizedDescription
            diagnostics.canAccessSandbox = false
            return
        }

        diagnostics.totalDirsScanned += allDirs.count

        for dir in allDirs {
            let dirPath = dir.path
            let marker = firstExistingMarker(in: dirPath, markers: trollStoreMarkers)
            guard !marker.isEmpty else { continue }

            diagnostics.markerFilesFound += 1

            // Exclude TrollStore / TrollStoreLite own containers.
            if isTrollStoreOwnContainer(dirPath) {
                diagnostics.skippedContainers += 1
                continue
            }

            if let app = parseBundleContainer(dir, marker: marker, dataContainerMap: dataContainerMap),
               !seenBundleIDs.contains(app.bundleIdentifier) {
                results.append(app)
                seenBundleIDs.insert(app.bundleIdentifier)
                diagnostics.trollStoreApps += 1
            }
        }
    }

    // MARK: - Data Container (.appInfo.plist) Scanning

    private func scanDataContainersForAppInfo(
        at basePath: String,
        into results: inout [TrollStoreApp],
        seenBundleIDs: inout Set<String>
    ) {
        guard let allDirs = enumerateSubdirectories(at: basePath) else { return }
        if !diagnostics.canAccessSandbox {
            diagnostics.canAccessSandbox = true
        }
        diagnostics.totalDirsScanned += allDirs.count

        for dir in allDirs {
            let appInfoPath = (dir.path as NSString).appendingPathComponent(appInfoMarker)
            guard fileManager.fileExists(atPath: appInfoPath) else { continue }

            diagnostics.markerFilesFound += 1

            if let app = parseAppInfoPlistContainer(dir),
               !seenBundleIDs.contains(app.bundleIdentifier) {
                results.append(app)
                seenBundleIDs.insert(app.bundleIdentifier)
                diagnostics.trollStoreApps += 1
            }
        }
    }

    // MARK: - Data Container Map

    /// Builds a map of bundle ID -> data container path by reading the MCM metadata
    /// plist inside each Data/Application/<UUID> directory.
    private func buildDataContainerMap() -> [String: String] {
        var map: [String: String] = [:]
        for basePath in dataContainerPaths {
            guard let dirs = enumerateSubdirectories(at: basePath) else { continue }
            for dir in dirs {
                let metadataPath = (dir.path as NSString).appendingPathComponent(
                    ".com.apple.mobile_container_manager.metadata.plist"
                )
                guard let data = fileManager.contents(atPath: metadataPath),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let bundleId = plist["MCMMetadataIdentifier"] as? String,
                      !bundleId.isEmpty else { continue }
                map[bundleId] = dir.path
            }
        }
        return map
    }

    // MARK: - App Parsing

    /// Parses a bundle container directory (containing a .app bundle) into a TrollStoreApp.
    private func parseBundleContainer(
        _ containerURL: URL,
        marker: String,
        dataContainerMap: [String: String]
    ) -> TrollStoreApp? {
        let containerPath = containerURL.path

        // Find the .app bundle inside the container.
        guard let appBundleURL = findAppBundle(in: containerPath) else { return nil }
        let appBundlePath = appBundleURL.path

        // Read the app's Info.plist.
        let infoPlistPath = (appBundlePath as NSString).appendingPathComponent("Info.plist")
        let infoPlist = readPlistDictionary(at: infoPlistPath)

        let bundleId = infoPlist?["CFBundleIdentifier"] as? String
            ?? infoPlist?["CFBundlePackageIdentifier"] as? String
            ?? bundleIdFromPath(containerPath)
        let displayName = infoPlist?["CFBundleDisplayName"] as? String
            ?? infoPlist?["CFBundleName"] as? String
            ?? appBundleURL.lastPathComponent
        let version = infoPlist?["CFBundleShortVersionString"] as? String
            ?? infoPlist?["CFBundleVersion"] as? String
            ?? "1.0"

        // Skip Apple system apps (TrollStore should never install these, but be safe).
        if bundleId.hasPrefix("com.apple.") { return nil }

        // Locate the matching data container.
        let dataContainerPath = dataContainerMap[bundleId] ?? ""

        let appSize = calculateDirectorySize(at: appBundlePath)
        let installDate = fileModificationDate(at: containerPath)

        return TrollStoreApp(
            id: bundleId.isEmpty ? containerPath : bundleId,
            bundleIdentifier: bundleId,
            displayName: displayName,
            version: version,
            bundlePath: appBundlePath,
            dataContainerPath: dataContainerPath,
            installDate: installDate,
            appSize: appSize,
            isTrollStore: true,
            markerType: marker
        )
    }

    /// Parses a Data container that contains a .appInfo.plist marker.
    private func parseAppInfoPlistContainer(_ containerURL: URL) -> TrollStoreApp? {
        let containerPath = containerURL.path

        let appInfoPath = (containerPath as NSString).appendingPathComponent(appInfoMarker)
        let appInfo = readPlistDictionary(at: appInfoPath)

        let bundleId = appInfo?["CFBundleIdentifier"] as? String
            ?? appInfo?["bundleIdentifier"] as? String
            ?? bundleIdFromMetadata(at: containerPath)
        let displayName = appInfo?["CFBundleDisplayName"] as? String
            ?? appInfo?["CFBundleName"] as? String
            ?? containerURL.lastPathComponent
        let version = appInfo?["CFBundleShortVersionString"] as? String
            ?? appInfo?["CFBundleVersion"] as? String
            ?? "1.0"

        if bundleId.hasPrefix("com.apple.") { return nil }

        // Try to find the matching bundle container by bundle ID.
        let bundlePath = findBundleContainer(forBundleId: bundleId)

        let appSize = calculateDirectorySize(at: containerPath)
        let installDate = fileModificationDate(at: containerPath)

        return TrollStoreApp(
            id: bundleId.isEmpty ? containerPath : bundleId,
            bundleIdentifier: bundleId,
            displayName: displayName,
            version: version,
            bundlePath: bundlePath,
            dataContainerPath: containerPath,
            installDate: installDate,
            appSize: appSize,
            isTrollStore: true,
            markerType: appInfoMarker
        )
    }

    // MARK: - Permission Check (Module 4)

    /// Tests access to key sandbox paths and returns results for each.
    public func runPermissionCheck() -> [PermissionCheckResult] {
        let testPaths = [
            "/private/var/mobile/Containers/Data/Application/",
            "/var/mobile/Containers/Data/Application/",
            "/var/containers/Bundle/Application/",
            "/private/var/containers/Bundle/Application/",
            "/var/mobile/",
            "/var/containers/",
            "/"
        ]

        var results: [PermissionCheckResult] = []

        for path in testPaths {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: path)
                results.append(PermissionCheckResult(
                    path: path,
                    isAccessible: true,
                    itemCount: contents.count,
                    error: nil
                ))
            } catch {
                results.append(PermissionCheckResult(
                    path: path,
                    isAccessible: false,
                    itemCount: 0,
                    error: error.localizedDescription
                ))
            }
        }

        return results
    }

    /// Checks whether the current process has the no-sandbox entitlement applied.
    public func hasSandboxEscape() -> Bool {
        let testPaths = [
            "/private/var/mobile/Containers/Data/Application/",
            "/var/containers/Bundle/Application/"
        ]
        for testPath in testPaths {
            do {
                _ = try fileManager.contentsOfDirectory(atPath: testPath)
                return true
            } catch {
                continue
            }
        }
        return false
    }

    // MARK: - Marker Helpers

    /// Checks whether a directory contains any of the given marker files.
    private func firstExistingMarker(in directory: String, markers: [String]) -> String {
        for marker in markers {
            let markerPath = (directory as NSString).appendingPathComponent(marker)
            if fileManager.fileExists(atPath: markerPath) {
                return marker
            }
        }
        return ""
    }

    /// Returns true if the container belongs to TrollStore / TrollStoreLite itself.
    private func isTrollStoreOwnContainer(_ containerPath: String) -> Bool {
        let trollStoreApp = (containerPath as NSString).appendingPathComponent("TrollStore.app")
        let trollStoreLiteApp = (containerPath as NSString).appendingPathComponent("TrollStoreLite.app")
        return fileManager.fileExists(atPath: trollStoreApp)
            || fileManager.fileExists(atPath: trollStoreLiteApp)
    }

    /// Finds the .app bundle inside a bundle container.
    private func findAppBundle(in containerPath: String) -> URL? {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: containerPath) else { return nil }
        for entry in entries {
            if (entry as NSString).pathExtension == "app" {
                return URL(fileURLWithPath: (containerPath as NSString).appendingPathComponent(entry))
            }
        }
        return nil
    }

    /// Finds the bundle container path for a given bundle ID by scanning the
    /// bundle container directories and reading each bundle's Info.plist.
    private func findBundleContainer(forBundleId bundleId: String) -> String {
        for basePath in bundleContainerPaths {
            guard let dirs = enumerateSubdirectories(at: basePath) else { continue }
            for dir in dirs {
                guard let appBundleURL = findAppBundle(in: dir.path) else { continue }
                let infoPlistPath = (appBundleURL.path as NSString).appendingPathComponent("Info.plist")
                let infoPlist = readPlistDictionary(at: infoPlistPath)
                if let id = infoPlist?["CFBundleIdentifier"] as? String, id == bundleId {
                    return appBundleURL.path
                }
            }
        }
        return ""
    }

    /// Reads a metadata plist to extract the bundle identifier for a data container.
    private func bundleIdFromMetadata(at containerPath: String) -> String {
        let metadataPath = (containerPath as NSString).appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist"
        )
        guard let data = fileManager.contents(atPath: metadataPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleId = plist["MCMMetadataIdentifier"] as? String else { return "" }
        return bundleId
    }

    /// Derives a fallback bundle ID from the container path's last component.
    private func bundleIdFromPath(_ path: String) -> String {
        return (path as NSString).lastPathComponent
    }

    // MARK: - File Helpers

    /// Checks if a directory exists and is accessible by listing its contents.
    private func dirExistsAndAccessible(at path: String) -> Bool {
        do {
            _ = try fileManager.contentsOfDirectory(atPath: path)
            return true
        } catch {
            return false
        }
    }

    /// Enumerates subdirectories of a given path.
    private func enumerateSubdirectories(at path: String) -> [URL]? {
        do {
            return try fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )
        } catch {
            return nil
        }
    }

    /// Reads a plist file as a dictionary.
    private func readPlistDictionary(at path: String) -> [String: Any]? {
        guard let data = fileManager.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        return plist as? [String: Any]
    }

    /// Checks if a path contains a TrollStore marker file.
    public static func isTrollStoreApp(appContainerURL: URL) -> Bool {
        let markerFiles = ["_TrollStore", "_TrollStoreLite", ".appInfo.plist"]
        for marker in markerFiles {
            let markerPath = appContainerURL.appendingPathComponent(marker).path
            if FileManager.default.fileExists(atPath: markerPath) {
                return true
            }
        }
        return false
    }

    private func fileModificationDate(at path: String) -> Date? {
        if let attrs = try? fileManager.attributesOfItem(atPath: path) {
            return attrs[.modificationDate] as? Date
        }
        return nil
    }

    private func calculateDirectorySize(at path: String) -> Int64 {
        guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }
        var totalSize: Int64 = 0
        while let element = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(element)
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
               let fileSize = attrs[.size] as? Int64 {
                totalSize += fileSize
            }
        }
        return totalSize
    }

    /// Reads a plist file and returns its deserialized content.
    public static func readPlistFile(filePath: URL) -> Any? {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return nil }
        return try? PropertyListSerialization.propertyList(
            from: Data(contentsOf: filePath),
            format: nil
        )
    }
}
