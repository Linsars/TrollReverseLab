//
//  TrollStoreAppScanner.swift
//  TrollReverseLab
//
//  Module 1: Scans /var/mobile/Containers/Data/Application/ for TrollStore
//  applications by detecting .appInfo.plist markers.
//
//  CONSTRAINT: Read-only scanning for local research. No modification of
//  system data or third-party app store applications.
//

import Foundation

/// Represents a TrollStore-installed application discovered on the device.
public struct TrollStoreApp: Identifiable, Hashable {
    public let id: String
    public let bundleIdentifier: String
    public let displayName: String
    public let version: String
    public let containerPath: String
    public let installDate: Date?
    public let appSize: Int64

    public var documentsPath: String {
        (containerPath as NSString).appendingPathComponent("Documents")
    }

    public var libraryPath: String {
        (containerPath as NSString).appendingPathComponent("Library")
    }

    public var preferencesPath: String {
        (libraryPath as NSString).appendingPathComponent("Preferences")
    }
}

/// Scanner that discovers TrollStore applications by reading the application
/// containers directory and filtering for .appInfo.plist markers.
public final class TrollStoreAppScanner {

    private let containersPath = "/var/mobile/Containers/Data/Application"
    private let fileManager = FileManager.default

    public init() {}

    /// Scans all application containers and returns only those identified
    /// as TrollStore installations (presence of .appInfo.plist).
    public func scanTrollStoreApps() -> [TrollStoreApp] {
        guard let containerDirs = try? fileManager.contentsOfDirectory(atPath: containersPath) else {
            return []
        }

        var apps: [TrollStoreApp] = []

        for dir in containerDirs {
            let containerPath = (containersPath as NSString).appendingPathComponent(dir)
            let appInfoPath = (containerPath as NSString).appendingPathComponent(".appInfo.plist")

            // Only process directories with .appInfo.plist (TrollStore marker)
            guard fileManager.fileExists(atPath: appInfoPath) else { continue }

            if let app = parseAppInfo(at: containerPath, appInfoPath: appInfoPath) {
                apps.append(app)
            }
        }

        return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Parses the .appInfo.plist to extract application metadata.
    private func parseAppInfo(at containerPath: String, appInfoPath: String) -> TrollStoreApp? {
        guard let plistData = FileManager.default.contents(atPath: appInfoPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return nil
        }

        let bundleId = plist["CFBundleIdentifier"] as? String ?? "unknown"
        let displayName = plist["CFBundleDisplayName"] as? String
            ?? plist["CFBundleName"] as? String
            ?? bundleId
        let version = plist["CFBundleShortVersionString"] as? String ?? "1.0"

        let installDate = parseInstallDate(from: plist)
        let appSize = calculateDirectorySize(at: containerPath)

        return TrollStoreApp(
            id: bundleId,
            bundleIdentifier: bundleId,
            displayName: displayName,
            version: version,
            containerPath: containerPath,
            installDate: installDate,
            appSize: appSize
        )
    }

    private func parseInstallDate(from plist: [String: Any]) -> Date? {
        // TrollStore stores install timestamp in .appInfo.plist
        if let timestamp = plist["TSInstallDate"] as? Double {
            return Date(timeIntervalSince1970: timestamp)
        }
        // Fallback: use file attributes
        return nil
    }

    /// Recursively calculates the total size of an app container directory.
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
