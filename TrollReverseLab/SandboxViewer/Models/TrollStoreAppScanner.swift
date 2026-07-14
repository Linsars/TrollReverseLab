//
//  TrollStoreAppScanner.swift
//  TrollReverseLab
//
//  Module 1: Scans iOS Bundle and Data container directories for installed
//  applications. Identifies TrollStore apps by checking entitlements.
//  Supports both rootful and rootless (/var/jb) jailbreak layouts.
//
//  CONSTRAINT: Read-only scanning for local research. No modification of
//  system data or third-party app store applications.
//

import Foundation
import Security

/// Represents an installed application discovered on the device.
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

    /// Primary container path (prefers data container if available, else bundle)
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

/// Diagnostic info about the last scan — helps users troubleshoot when no apps are found.
public struct ScanDiagnostics {
    public var pathsScanned: [String] = []
    public var totalBundleDirs: Int = 0
    public var totalAppsFound: Int = 0
    public var trollStoreApps: Int = 0
    public var thirdPartyApps: Int = 0
    public var systemAppsFiltered: Int = 0
    public var errors: [String] = []
    public var dataContainersFound: Int = 0
}

/// Scanner that discovers installed applications by reading Bundle and Data
/// container directories. Identifies TrollStore apps via entitlements.
public final class TrollStoreAppScanner {

    // Scan paths for both standard and rootless jailbreak layouts
    private let bundlePaths = [
        "/var/containers/Bundle/Application",
        "/var/jb/var/containers/Bundle/Application",
        "/private/var/containers/Bundle/Application"
    ]
    private let dataPaths = [
        "/var/mobile/Containers/Data/Application",
        "/var/jb/var/mobile/Containers/Data/Application",
        "/private/var/mobile/Containers/Data/Application"
    ]

    private let fileManager = FileManager.default
    public private(set) var diagnostics = ScanDiagnostics()

    public init() {}

