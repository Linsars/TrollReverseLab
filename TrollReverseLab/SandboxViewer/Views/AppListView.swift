//
//  AppListView.swift
//  TrollReverseLab
//
//  Module 1: Main view showing list of installed applications.
//  Scans Bundle and Data container directories, identifies TrollStore apps,
//  and displays them for user selection with diagnostic info.
//

import SwiftUI

/// View model for the app scanner.
public final class AppScannerViewModel: ObservableObject {
    @Published public var apps: [TrollStoreApp] = []
    @Published public var isScanning = false
    @Published public var selectedApp: TrollStoreApp?
    @Published public var diagnostics: ScanDiagnostics?
    @Published public var showDiagnostics = false

    private let scanner = TrollStoreAppScanner()

    public func scan() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = self.scanner.scanTrollStoreApps()
            let diag = self.scanner.diagnostics
            DispatchQueue.main.async {
                self.apps = found
                self.diagnostics = diag
                self.isScanning = false
            }
        }
    }
}

/// List view showing all installed applications on the device.
struct AppListView: View {
    @EnvironmentObject var scanner: AppScannerViewModel
    @State private var showManualPath = false
    @State private var manualPath = ""

    var body: some View {
        NavigationView {
            Group {
                if scanner.isScanning {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("正在扫描设备应用...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if scanner.apps.isEmpty {
                    EmptyStateWithDiagnosticsView(
                        diagnostics: scanner.diagnostics,
                        onRescan: { scanner.scan() },
                        onManualPath: { showManualPath = true }
                    )
                } else {
                    appListView
                }
            }
            .navigationTitle("TrollStore 应用")
            .navigationBarItems(
                trailing: HStack {
                    if !scanner.apps.isEmpty {
                        Button {
                            scanner.showDiagnostics = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                    }
                    Button {
                        scanner.scan()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            )
            .onAppear {
                if scanner.apps.isEmpty && !scanner.isScanning {
                    scanner.scan()
                }
            }
            .sheet(isPresented: $scanner.showDiagnostics) {
                DiagnosticsView(diagnostics: scanner.diagnostics)
            }
            .sheet(isPresented: $showManualPath) {
                ManualPathView(path: $manualPath) { path in
                    // Create a manual app entry for browsing
                    let manualApp = TrollStoreApp(
                        id: "manual",
                        bundleIdentifier: "manual",
                        displayName: (path as NSString).lastPathComponent,
                        version: "—",
                        bundlePath: path,
                        dataContainerPath: path,
                        installDate: nil,
                        appSize: 0,
                        isTrollStore: true
                    )
                    scanner.selectedApp = manualApp
                }
            }
        }
    }

    private var appListView: some View {
        List {
            // TrollStore apps section
            if scanner.apps.contains(where: { $0.isTrollStore }) {
                Section(header: Text("TrollStore 应用 (\(scanner.apps.filter { $0.isTrollStore }.count))")) {
                    ForEach(scanner.apps.filter { $0.isTrollStore }) { app in
                        NavigationLink(destination: SandboxBrowserView(app: app)) {
                            AppRowView(app: app)
                        }
                    }
                }
            }

            // Other third-party apps section
            let otherApps = scanner.apps.filter { !$0.isTrollStore }
            if !otherApps.isEmpty {
                Section(header: Text("其他第三方应用 (\(otherApps.count))")) {
                    ForEach(otherApps) { app in
                        NavigationLink(destination: SandboxBrowserView(app: app)) {
                            AppRowView(app: app)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// Row displaying app icon, name, version, and container size.
struct AppRowView: View {
    let app: TrollStoreApp

    var body: some View {
        HStack(spacing: 12) {
            // App icon placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(app.isTrollStore ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.15))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: app.isTrollStore ? "app.badge.checkmark" : "app.fill")
                        .font(.title2)
                        .foregroundColor(app.isTrollStore ? .orange : .accentColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("v\(app.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if app.appSize > 0 {
                        Text(formatSize(app.appSize))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if app.isTrollStore {
                        Label("TrollStore", systemImage: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                Text(app.bundleIdentifier)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Empty state with diagnostic info and manual path option.
struct EmptyStateWithDiagnosticsView: View {
    let diagnostics: ScanDiagnostics?
    let onRescan: () -> Void
    let onManualPath: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("未找到应用")
                    .font(.headline)

                Text("扫描完成但未发现可浏览的应用")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // Diagnostic info
                if let diag = diagnostics {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("诊断信息")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        DiagnosticRow(label: "扫描路径", value: "\(diag.pathsScanned.count) 个")
                        DiagnosticRow(label: "Bundle 目录数", value: "\(diag.totalBundleDirs)")
                        DiagnosticRow(label: "数据容器数", value: "\(diag.dataContainersFound)")
                        DiagnosticRow(label: "发现应用总数", value: "\(diag.totalAppsFound)")
                        DiagnosticRow(label: "系统应用过滤", value: "\(diag.systemAppsFiltered)")

                        if !diag.errors.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("错误信息:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                                ForEach(diag.errors, id: \.self) { error in
                                    Text("• \(error)")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.top, 4)
                        }

                        Text("扫描的路径:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        ForEach(diag.pathsScanned, id: \.self) { path in
                            Text("• \(path)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onRescan) {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: onManualPath) {
                        Label("手动输入路径", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 32)

                Text("提示: 如果诊断信息显示所有路径都无法访问，请确认应用已通过 TrollStore 正确安装，且设备已越狱或使用 TrollStore 环境。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

/// Diagnostics detail view (shown via info button).
struct DiagnosticsView: View {
    let diagnostics: ScanDiagnostics?
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                if let diag = diagnostics {
                    Section(header: Text("统计")) {
                        DiagnosticRow(label: "扫描路径数", value: "\(diag.pathsScanned.count)")
                        DiagnosticRow(label: "Bundle 目录数", value: "\(diag.totalBundleDirs)")
                        DiagnosticRow(label: "数据容器数", value: "\(diag.dataContainersFound)")
                        DiagnosticRow(label: "发现应用总数", value: "\(diag.totalAppsFound)")
                        DiagnosticRow(label: "TrollStore 应用", value: "\(diag.trollStoreApps)")
                        DiagnosticRow(label: "其他第三方应用", value: "\(diag.thirdPartyApps - diag.trollStoreApps)")
                        DiagnosticRow(label: "系统应用(已过滤)", value: "\(diag.systemAppsFiltered)")
                    }

                    Section(header: Text("扫描路径")) {
                        ForEach(diag.pathsScanned, id: \.self) { path in
                            Text(path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !diag.errors.isEmpty {
                        Section(header: Text("错误")) {
                            ForEach(diag.errors, id: \.self) { error in
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                } else {
                    Text("暂无诊断信息")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("扫描诊断")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

/// Manual path entry view.
struct ManualPathView: View {
    @Binding var path: String
    let onConfirm: (String) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("手动输入路径"), footer: Text("输入应用 Bundle 或数据容器的完整路径进行浏览")) {
                    TextField("/var/containers/Bundle/Application/...", text: $path)
                        .keyboardType(.default)
                        .autocapitalization(.none)
                }

                Section(header: Text("常用路径")) {
                    Button("/var/containers/Bundle/Application") {
                        path = "/var/containers/Bundle/Application"
                    }
                    Button("/var/mobile/Containers/Data/Application") {
                        path = "/var/mobile/Containers/Data/Application"
                    }
                    Button("/var/jb/var/containers/Bundle/Application") {
                        path = "/var/jb/var/containers/Bundle/Application"
                    }
                }
            }
            .navigationTitle("手动路径")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("浏览") {
                    if !path.isEmpty {
                        onConfirm(path)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .disabled(path.isEmpty)
            )
        }
    }
}

/// Empty state placeholder (legacy, kept for compatibility).
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
