//
//  AppBackupView.swift
//  TrollReverseLab
//
//  App data backup management UI.
//  Create, restore, and delete backups of TrollStore app data containers.
//

import SwiftUI

/// Backup management view — accessible from settings or app list.
struct AppBackupView: View {
    @EnvironmentObject var backupManager: AppBackupManager
    @EnvironmentObject var appScanner: AppScannerViewModel
    @State private var showAppPicker = false
    @State private var selectedApp: TrollStoreApp?

    var body: some View {
        Form {
            // MARK: - Auto Backup Setting
            Section(header: Text("自动备份"), footer: Text("AI 脚本执行前自动备份应用数据")) {
                Toggle("启用自动备份", isOn: Binding(
                    get: { backupManager.autoBackupEnabled },
                    set: { backupManager.setAutoBackup($0) }
                ))
            }

            // MARK: - Create Backup
            Section(header: Text("创建备份")) {
                Button {
                    showAppPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("选择应用进行备份")
                    }
                }

                if let app = selectedApp {
                    HStack {
                        AppIconView(bundlePath: app.bundlePath)
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                                .font(.subheadline)
                            Text(app.bundleIdentifier)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("备份") {
                            backupManager.backup(app: app, isAuto: false)
                            selectedApp = nil
                        }
                        .buttonStyle(DefaultButtonStyle())
                    }
                }
            }

            // MARK: - Status
            if case .backingUp(let progress) = backupManager.status {
                Section {
                    VStack {
                        ProgressView(value: progress)
                        Text("正在备份...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if case .restoring(let progress) = backupManager.status {
                Section {
                    VStack {
                        ProgressView(value: progress)
                        Text("正在还原...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if case .completed(let msg) = backupManager.status {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.caption)
                    }
                }
            } else if case .failed(let msg) = backupManager.status {
                Section {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(msg)
                            .font(.caption)
                    }
                }
            }

            // MARK: - Backup List
            if backupManager.backups.isEmpty {
                Section {
                    Text("暂无备份记录")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            } else {
                // Summary
                Section(header: Text("备份汇总")) {
                    HStack {
                        Text("备份总数")
                        Spacer()
                        Text("\(backupManager.backups.count)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("总占用空间")
                        Spacer()
                        Text(formatSize(backupManager.totalBackupSize)).foregroundColor(.secondary)
                    }
                }

                // Group by app
                ForEach(groupedBackups, id: \.key) { group in
                    Section(header: Text("\(group.key) (\(group.value.count))")) {
                        ForEach(group.value) { backup in
                            BackupRowView(backup: backup) {
                                backupManager.deleteBackup(backup)
                            } onRestore: {
                                backupManager.restore(backup: backup)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("备份管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(
                apps: appScanner.apps,
                selectedApp: $selectedApp,
                isPresented: $showAppPicker
            )
        }
    }

    // MARK: - Helpers

    private var groupedBackups: [(key: String, value: [AppBackupRecord])] {
        let groups = Dictionary(grouping: backupManager.backups, by: { $0.displayName })
        return groups.sorted { $0.key < $1.key }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Backup Row

struct BackupRowView: View {
    let backup: AppBackupRecord
    let onDelete: () -> Void
    let onRestore: () -> Void
    @State private var showConfirmRestore = false
    @State private var showConfirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if backup.isAuto {
                            Text("自动")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(3)
                        }
                        Text(backup.note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("v\(backup.version) · \(backup.formattedSize) · \(backup.fileCount) 文件")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(backup.formattedDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Menu {
                    Button {
                        showConfirmRestore = true
                    } label: {
                        Label("还原", systemImage: "arrow.uturn.backward")
                    }

                    Button {
                        showConfirmDelete = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .alert(isPresented: $showConfirmRestore) {
            Alert(
                title: Text("确认还原"),
                message: Text("这将用备份数据覆盖 \(backup.displayName) 的当前数据。应用当前数据将被替换。确定继续？"),
                primaryButton: .destructive(Text("还原")) { onRestore() },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert(isPresented: $showConfirmDelete) {
            Alert(
                title: Text("确认删除"),
                message: Text("删除备份后无法恢复。确定删除？"),
                primaryButton: .destructive(Text("删除")) { onDelete() },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }
}
