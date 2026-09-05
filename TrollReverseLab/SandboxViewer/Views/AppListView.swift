//
//  AppListView.swift
//  TrollReverseLab
//
//  Module 1: Main view showing list of TrollStore-installed applications.
//  Scans Data container directory, identifies TrollStore apps via .appInfo.plist,
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
    @Published public var permissionError: String?

    private let scanner = TrollStoreAppScanner()
    private var hasLoadedCache = false
    /// false = 仅巨魔应用（旧行为）；true = 全部已安装应用（App Store/侧载一律列出）
    @Published public var showAllApps: Bool = UserDefaults.standard.object(forKey: "sandboxShowAllApps") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showAllApps, forKey: "sandboxShowAllApps") }
    }

    /// Loads cached apps immediately (called on first appear).
    public func loadCache() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        let cachedApps = TrollStoreAppCache.shared.loadCachedApps().filter { showAllApps || $0.isTrollStore }
        self.apps = cachedApps
        self.diagnostics = TrollStoreAppCache.shared.loadCachedDiagnostics()
    }

    /// Starts an async scan without blocking the UI.
    public func scan() {
        guard !isScanning else { return }
        isScanning = true
        permissionError = nil

        scanner.includeAllApps = showAllApps
        scanner.scanTrollStoreAppsAsync { [weak self] found, diag in
            guard let self = self else { return }
            self.apps = found
            self.diagnostics = diag
            self.permissionError = diag.permissionError
            self.isScanning = false
        }
    }

    /// Toggle 切换后重扫。
    public func rescanForModeChange() {
        TrollStoreAppCache.shared.saveCachedApps([])  // 清缓存防止旧模式结果残留
        scan()
    }
}