    /// Scans all application containers and returns third-party apps,
    /// marking those installed via TrollStore.
    public func scanTrollStoreApps() -> [TrollStoreApp] {
        diagnostics = ScanDiagnostics()
        var results: [TrollStoreApp] = []

        // Step 1: Scan bundle directories for .app bundles
        var appBundles: [(path: String, infoPlist: [String: Any])] = []
        var dataContainerMap: [String: String] = [:]  // bundleId -> dataPath

        // Scan Bundle directories
        for bundleBasePath in bundlePaths {
            diagnostics.pathsScanned.append("Bundle: \(bundleBasePath)")
            guard let appDirs = try? fileManager.contentsOfDirectory(atPath: bundleBasePath) else {
                diagnostics.errors.append("无法访问: \(bundleBasePath)")
                continue
            }
            diagnostics.totalBundleDirs += appDirs.count

            for appDir in appDirs {
                let fullDir = (bundleBasePath as NSString).appendingPathComponent(appDir)
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: fullDir, isDirectory: &isDir), isDir.boolValue else { continue }

                // Find .app bundle inside
                guard let contents = try? fileManager.contentsOfDirectory(atPath: fullDir) else { continue }
                for content in contents where content.hasSuffix(".app") {
                    let appPath = (fullDir as NSString).appendingPathComponent(content)
                    let infoPlistPath = (appPath as NSString).appendingPathComponent("Info.plist")

                    guard let data = fileManager.contents(atPath: infoPlistPath),
                          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                        continue
                    }
                    appBundles.append((appPath, plist))
                }
            }
        }

        // Step 2: Scan Data container directories and map by bundle ID
        for dataBasePath in dataPaths {
            diagnostics.pathsScanned.append("Data: \(dataBasePath)")
            guard let dataDirs = try? fileManager.contentsOfDirectory(atPath: dataBasePath) else {
                diagnostics.errors.append("无法访问: \(dataBasePath)")
                continue
            }

            for dir in dataDirs {
                let containerPath = (dataBasePath as NSString).appendingPathComponent(dir)

                // Method 1: Read metadata plist (standard iOS)
                let metadataPath = (containerPath as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                if let data = fileManager.contents(atPath: metadataPath),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let bundleId = plist["MCMMetadataIdentifier"] as? String {
                    dataContainerMap[bundleId] = containerPath
                    continue
                }

                // Method 2: Try without leading dot
                let metadataPath2 = (containerPath as NSString).appendingPathComponent("com.apple.mobile_container_manager.metadata.plist")
                if let data = fileManager.contents(atPath: metadataPath2),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let bundleId = plist["MCMMetadataIdentifier"] as? String {
                    dataContainerMap[bundleId] = containerPath
                    continue
                }

                // Method 3: Check for .appInfo.plist (some TrollStore setups)
                let appInfoPath = (containerPath as NSString).appendingPathComponent(".appInfo.plist")
                if fileManager.fileExists(atPath: appInfoPath) {
                    if let data = fileManager.contents(atPath: appInfoPath),
                       let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let bundleId = plist["CFBundleIdentifier"] as? String {
                        dataContainerMap[bundleId] = containerPath
                    }
                }
            }
        }
        diagnostics.dataContainersFound = dataContainerMap.count

        // Step 3: Build TrollStoreApp list
        for (bundlePath, infoPlist) in appBundles {
            let bundleId = infoPlist["CFBundleIdentifier"] as? String ?? "unknown"

            // Skip Apple system apps
            if bundleId.hasPrefix("com.apple.") {
                diagnostics.systemAppsFiltered += 1
                continue
            }

            // Skip placeholder/system web clips
            if bundleId.hasPrefix("com.apple.WebKit.") || bundleId.hasPrefix("com.apple.webapp") {
                diagnostics.systemAppsFiltered += 1
                continue
            }

            let displayName = infoPlist["CFBundleDisplayName"] as? String
                ?? infoPlist["CFBundleName"] as? String
                ?? bundleId
            let version = infoPlist["CFBundleShortVersionString"] as? String ?? "1.0"

            let dataPath = dataContainerMap[bundleId] ?? ""

            // Detect TrollStore installation
            let isTrollStore = detectTrollStoreApp(at: bundlePath, bundleId: bundleId, infoPlist: infoPlist)

            let appSize = calculateDirectorySize(at: bundlePath)
            let installDate = fileModificationDate(at: bundlePath)

            results.append(TrollStoreApp(
                id: bundleId,
                bundleIdentifier: bundleId,
                displayName: displayName,
                version: version,
                bundlePath: bundlePath,
                dataContainerPath: dataPath,
                installDate: installDate,
                appSize: appSize,
                isTrollStore: isTrollStore
            ))

            diagnostics.thirdPartyApps += 1
            if isTrollStore {
                diagnostics.trollStoreApps += 1
            }
        }

        diagnostics.totalAppsFound = results.count

        return results.sorted { a, b in
            if a.isTrollStore != b.isTrollStore {
                return a.isTrollStore  // TrollStore apps first
            }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// Detects whether an app was installed via TrollStore by checking its entitlements.
    private func detectTrollStoreApp(at appPath: String, bundleId: String, infoPlist: [String: Any]) -> Bool {
        // Method 1: Use Security framework to read entitlements (most reliable)
        if let entitlements = readEntitlementsViaSecurityFramework(at: appPath) {
            return checkTrollStoreEntitlements(entitlements)
        }

        // Method 2: Search binary for TrollStore-specific entitlement strings
        if let binaryPath = findMainBinary(at: appPath),
           let binaryData = fileManager.contents(atPath: binaryPath) {
            return checkTrollStoreEntitlementsInBinary(binaryData)
        }

        // Method 3: Check if app has get-task-allow in Info.plist (TrollStore sets this)
        if let getTaskAllow = infoPlist["get-task-allow"] as? Bool, getTaskAllow {
            return true
        }

        return false
    }

    /// Reads entitlements using the Security framework (SecStaticCode).
    private func readEntitlementsViaSecurityFramework(at appPath: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: appPath)
        var staticCode: SecStaticCode?
        let createResult = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(rawValue: 0), &staticCode)
        guard createResult == errSecSuccess, let code = staticCode else { return nil }

        var signingInfo: CFDictionary?
        let flags: SecCSFlags = [.requireEntitlements, .getSecurityInformation]
        let copyResult = SecCodeCopySigningInformation(code, flags, &signingInfo)
        guard copyResult == errSecSuccess, let info = signingInfo as? [String: Any] else { return nil }

        // kSecCodeInfoEntitlementsDict may be present
        if let entitlements = info["entitlements"] as? [String: Any] {
            return entitlements
        }
        if let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
            return entitlements
        }
        return nil
    }

    /// Checks if the entitlements dict contains TrollStore-specific keys.
    private func checkTrollStoreEntitlements(_ entitlements: [String: Any]) -> Bool {
        let trollStoreKeys = [
            "com.apple.private.security.no-sandbox",
            "com.apple.private.security.container-required",
            "com.apple.developer.kernel.increased-memory-limit",
            "com.apple.security.cs.disable-library-validation",
            "com.apple.security.cs.allow-dyld-environment-variables",
            "com.apple.security.cs.allow-jit",
            "com.apple.security.cs.disable-executable-page-protection",
            "platform-application",
            "com.apple.private.tcc.allow"
        ]
        for key in trollStoreKeys {
            if entitlements[key] != nil {
                return true
            }
        }
        return false
    }

    /// Fallback: searches binary data for TrollStore entitlement strings.
    private func checkTrollStoreEntitlementsInBinary(_ data: Data) -> Bool {
        let searchStrings = [
            "com.apple.private.security.no-sandbox",
            "platform-application",
            "com.apple.security.cs.disable-library-validation"
        ]
        for searchString in searchStrings {
            if let searchData = searchString.data(using: .utf8),
               data.range(of: searchData) != nil {
                return true
            }
        }
        return false
    }

    /// Finds the main executable binary inside a .app bundle.
    private func findMainBinary(at appPath: String) -> String? {
        // Read Info.plist for CFBundleExecutable
        let infoPlistPath = (appPath as NSString).appendingPathComponent("Info.plist")
        if let data = fileManager.contents(atPath: infoPlistPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let executable = plist["CFBundleExecutable"] as? String {
            let binaryPath = (appPath as NSString).appendingPathComponent(executable)
            if fileManager.fileExists(atPath: binaryPath) {
                return binaryPath
            }
        }

        // Fallback: use app bundle name (without .app)
        let appName = (appPath as NSString).lastPathComponent
        let binaryName = appName.replacingOccurrences(of: ".app", with: "")
        let binaryPath = (appPath as NSString).appendingPathComponent(binaryName)
        if fileManager.fileExists(atPath: binaryPath) {
            return binaryPath
        }

        // Fallback: find first executable file
        if let contents = try? fileManager.contentsOfDirectory(atPath: appPath) {
            for content in contents {
                let fullPath = (appPath as NSString).appendingPathComponent(content)
                if fileManager.isExecutableFile(atPath: fullPath) {
                    return fullPath
                }
            }
        }

        return nil
    }

    /// Gets the file modification date (used as install date approximation).
    private func fileModificationDate(at path: String) -> Date? {
        if let attrs = try? fileManager.attributesOfItem(atPath: path) {
            return attrs[.modificationDate] as? Date
        }
        return nil
    }

    /// Recursively calculates the total size of a directory.
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
}
