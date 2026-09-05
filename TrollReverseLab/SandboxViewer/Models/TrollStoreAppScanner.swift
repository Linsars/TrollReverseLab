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
import UIKit

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
public struct TrollStoreApp: Identifiable, Hashable, Codable {
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

    enum CodingKeys: String, CodingKey {
        case id, bundleIdentifier, displayName, version, bundlePath, dataContainerPath
        case installDate, appSize, isTrollStore, markerType
    }

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

    public var iconPaths: [String] {
        return AppIconLoader.iconPaths(forBundle: bundlePath)
    }
}

// MARK: - Diagnostics

/// Diagnostic info about the last scan — helps users troubleshoot.
public struct ScanDiagnostics: Codable {
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

    public init() {}
}

// MARK: - Permission Check Result

/// Result of a permission self-check (Module 4).
public struct PermissionCheckResult {
    public let path: String
    public let isAccessible: Bool
    public let itemCount: Int
    public let error: String?
}

// MARK: - App Icon Loader

/// Loads app icons from a .app bundle without relying on UIKit bundles.
public enum AppIconLoader {
    public static func iconPaths(forBundle bundlePath: String) -> [String] {
        let infoPath = (bundlePath as NSString).appendingPathComponent("Info.plist")
        guard let data = FileManager.default.contents(atPath: infoPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return []
        }

        var candidates: [String] = []

        // Primary: CFBundleIcons (iOS 5+)
        if let icons = plist["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            candidates.append(contentsOf: files)
        }

        // Fallback: CFBundleIconFiles
        if let files = plist["CFBundleIconFiles"] as? [String] {
            candidates.append(contentsOf: files)
        }

        // Fallback: CFBundleIconName
        if let iconName = plist["CFBundleIconName"] as? String, !candidates.contains(iconName) {
            candidates.append(iconName)
        }

        // Build full paths
        var result: [String] = []
        for name in candidates {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Try name, name@2x, name@3x
            for suffix in ["", "@2x", "@3x"] {
                let fileName = trimmed + suffix + ".png"
                let fullPath = (bundlePath as NSString).appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fullPath) {
                    result.append(fullPath)
                }
            }
            // Try as asset catalog name (AppIcon60x60@2x etc.)
            let assetPath = (bundlePath as NSString).appendingPathComponent(trimmed + ".png")
            if FileManager.default.fileExists(atPath: assetPath) && !result.contains(assetPath) {
                result.append(assetPath)
            }
        }

        return Array(result.prefix(3))
    }

    public static func loadUIImage(fromPath path: String) -> UIImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        // Use data-based decoding to avoid UIImage caching issues with sandbox paths
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return UIImage(data: data, scale: UIScreen.main.scale)
    }
}

// MARK: - Scan Cache

/// Persistent cache for scanned TrollStore apps so the UI opens instantly.
public final class TrollStoreAppCache {
    public static let shared = TrollStoreAppCache()

    private let fileManager = FileManager.default
    private var cacheDirectory: String {
        let docs = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        return (docs as NSString).appendingPathComponent("TrollReverseLab")
    }

    private var appsCachePath: String {
        return (cacheDirectory as NSString).appendingPathComponent("scannedApps.json")
    }

    private var diagnosticsCachePath: String {
        return (cacheDirectory as NSString).appendingPathComponent("scanDiagnostics.json")
    }

    private init() {
        try? fileManager.createDirectory(atPath: cacheDirectory, withIntermediateDirectories: true)
    }

    public func loadCachedApps() -> [TrollStoreApp] {
        guard let data = fileManager.contents(atPath: appsCachePath) else { return [] }
        return (try? JSONDecoder().decode([TrollStoreApp].self, from: data)) ?? []
    }

    public func saveCachedApps(_ apps: [TrollStoreApp]) {
        if let data = try? JSONEncoder().encode(apps) {
            fileManager.createFile(atPath: appsCachePath, contents: data, attributes: nil)
        }
    }

    public func loadCachedDiagnostics() -> ScanDiagnostics? {
        guard let data = fileManager.contents(atPath: diagnosticsCachePath) else { return nil }
        return try? JSONDecoder().decode(ScanDiagnostics.self, from: data)
    }

    public func saveCachedDiagnostics(_ diagnostics: ScanDiagnostics) {
        if let data = try? JSONEncoder().encode(diagnostics) {
            fileManager.createFile(atPath: diagnosticsCachePath, contents: data, attributes: nil)
        }
    }
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
    /// true = 全量模式：不做 TrollStore marker 过滤、不剔 Apple 应用
    public var includeAllApps: Bool = false

    public init() {}

    // MARK: - Public Scan API