/// List view showing all TrollStore applications on the device.
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
                        Text("正在扫描 TrollStore 应用...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if let permError = scanner.permissionError {
                    // Permission error — IPA missing no-sandbox entitlement
                    PermissionErrorView(
                        error: permError,
                        diagnostics: scanner.diagnostics,
                        onRescan: { scanner.scan() },
                        onManualPath: { showManualPath = true }
                    )
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
            .navigationTitle("应用沙盒")
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
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Picker("范围", selection: Binding(
                        get: { scanner.showAllApps },
                        set: { newValue in
                            scanner.showAllApps = newValue
                            scanner.rescanForModeChange()
                        }
                    )) {
                        Text("全部应用").tag(true)
                        Text("仅巨魔").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(UIColor.systemBackground))
            }
            .onAppear {
                scanner.loadCache()
                if !scanner.isScanning {
                    scanner.scan()
                }
            }
            .sheet(isPresented: $scanner.showDiagnostics) {
                DiagnosticsView(diagnostics: scanner.diagnostics)
            }
            .sheet(isPresented: $showManualPath) {
                ManualPathView(path: $manualPath) { path in
                    let manualApp = TrollStoreApp(
                        id: "manual",
                        bundleIdentifier: "manual",
                        displayName: (path as NSString).lastPathComponent,
                        version: "—",
                        bundlePath: path,
                        dataContainerPath: path,
                        installDate: nil,
                        appSize: 0,
                        isTrollStore: true,
                        markerType: "manual"
                    )
                    scanner.selectedApp = manualApp
                }
            }
        }
    }

    private var appListView: some View {
        List {
            Section(header: Text(scanner.showAllApps ? "全部应用 (\(scanner.apps.count))" : "TrollStore 应用 (\(scanner.apps.count))")) {
                ForEach(scanner.apps) { app in
                    NavigationLink(destination: SandboxBrowserView(app: app)) {
                        AppRowView(app: app)
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
    @State private var rowImage: UIImage?
    @State private var displayedSize: Int64 = 0

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundlePath: app.bundlePath)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    if app.isTrollStore {
                        Text("TS")
                            .font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(4)
                    }
                    Text("v\(app.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if displayedSize > 0 {
                        Text(formatSize(displayedSize))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Label("TrollStore", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                Text(app.bundleIdentifier)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear {
            displayedSize = app.appSize
            if displayedSize == 0 {
                TrollStoreAppScanner.calculateAppSizeAsync(for: app) { size in
                    displayedSize = size
                }
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Loads and displays the actual app icon from a .app bundle.
struct AppIconView: View {
    let bundlePath: String
    @State private var iconImage: UIImage?

    var body: some View {
        Group {
            if let iconImage = iconImage {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.15))
                    .overlay(
                        Image(systemName: "app.badge.checkmark")
                            .font(.title2)
                            .foregroundColor(.orange)
                    )
            }
        }
        .onAppear {
            loadIcon()
        }
        .onChange(of: bundlePath) { _ in
            loadIcon()
        }
    }

    private func loadIcon() {
        DispatchQueue.global(qos: .userInitiated).async {
            let paths = AppIconLoader.iconPaths(forBundle: bundlePath)
            var image: UIImage?
            for path in paths {
                if let loaded = AppIconLoader.loadUIImage(fromPath: path) {
                    image = loaded
                    break
                }
            }
            DispatchQueue.main.async {
                self.iconImage = image
            }
        }
    }
}

/// Permission error view — shown when sandbox escape entitlement is missing.
struct PermissionErrorView: View {
    let error: String
    let diagnostics: ScanDiagnostics?
    let onRescan: () -> Void
    let onManualPath: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)

                Text("沙盒权限缺失")
                    .font(.headline)
                    .foregroundColor(.red)

                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Diagnostic info
                if let diag = diagnostics {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("诊断信息")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        DiagnosticRow(label: "扫描目录数", value: "\(diag.totalDirsScanned)")
                        DiagnosticRow(label: "Marker 文件数", value: "\(diag.markerFilesFound)")
                        DiagnosticRow(label: "TrollStore 应用", value: "\(diag.trollStoreApps)")
                        DiagnosticRow(label: "沙盒可访问", value: diag.canAccessSandbox ? "是" : "否")
                        DiagnosticRow(label: "扫描路径数", value: "\(diag.pathsScanned.count)")
                        DiagnosticRow(label: "跳过容器", value: "\(diag.skippedContainers)")

                        if !diag.markersChecked.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("检测标记:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                Text(diag.markersChecked.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }

                        if !diag.errors.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("错误信息:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                                ForEach(diag.errors, id: \.self) { err in
                                    Text("• \(err)")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

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

                Text("提示: 请确认 IPA 已通过 TrollStore 安装，且 entitlements 包含 com.apple.private.security.no-sandbox 权限。可在「权限自检」标签页检查当前权限状态。")
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

                Text("未找到 TrollStore 应用")
                    .font(.headline)

                Text("扫描完成但未发现 TrollStore 标记\n标准 TrollStore 2.1.1 使用 _TrollStore / _TrollStoreLite（位于 /var/containers/Bundle/Application/），部分 ReMod 使用 .appInfo.plist（位于数据容器）。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                if let diag = diagnostics {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("诊断信息")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        DiagnosticRow(label: "扫描目录数", value: "\(diag.totalDirsScanned)")
                        DiagnosticRow(label: "Marker 文件数", value: "\(diag.markerFilesFound)")
                        DiagnosticRow(label: "TrollStore 应用", value: "\(diag.trollStoreApps)")
                        DiagnosticRow(label: "沙盒可访问", value: diag.canAccessSandbox ? "是" : "否")
                        DiagnosticRow(label: "扫描路径数", value: "\(diag.pathsScanned.count)")
                        DiagnosticRow(label: "跳过容器", value: "\(diag.skippedContainers)")

                        if !diag.markersChecked.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("检测标记:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                Text(diag.markersChecked.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

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

                Text("提示: 标准 TrollStore 2.1.1 在 /var/containers/Bundle/Application/ 下放置 _TrollStore 标记文件。如果 Marker 文件数为 0，请确认你安装的应用确实来自 TrollStore；如果沙盒可访问为「否」，请在「权限自检」标签页检查并重新打包。")
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
                        DiagnosticRow(label: "扫描目录数", value: "\(diag.totalDirsScanned)")
                        DiagnosticRow(label: "Marker 文件数", value: "\(diag.markerFilesFound)")
                        DiagnosticRow(label: "TrollStore 应用", value: "\(diag.trollStoreApps)")
                        DiagnosticRow(label: "沙盒可访问", value: diag.canAccessSandbox ? "是" : "否")
                        DiagnosticRow(label: "跳过容器", value: "\(diag.skippedContainers)")
                        DiagnosticRow(label: "扫描耗时", value: String(format: "%.2fs", diag.scanDuration))
                    }

                    Section(header: Text("检测标记")) {
                        ForEach(diag.markersChecked, id: \.self) { marker in
                            Text(marker)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
                Section(header: Text("手动输入路径"), footer: Text("输入应用数据容器的完整路径进行浏览")) {
                    TextField("/private/var/mobile/Containers/Data/Application/...", text: $path)
                        .keyboardType(.default)
                        .autocapitalization(.none)
                }

                Section(header: Text("常用路径")) {
                    Button("/private/var/mobile/Containers/Data/Application") {
                        path = "/private/var/mobile/Containers/Data/Application"
                    }
                    Button("/var/mobile/Containers/Data/Application") {
                        path = "/var/mobile/Containers/Data/Application"
                    }
                    Button("/var/containers/Bundle/Application") {
                        path = "/var/containers/Bundle/Application"
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

/// Empty state placeholder.
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
