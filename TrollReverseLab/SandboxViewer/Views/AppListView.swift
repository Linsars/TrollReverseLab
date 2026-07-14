//
//  AppListView.swift
//  TrollReverseLab
//
//  Module 1: Main view showing list of TrollStore applications.
//  Scans for apps with .appInfo.plist markers and displays them
//  for user selection.
//

import SwiftUI

/// View model for the app scanner.
public final class AppScannerViewModel: ObservableObject {
    @Published public var apps: [TrollStoreApp] = []
    @Published public var isScanning = false
    @Published public var selectedApp: TrollStoreApp?

    private let scanner = TrollStoreAppScanner()

    public func scan() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = self.scanner.scanTrollStoreApps()
            DispatchQueue.main.async {
                self.apps = found
                self.isScanning = false
            }
        }
    }
}

/// List view showing all TrollStore applications on the device.
struct AppListView: View {
    @EnvironmentObject var scanner: AppScannerViewModel

    var body: some View {
        NavigationView {
            Group {
                if scanner.isScanning {
                    ProgressView("扫描 TrollStore 应用...")
                } else if scanner.apps.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "未找到 TrollStore 应用",
                        message: "请确认设备已通过 TrollStore 安装应用，然后点击右上角刷新"
                    )
                } else {
                    List(scanner.apps) { app in
                        NavigationLink(destination: SandboxBrowserView(app: app)) {
                            AppRowView(app: app)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("TrollStore 应用")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        scanner.scan()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                if scanner.apps.isEmpty {
                    scanner.scan()
                }
            }
        }
    }
}

/// Row displaying app icon, name, version, and container size.
struct AppRowView: View {
    let app: TrollStoreApp

    var body: some View {
        HStack(spacing: 12) {
            // App icon placeholder (TrollStore apps may not expose icon easily)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("v\(app.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatSize(app.appSize))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
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
