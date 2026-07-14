//
//  TrollReverseLabApp.swift
//  TrollReverseLab
//
//  Main application entry point.
//  iOS local reverse engineering learning tool for TrollStore environment.
//
//  Four modules:
//  1. 沙盒文件浏览器 (Sandbox File Browser)
//  2. 内置Frida本地调试 (Frida Local Debug)
//  3. LLM逆向脚本生成 (AI Script Generation)
//  4. 权限自检捕获 (Permission Self-Check)
//

import SwiftUI

@main
struct TrollReverseLabApp: App {
    @StateObject private var appScanner = AppScannerViewModel()
    @StateObject private var fridaEngine = FridaEngine()
    @StateObject private var aiClient = AIScriptClient()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appScanner)
                .environmentObject(fridaEngine)
                .environmentObject(aiClient)
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

/// Main tab navigation for the four core modules.
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

            // Module 2: Frida Debug Engine
            FridaDebugView()
                .tabItem {
                    Label("Frida调试", systemImage: "ladybug")
                }
                .tag(1)

            // Module 3: AI Script Generator
            AIScriptView()
                .tabItem {
                    Label("AI脚本", systemImage: "wand.and.stars")
                }
                .tag(2)

            // Module 4: Permission Self-Check
            PermissionCheckerView()
                .tabItem {
                    Label("权限自检", systemImage: "shield.checkered")
                }
                .tag(3)
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
