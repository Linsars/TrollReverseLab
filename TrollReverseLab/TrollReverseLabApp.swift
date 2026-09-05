//
//  TrollReverseLabApp.swift
//  TrollReverseLab
//
//  Main application entry point.
//  iOS local reverse engineering learning tool for TrollStore environment.
//
//  Six modules:
//  1. 沙盒文件浏览器 (Sandbox File Browser)
//  2. 网络抓包 (Packet Capture — HTTP/HTTPS proxy for AI analysis)
//  3. 内置Frida本地调试 (Frida Local Debug)
//  4. LLM逆向脚本生成 (AI Script Generation)
//  5. 设置与权限自检 (Settings & Permission Self-Check)
//  6. 应用数据备份/还原 (App Data Backup/Restore — integrated)
//

import SwiftUI

@main
struct TrollReverseLabApp: App {
    @StateObject private var appScanner = AppScannerViewModel()
    @StateObject private var fridaEngine = FridaEngine()
    @StateObject private var aiClient = AIScriptClient()
    @StateObject private var captureEngine = PacketCaptureEngine()
    @StateObject private var backupManager = AppBackupManager()
    @StateObject private var coordinateManager = CoordinatePickerManager()
    @StateObject private var statusManager = DeviceStatusManager()
    @StateObject private var ipaBuilder = IPABuilderManager()
    @StateObject private var materialEditor = MaterialEditorManager()
    @StateObject private var contentScheduler = ContentSchedulerManager()
    @StateObject private var scriptRecorder = ScriptRecorderManager()
    @StateObject private var sandboxLab = SandboxLabManager()
    @StateObject private var conversationManager = AIConversationManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appScanner)
                .environmentObject(fridaEngine)
                .environmentObject(aiClient)
                .environmentObject(captureEngine)
                .environmentObject(backupManager)
                .environmentObject(coordinateManager)
                .environmentObject(statusManager)
                .environmentObject(ipaBuilder)
                .environmentObject(materialEditor)
                .environmentObject(contentScheduler)
                .environmentObject(scriptRecorder)
                .environmentObject(sandboxLab)
                .environmentObject(conversationManager)
        }
    }
}

/// Main tab navigation for the core modules.
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Module 1: Sandbox File Browser
            AppListView()
                .tabItem {
                    Label("沙盒浏览", systemImage: "folder.badge.person.crop")
                }
                .tag(0)

            // Module 2: Packet Capture
            PacketCaptureView()
                .tabItem {
                    Label("抓包", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(1)

            // Module 3: Frida Debug Engine
            FridaDebugView()
                .tabItem {
                    Label("Frida调试", systemImage: "ladybug")
                }
                .tag(2)

            // Module 4: AI Script Generator
            AIScriptView()
                .tabItem {
                    Label("AI脚本", systemImage: "wand.and.stars")
                }
                .tag(3)

            // Module 5: More tools (workflow, settings, tools)
            MoreView()
                .tabItem {
                    Label("更多", systemImage: "ellipsis")
                }
                .tag(4)
        }
    }
}

