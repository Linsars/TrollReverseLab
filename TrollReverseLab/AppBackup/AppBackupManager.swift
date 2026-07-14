//
//  AppBackupManager.swift
//  TrollReverseLab
//
//  Manages app data backup and restore operations.
//  Backs up TrollStore app data containers to local storage.
//  Supports manual and automatic (pre-AI) backups.
//

import Foundation
import SwiftUI

/// Manages app data backup/restore operations.
public final class AppBackupManager: ObservableObject {

    @Published public var backups: [AppBackupRecord] = []
    @Published public var status: BackupStatus = .idle
    @Published public var autoBackupEnabled = true

    private let fileManager = FileManager.default
    private let backupsMetadataFile: String
    private let backupsRootDir: String

    public init() {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        backupsRootDir = (docs as NSString).appendingPathComponent("AppBackups")
        backupsMetadataFile = (backupsRootDir as NSString).appendingPathComponent("backups_metadata.json")

        try? fileManager.createDirectory(atPath: backupsRootDir, withIntermediateDirectories: true)
        autoBackupEnabled = UserDefaults.standard.bool(forKey: "auto_backup_enabled")
        loadBackups()
    }

    // MARK: - Backup

    /// Creates a backup of the given app's data container.
    public func backup(app: TrollStoreApp, isAuto: Bool = false, note: String = "") {
        guard !app.dataContainerPath.isEmpty else {
            status = .failed(message: "应用数据容器路径为空")
            return
        }

        guard fileManager.fileExists(atPath: app.dataContainerPath) else {
            status = .failed(message: "数据容器不存在: \(app.dataContainerPath)")
            return
        }

        status = .backingUp(progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let timestamp = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestampStr = formatter.string(from: timestamp)

            let safeBundleId = app.bundleIdentifier.replacingOccurrences(of: ".", with: "_")
            let backupDir = (self.backupsRootDir as NSString)
                .appendingPathComponent("\(safeBundleId)_\(timestampStr)")

            do {
                try self.fileManager.createDirectory(atPath: backupDir, withIntermediateDirectories: true)

                // Copy the data container
                let (size, fileCount) = self.copyDirectory(
                    from: app.dataContainerPath,
                    to: backupDir
                )

                let record = AppBackupRecord(
                    bundleId: app.bundleIdentifier,
                    displayName: app.displayName,
                    version: app.version,
                    backupPath: backupDir,
                    sourcePath: app.dataContainerPath,
                    timestamp: timestamp,
                    size: size,
                    fileCount: fileCount,
                    isAuto: isAuto,
                    note: note.isEmpty ? (isAuto ? "AI 操作前自动备份" : "手动备份") : note
                )

                DispatchQueue.main.async {
                    self.backups.insert(record, at: 0)
                    self.saveBackups()
                    self.status = .completed(message: "备份成功: \(app.displayName) (\(record.formattedSize))")
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .failed(message: "备份失败: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Restore

    /// Restores a backup to the original app's data container.
    public func restore(backup: AppBackupRecord) {
        guard fileManager.fileExists(atPath: backup.backupPath) else {
            status = .failed(message: "备份文件不存在")
            return
        }

        guard !backup.sourcePath.isEmpty else {
            status = .failed(message: "原始路径为空")
            return
        }

        status = .restoring(progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // Clear existing data in the source directory (except the directory itself)
                let contents = try self.fileManager.contentsOfDirectory(atPath: backup.sourcePath)
                for item in contents {
                    let itemPath = (backup.sourcePath as NSString).appendingPathComponent(item)
                    try? self.fileManager.removeItem(atPath: itemPath)
                }

                // Copy backup files back
                let (_, _) = self.copyDirectory(
                    from: backup.backupPath,
                    to: backup.sourcePath
                )

                DispatchQueue.main.async {
                    self.status = .completed(message: "还原成功: \(backup.displayName)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .failed(message: "还原失败: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Delete

    public func deleteBackup(_ backup: AppBackupRecord) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(atPath: backup.backupPath)

            DispatchQueue.main.async {
                self.backups.removeAll { $0.id == backup.id }
                self.saveBackups()
            }
        }
    }

    // MARK: - Auto Backup

    /// Creates an automatic backup before AI script execution.
    public func autoBackupIfNeeded(for app: TrollStoreApp) {
        guard autoBackupEnabled else { return }
        backup(app: app, isAuto: true, note: "AI 脚本执行前自动备份")
    }

    public func setAutoBackup(_ enabled: Bool) {
        autoBackupEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "auto_backup_enabled")
    }

    // MARK: - Query

    public func backupsForApp(bundleId: String) -> [AppBackupRecord] {
        backups.filter { $0.bundleId == bundleId }
    }

    public var totalBackupSize: Int64 {
        backups.reduce(0) { $0 + $1.size }
    }

    // MARK: - Private Helpers

    /// Recursively copies a directory and returns (totalSize, fileCount).
    private func copyDirectory(from source: String, to destination: String) -> (Int64, Int) {
        var totalSize: Int64 = 0
        var fileCount = 0

        guard let enumerator = fileManager.enumerator(atPath: source) else {
            return (0, 0)
        }

        while let item = enumerator.nextObject() as? String {
            let sourcePath = (source as NSString).appendingPathComponent(item)
            let destPath = (destination as NSString).appendingPathComponent(item)

            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: sourcePath, isDirectory: &isDir) {
                if isDir.boolValue {
                    try? fileManager.createDirectory(atPath: destPath, withIntermediateDirectories: true)
                } else {
                    // Create parent directory if needed
                    let parentDir = (destPath as NSString).deletingLastPathComponent
                    try? fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

                    if let attrs = try? fileManager.attributesOfItem(atPath: sourcePath) {
                        if let size = attrs[.size] as? Int64 {
                            totalSize += size
                        }
                    }
                    try? fileManager.copyItem(atPath: sourcePath, toPath: destPath)
                    fileCount += 1

                    // Update progress periodically
                    if fileCount % 50 == 0 {
                        let progress = min(Double(fileCount) / 1000.0, 0.95)
                        DispatchQueue.main.async {
                            self.status = .backingUp(progress: progress)
                        }
                    }
                }
            }
        }

        return (totalSize, fileCount)
    }

    // MARK: - Persistence

    private func saveBackups() {
        if let data = try? JSONEncoder().encode(backups) {
            try? data.write(to: URL(fileURLWithPath: backupsMetadataFile))
        }
    }

    private func loadBackups() {
        guard let data = fileManager.contents(atPath: backupsMetadataFile),
              let decoded = try? JSONDecoder().decode([AppBackupRecord].self, from: data) else {
            return
        }
        backups = decoded
    }
}
