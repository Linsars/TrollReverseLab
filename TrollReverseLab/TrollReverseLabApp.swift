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
                .onAppear {
                    checkFirstLaunchAgreement()
                }
        }
    }

    private func checkFirstLaunchAgreement() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasAcceptedUsageAgreement") {
            defaults.set(false, forKey: "hasAcceptedUsageAgreement")
        }
    }
}

/// Main tab navigation for the core modules.
struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showAgreement = false

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
        .sheet(isPresented: $showAgreement) {
            UsageAgreementView(isPresented: $showAgreement)
        }
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "hasAcceptedUsageAgreement") {
                showAgreement = true
            }
        }
    }
}

/// First-launch usage agreement that enforces ethical use constraints.
struct UsageAgreementView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("使用协议")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("TrollReverseLab 仅用于以下合法用途：")
                        .font(.body)

                    VStack(alignment: .leading, spacing: 8) {
                        AgreementItem(text: "个人本地 iOS 逆向学习与教学")
                        AgreementItem(text: "单机本地存档数据格式研究")
                        AgreementItem(text: "客户端数据结构调试与分析")
                        AgreementItem(text: "Frida 逆向技术教学与学习")
                        AgreementItem(text: "iOS 沙盒机制与存储原理研究")
                        AgreementItem(text: "个人原创内容素材编辑与排版")
                        AgreementItem(text: "iOS 交互流程录制与学习")
                    }

                    Text("严禁用于以下用途：")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.red)

                    VStack(alignment: .leading, spacing: 8) {
                        AgreementItem(text: "内购绕过、支付欺诈", isProhibited: true)
                        AgreementItem(text: "联机游戏篡改、批量破解", isProhibited: true)
                        AgreementItem(text: "侵犯软件版权、盗取隐私数据", isProhibited: true)
                        AgreementItem(text: "对外分发破解脚本、商业化破解", isProhibited: true)
                        AgreementItem(text: "批量矩阵营销、虚假互动刷量", isProhibited: true)
                        AgreementItem(text: "规避平台风控、批量养号运营", isProhibited: true)
                    }

                    Text("本工具仅针对用户自选的 TrollStore 安装应用做本地研究，不用于访问系统核心进程、App Store 应用或第三方隐私数据。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("使用协议")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("拒绝") { }
                    .disabled(true),
                trailing: Button("同意并继续") {
                    UserDefaults.standard.set(true, forKey: "hasAcceptedUsageAgreement")
                    isPresented = false
                }
            )
        }
    }
}

struct AgreementItem: View {
    let text: String
    var isProhibited: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isProhibited ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isProhibited ? .red : .green)
                .font(.caption)
            Text(text)
                .font(.subheadline)
        }
    }
}