    /// Async scan that returns results on a background queue and calls completion on main.
    public func scanTrollStoreAppsAsync(completion: @escaping ([TrollStoreApp], ScanDiagnostics) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let apps = self.scanTrollStoreApps()
            let diag = self.diagnostics
            DispatchQueue.main.async {
                completion(apps, diag)
            }
        }
    }

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
            let apps = scanBundleContainers(at: basePath, dataContainerMap: dataContainerMap)
            for app in apps where !seenBundleIDs.contains(app.bundleIdentifier) {
                results.append(app)
                seenBundleIDs.insert(app.bundleIdentifier)
            }
        }

        // 2. SECONDARY: Scan data containers for .appInfo.plist.
        for basePath in dataContainerPaths {
            if !diagnostics.pathsScanned.contains(basePath) {
                diagnostics.pathsScanned.append(basePath)
            }
            let apps = scanDataContainersForAppInfo(at: basePath)
            for app in apps where !seenBundleIDs.contains(app.bundleIdentifier) {
                results.append(app)
                seenBundleIDs.insert(app.bundleIdentifier)
            }
        }

        diagnostics.scanDuration = CFAbsoluteTimeGetCurrent() - startTime

        let sorted = results.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        // Persist immediately
        TrollStoreAppCache.shared.saveCachedApps(sorted)
        TrollStoreAppCache.shared.saveCachedDiagnostics(diagnostics)

        return sorted
    }

    // MARK: - Bundle Container Scanning

    private func scanBundleContainers(
        at basePath: String,
        dataContainerMap: [String: String]
    ) -> [TrollStoreApp] {
        guard dirExistsAndAccessible(at: basePath) else {
            diagnostics.errors.append("无法访问 bundle 容器根目录: \(basePath)")
            return []
        }

        guard let allDirs = enumerateSubdirectories(at: basePath) else {
            diagnostics.permissionError = SandboxPermissionError.noSandboxEscape(path: basePath).localizedDescription
            diagnostics.canAccessSandbox = false
            return []
        }

        diagnostics.totalDirsScanned += allDirs.count

        // Process in parallel for speed; accumulate local results per task.
        let lock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        var results: [TrollStoreApp] = []

        for dir in allDirs {
            group.enter()
            queue.async { [weak self] in
                defer { group.leave() }
                guard let self = self else { return }

                let dirPath = dir.path
                let marker = self.firstExistingMarker(in: dirPath, markers: self.trollStoreMarkers)

                // 全量模式：无 marker 也进列表（markerType 标 "all"）
                if marker.isEmpty && !self.includeAllApps { return }

                if !marker.isEmpty {
                    lock.lock()
                    self.diagnostics.markerFilesFound += 1
                    lock.unlock()
                }

                // 全量模式下不排除 TrollStore 自身容器
                if !self.includeAllApps && self.isTrollStoreOwnContainer(dirPath) {
                    lock.lock()
                    self.diagnostics.skippedContainers += 1
                    lock.unlock()
                    return
                }

                let effectiveMarker = marker.isEmpty ? "all" : marker
                if let app = self.parseBundleContainer(dir, marker: effectiveMarker, dataContainerMap: dataContainerMap) {
                    lock.lock()
                    results.append(app)
                    self.diagnostics.trollStoreApps += 1
                    lock.unlock()
                }
            }
        }
        group.wait()
        return results
    }

    // MARK: - Data Container (.appInfo.plist) Scanning

    private func scanDataContainersForAppInfo(
        at basePath: String
    ) -> [TrollStoreApp] {
        guard let allDirs = enumerateSubdirectories(at: basePath) else { return [] }
        if !diagnostics.canAccessSandbox {
            diagnostics.canAccessSandbox = true
        }
        diagnostics.totalDirsScanned += allDirs.count

        let lock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        var results: [TrollStoreApp] = []

        for dir in allDirs {
            group.enter()
            queue.async { [weak self] in
                defer { group.leave() }
                guard let self = self else { return }

                let appInfoPath = (dir.path as NSString).appendingPathComponent(self.appInfoMarker)
                guard self.fileManager.fileExists(atPath: appInfoPath) else { return }

                lock.lock()
                self.diagnostics.markerFilesFound += 1
                lock.unlock()

                if let app = self.parseAppInfoPlistContainer(dir) {
                    lock.lock()
                    results.append(app)
                    self.diagnostics.trollStoreApps += 1
                    lock.unlock()
                }
            }
        }
        group.wait()
        return results
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

        // Skip Apple system apps only in TrollStore-only mode.
        if !includeAllApps && bundleId.hasPrefix("com.apple.") { return nil }

        // Locate the matching data container.
        let dataContainerPath = dataContainerMap[bundleId] ?? ""

        // Calculate size on a background queue to keep scanning fast; default to 0 here.
        let appSize: Int64 = 0
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
            isTrollStore: marker != "all",   // "all" = 全量模式下的非巨魔应用
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

        let appSize: Int64 = 0
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

    // MARK: - Async Size Calculation

    /// Calculates the size of an installed app asynchronously.
    public static func calculateAppSizeAsync(for app: TrollStoreApp, completion: @escaping (Int64) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            var total: Int64 = 0
            for path in [app.bundlePath, app.dataContainerPath] where !path.isEmpty {
                total += calculateDirectorySize(at: path, fileManager: fileManager)
            }
            DispatchQueue.main.async { completion(total) }
        }
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

    private static func calculateDirectorySize(at path: String, fileManager: FileManager = FileManager.default) -> Int64 {
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
