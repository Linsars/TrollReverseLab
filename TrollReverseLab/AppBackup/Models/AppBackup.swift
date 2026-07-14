//
//  AppBackup.swift
//  TrollReverseLab
//
//  App data backup/restore data model.
//  Stores metadata about each backup point created from a TrollStore app's
//  data container.
//

import Foundation

/// Represents a backup of a TrollStore app's data container.
public struct AppBackupRecord: Identifiable, Codable, Hashable {
    public let id: UUID
    public let bundleId: String
    public let displayName: String
    public let version: String
    public let backupPath: String
    public let sourcePath: String
    public let timestamp: Date
    public let size: Int64
    public let fileCount: Int
    public let isAuto: Bool
    public let note: String

    public init(
        id: UUID = UUID(),
        bundleId: String,
        displayName: String,
        version: String,
        backupPath: String,
        sourcePath: String,
        timestamp: Date = Date(),
        size: Int64 = 0,
        fileCount: Int = 0,
        isAuto: Bool = false,
        note: String = ""
    ) {
        self.id = id
        self.bundleId = bundleId
        self.displayName = displayName
        self.version = version
        self.backupPath = backupPath
        self.sourcePath = sourcePath
        self.timestamp = timestamp
        self.size = size
        self.fileCount = fileCount
        self.isAuto = isAuto
        self.note = note
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

/// Backup operation status.
public enum BackupStatus: Equatable {
    case idle
    case backingUp(progress: Double)
    case restoring(progress: Double)
    case completed(message: String)
    case failed(message: String)

    public var isInProgress: Bool {
        switch self {
        case .backingUp, .restoring: return true
        default: return false
        }
    }
}
