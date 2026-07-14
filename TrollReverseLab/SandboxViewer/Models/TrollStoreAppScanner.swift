//
//  TrollStoreAppScanner.swift
//  TrollReverseLab
//
//  Module 1: Scans iOS Data container directory for TrollStore-installed
//  applications. Uses .appInfo.plist marker file to identify TrollStore apps.
//
//  INTEGRATED FROM: FilzaEscaped sandbox traversal logic (Material 1)
//  - Only scans /private/var/mobile/Containers/Data/Application/
//  - Uses .appInfo.plist as TrollStore app marker
//  - Catches sandbox permission errors with actionable messages
//  - NO /var/jb jailbreak paths (pure TrollStore, no jailbreak)
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
    public let bundlePath: String          // Path to the .app bundle (may be empty if not found)
    public let dataContainerPath: String    // Path to the data sandbox container
    public let installDate: Date?
    public let appSize: Int64
    public let isTrollStore: Bool

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

/// Scanner that discovers TrollStore-installed applications by reading the
/// Data container directory and checking for .appInfo.plist marker files.
///
/// Based on FilzaEscaped sandbox traversal logic:
/// - Scans ONLY /private/var/mobile/Containers/Data/Application/
/// - Identifies TrollStore apps via .appInfo.plist marker
/// - Catches permission errors and surfaces actionable messages
public final class TrollStoreAppScanner {

    /// The sole scan path — pure TrollStore, no jailbreak paths.
    private let dataContainerPath = "/private/var/mobile/Containers/Data/Application/"

    private let fileManager = FileManager.default
    public private(set) var diagnostics = ScanDiagnostics()

    public init() {}

    // MARK: - Public Scan API

    /// Scans the Data container directory for TrollStore-installed apps.
    /// Throws SandboxPermissionError if the app lacks sandbox escape entitlements.
    public func scanTrollStoreApps() -> [TrollStoreApp] {
        diagnostics = ScanDiagnostics()
        let startTime = CFAbsoluteTimeGetCurrent()
        var results: [TrollStoreApp] = []

        diagnostics.pathsScanned.append(dataContainerPath)

        do {
            let allDirs = try fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: dataContainerPath),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )

            diagnostics.canAccessSandbox = true
            diagnostics.totalDirsScanned = allDirs.count

            for dir in allDirs {
                let appInfoPlist = dir.appendingPathComponent(".appInfo.plist")

                // Only include TrollStore-installed apps (marker file check)
                if fileManager.fileExists(atPath: appInfoPlist.path) {
                    diagnostics.markerFilesFound += 1

                    if let app = parseApp(at: dir) {
                        results.append(app)
                        diagnostics.trollStoreApps += 1
                    }
                }
            }
        } catch {
            // Permission denied — IPA is missing no-sandbox entitlement
            diagnostics.canAccessSandbox = false
            diagnostics.permissionError = SandboxPermissionError.noSandboxEscape(path: dataContainerPath).localizedDescription
            diagnostics.errors.append("无法访问: \(dataContainerPath)\n原因: \(error.localizedDescription)")
        }

        diagnostics.scanDuration = CFAbsoluteTimeGetCurrent() - startTime

        return results.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    // MARK: - Permission Check (Module 4)

    /// Tests access to key sandbox paths and returns results for each.
    /// Used by the Permission Self-Check module to diagnose entitlement issues.
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
    /// Uses contentsOfDirectory (not just fileExists) because the latter can return
    /// true for paths the sandbox still blocks from listing.
    public func hasSandboxEscape() -> Bool {
        let testPath = "/private/var/mobile/Containers/Data/Application/"
        do {
            _ = try fileManager.contentsOfDirectory(atPath: testPath)
            return true
        } catch {
            return false
        }
    }

    // MARK: - App Parsing

    /// Parses a data container directory into a TrollStoreApp.
    private func parseApp(at containerURL: URL) -> TrollStoreApp? {
        let containerPath = containerURL.path

        // Read MCM metadata plist to get bundle ID
        let metadataPath = (containerPath as NSString).appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist"
        )

        var bundleId = "unknown"
        var displayName = containerURL.lastPathComponent
        var version = "1.0"

        if let data = fileManager.contents(atPath: metadataPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            if let id = plist["MCMMetadataIdentifier"] as? String {
                bundleId = id
            }
        }

        // Read .appInfo.plist for additional info
        let appInfoPath = (containerPath as NSString).appendingPathComponent(".appInfo.plist")
        if let data = fileManager.contents(atPath: appInfoPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            if let name = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String {
                displayName = name
            }
            if let ver = plist["CFBundleShortVersionString"] as? String {
                version = ver
            }
            if let id = plist["CFBundleIdentifier"] as? String, bundleId == "unknown" {
                bundleId = id
            }
        }

        // Skip Apple system apps
        if bundleId.hasPrefix("com.apple.") {
            return nil
        }

        // Try to find bundle path from Info.plist in container
        var bundlePath = ""
        let infoPlistPath = (containerPath as NSString).appendingPathComponent("BundleInfo.plist")
        if let data = fileManager.contents(atPath: infoPlistPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let bundleURL = plist["CDBundlePath"] as? String {
            bundlePath = bundleURL
        }

        // Calculate container size
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
            isTrollStore: true
        )
    }

    // MARK: - File Helpers

    /// Checks if a path contains the .appInfo.plist TrollStore marker.
    public static func isTrollStoreApp(appContainerURL: URL) -> Bool {
        let markerFile = appContainerURL.appendingPathComponent(".appInfo.plist")
        return FileManager.default.fileExists(atPath: markerFile.path)
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

    // MARK: - Plist/JSON Reader (from Material 1)

    /// Reads a plist file and returns its deserialized content.
    public static func readPlistFile(filePath: URL) -> Any? {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return nil }
        return try? PropertyListSerialization.propertyList(
            from: Data(contentsOf: filePath),
            format: nil
        )
    }
}
