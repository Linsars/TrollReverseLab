import SwiftUI
import UIKit
import Foundation
import Combine

// MARK: - Sandbox Lab Manager

class SandboxLabManager: ObservableObject {

    @Published var pathInfos: [SandboxPathInfo] = []
    @Published var containerInfos: [ContainerInfo] = []
    @Published var processInfos: [ProcessInfoItem] = []
    @Published var isScanning: Bool = false
    @Published var educationalSections: [EducationalSection] = []

    private let fileManager = FileManager.default

    init() {
        educationalSections = EducationalSection.allSections
    }

    // MARK: - Sandbox Path Scanning

    func scanSandboxPaths() {
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var results: [SandboxPathInfo] = []

            // System paths
            let systemPaths: [(String, SandboxPathCategory, String)] = [
                ("/", .system, "文件系统根目录 — 无沙盒权限时不可访问"),
                ("/var", .system, "系统数据目录 — 包含容器、日志等"),
                ("/var/mobile", .system, "移动用户主目录 — App 数据存储位置"),
                ("/var/root", .system, "Root 用户主目录 — 需提权访问"),
                ("/System", .system, "系统文件目录 — iOS 系统二进制和框架"),
                ("/private", .system, "私有目录 — 链接目标，实际数据存储位置"),
                ("/Applications", .system, "系统应用目录 — TrollStore 应用安装位置"),
                ("/var/containers/Bundle/Application", .bundle, "应用 Bundle 容器 — 存放 .app 安装包"),
                ("/var/containers/Data/Application", .data, "应用数据容器 — 存放用户数据"),
            ]

            for (path, category, note) in systemPaths {
                results.append(SandboxPathInfo(path: path, category: category, educationalNote: note))
            }

            // App-specific paths
            let appPaths: [(String, SandboxPathCategory, String)] = [
                (NSHomeDirectory(), .data, "当前 App 沙盒根目录 — 沙盒内可读写"),
                ((NSHomeDirectory() as NSString).appendingPathComponent("Documents"), .documents, "Documents 目录 — 用户数据，iTunes 备份"),
                ((NSHomeDirectory() as NSString).appendingPathComponent("Library"), .library, "Library 目录 — 配置文件、偏好设置"),
                ((NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches"), .caches, "Caches 目录 — 缓存数据，可被系统清理"),
                ((NSHomeDirectory() as NSString).appendingPathComponent("tmp"), .tmp, "tmp 目录 — 临时文件，随时可能被清除"),
                (NSTemporaryDirectory(), .tmp, "系统临时目录 — 全局临时文件区域"),
            ]

            for (path, category, note) in appPaths {
                results.append(SandboxPathInfo(path: path, category: category, educationalNote: note))
            }

            // Group container path
            if let groupDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                results.append(SandboxPathInfo(
                    path: groupDir.path,
                    category: .group,
                    educationalNote: "Application Support 目录 — App 级别支持文件"
                ))
            }

            DispatchQueue.main.async {
                self.pathInfos = results
                self.isScanning = false
            }
        }
    }

    // MARK: - Process Info

    func collectProcessInfo() {
        let processInfo = Foundation.ProcessInfo.processInfo
        let bundle = Bundle.main

        var infos: [ProcessInfoItem] = []

        infos.append(ProcessInfoItem(id: "bundleId", label: "Bundle ID", value: bundle.bundleIdentifier ?? "N/A", icon: "tag"))
        infos.append(ProcessInfoItem(id: "version", label: "App Version", value: "\(bundle.infoDictionary?["CFBundleShortVersionString"] ?? "1.0")", icon: "info.circle"))
        infos.append(ProcessInfoItem(id: "build", label: "Build Number", value: "\(bundle.infoDictionary?["CFBundleVersion"] ?? "1")", icon: "hammer"))
        infos.append(ProcessInfoItem(id: "pid", label: "Process ID", value: "\(processInfo.processIdentifier)", icon: "number"))
        infos.append(ProcessInfoItem(id: "hostname", label: "Hostname", value: processInfo.hostName, icon: "network"))
        infos.append(ProcessInfoItem(id: "osVersion", label: "OS Version", value: processInfo.operatingSystemVersionString, icon: "cpu"))
        infos.append(ProcessInfoItem(id: "processorCount", label: "CPU Cores", value: "\(processInfo.processorCount)", icon: "cpu"))
        infos.append(ProcessInfoItem(id: "physicalMemory", label: "Physical Memory", value: formatBytes(processInfo.physicalMemory), icon: "memorychip"))
        infos.append(ProcessInfoItem(id: "homeDir", label: "Home Directory", value: NSHomeDirectory(), icon: "house.fill"))
        infos.append(ProcessInfoItem(id: "tmpDir", label: "Temp Directory", value: NSTemporaryDirectory(), icon: "clock.arrow.circlepath"))

        // System uptime
        let uptime = processInfo.systemUptime
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        infos.append(ProcessInfoItem(id: "uptime", label: "System Uptime", value: "\(hours)h \(minutes)m", icon: "timer"))

        // Active processors
        infos.append(ProcessInfoItem(id: "activeCPUs", label: "Active CPUs", value: "\(processInfo.activeProcessorCount)", icon: "cpu"))

        processInfos = infos
    }

    // MARK: - Container Scanning

    func scanContainers() {
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var containers: [ContainerInfo] = []

            // Scan Bundle Application directory
            let bundleAppPath = "/var/containers/Bundle/Application"
            if self.fileManager.fileExists(atPath: bundleAppPath) {
                if let appDirs = try? self.fileManager.contentsOfDirectory(atPath: bundleAppPath) {
                    for dir in appDirs {
                        let appDirPath = (bundleAppPath as NSString).appendingPathComponent(dir)
                        if let contents = try? self.fileManager.contentsOfDirectory(atPath: appDirPath) {
                            for content in contents where content.hasSuffix(".app") {
                                let appPath = (appDirPath as NSString).appendingPathComponent(content)
                                let infoPlistPath = (appPath as NSString).appendingPathComponent("Info.plist")
                                if let plist = NSDictionary(contentsOfFile: infoPlistPath) {
                                    let bundleId = plist["CFBundleIdentifier"] as? String ?? "unknown"
                                    let displayName = plist["CFBundleDisplayName"] as? String
                                        ?? plist["CFBundleName"] as? String ?? content

                                    // Try to find data container
                                    let dataPath = "/var/containers/Data/Application/\(dir)"
                                    containers.append(ContainerInfo(
                                        bundleId: bundleId,
                                        displayName: displayName,
                                        bundlePath: appPath,
                                        dataContainerPath: dataPath,
                                        containerType: "TrollStore"
                                    ))
                                }
                            }
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                self.containerInfos = containers
                self.isScanning = false
            }
        }
    }

    // MARK: - Environment Variables (Educational)

    func environmentVariables() -> [ProcessInfoItem] {
        let env = Foundation.ProcessInfo.processInfo.environment
        return env.sorted { $0.key < $1.key }.map { (key, value) in
            ProcessInfoItem(id: key, label: key, value: value, icon: "terminal")
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Summary

    var accessiblePathCount: Int {
        pathInfos.filter { $0.isAccessible }.count
    }

    var totalPathCount: Int {
        pathInfos.count
    }

    var hasSandboxEscape: Bool {
        pathInfos.contains { $0.path == "/" && $0.isAccessible }
    }
}
