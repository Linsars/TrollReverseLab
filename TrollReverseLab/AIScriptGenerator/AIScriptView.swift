//
//  AIScriptView.swift
//  TrollReverseLab
//
//  Module 3: AI-assisted script generation UI.
//  Natural language input generates Frida/Lua scripts for local
//  reverse engineering research.
//

import SwiftUI

struct AIScriptView: View {
    @EnvironmentObject var aiClient: AIScriptClient
    @EnvironmentObject var appScanner: AppScannerViewModel
    @EnvironmentObject var captureEngine: PacketCaptureEngine
    @EnvironmentObject var backupManager: AppBackupManager
    @State private var description = ""
    @State private var scriptType: ScriptType = .fridaJS
    @State private var appContext = ""
    @State private var selectedApp: TrollStoreApp?
    @State private var showAppPicker = false
    @State private var showFullResponse = false
    @State private var errorMessage: String?
    @State private var attachTraffic = false
    @State private var trafficHostFilter = ""
    @State private var showBackupView = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Input area
                VStack(spacing: 12) {
                    // Script type selector
                    Picker("脚本类型", selection: $scriptType) {
                        ForEach(ScriptType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Target app selector
                    VStack(alignment: .leading, spacing: 4) {
                        Text("目标应用（可选）")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button {
                            showAppPicker = true
                        } label: {
                            HStack {
                                if let app = selectedApp {
                                    AppIconView(bundlePath: app.bundlePath)
                                        .frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(app.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(app.bundleIdentifier)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                } else {
                                    Image(systemName: "app.badge")
                                        .foregroundColor(.secondary)
                                    Text("选择要分析的应用")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Traffic context (if captures available)
                    if captureEngine.hasCapturedData {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(isOn: $attachTraffic) {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.caption)
                                    Text("附加抓包数据 (\(captureEngine.captureCount) 条)")
                                        .font(.caption)
                                }
                            }

                            if attachTraffic {
                                TextField("按主机过滤（可选，如 api.example.com）", text: $trafficHostFilter)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .autocapitalization(.none)
                            }
                        }

                        Divider()
                    }

                    // Auto-backup toggle (if app selected)
                    if selectedApp != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                Toggle(isOn: Binding(
                                    get: { backupManager.autoBackupEnabled },
                                    set: { backupManager.setAutoBackup($0) }
                                )) {
                                    Text("AI 操作前自动备份应用数据")
                                        .font(.caption)
                                }
                            }

                            NavigationLink(destination: AppBackupView()) {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                    Text("管理备份 (\(backupManager.backups.count))")
                                        .font(.caption)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Divider()
                    }

                    // Natural language input
                    VStack(alignment: .leading, spacing: 4) {
                        Text("描述你要分析的本地数据或函数")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $description)
                                .frame(height: 80)
                                .font(.body)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.separator), lineWidth: 0.5)
                                )
                            if description.isEmpty {
                                Text("例如: 读取本地存档文件并解析其数据结构...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    // App context (optional)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("应用上下文（可选）")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("例如: 某单机游戏的本地存档格式", text: $appContext)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }

                    // Generate button
                    Button {
                        Task { await generateScript() }
                    } label: {
                        HStack {
                            if aiClient.isGenerating {
                                ProgressView()
                            }
                            Text(aiClient.isGenerating ? "生成中..." : "生成脚本")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DefaultButtonStyle())
                    .disabled(description.isEmpty || aiClient.isGenerating)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(16)

                Divider()

                // Generated scripts list
                if aiClient.generatedScripts.isEmpty {
                    EmptyStateView(
                        icon: "wand.and.stars",
                        title: "尚未生成脚本",
                        message: "描述你的本地逆向分析需求，AI 将生成对应的调试脚本"
                    )
                } else {
                    List(aiClient.generatedScripts.reversed()) { script in
                        NavigationLink(destination: ScriptDetailView(script: script)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(script.description)
                                    .font(.body)
                                    .lineLimit(2)

                                HStack(spacing: 8) {
                                    Text(script.scriptType.displayName)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .cornerRadius(4)

                                    Text(formatDate(script.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("AI 脚本生成")
            .navigationBarItems(trailing: Button {
                aiClient.resetConversation()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            })
            .sheet(isPresented: $showAppPicker) {
                AppPickerView(
                    apps: appScanner.apps,
                    selectedApp: $selectedApp,
                    isPresented: $showAppPicker
                )
            }
        }
    }

    private func generateScript() async {
        errorMessage = nil

        // Auto-backup before AI operation
        if let app = selectedApp {
            backupManager.autoBackupIfNeeded(for: app)
        }

        // Build traffic context from captured data
        let trafficContext: String? = attachTraffic
            ? captureEngine.exportForAI(
                hostFilter: trafficHostFilter.isEmpty ? nil : trafficHostFilter
              )
            : nil

        do {
            _ = try await aiClient.generateScript(
                description: description,
                scriptType: scriptType,
                appContext: appContext.isEmpty ? nil : appContext,
                targetApp: selectedApp,
                trafficContext: trafficContext
            )
            description = ""
            appContext = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Detail view showing a generated script with syntax highlighting.
struct ScriptDetailView: View {
    let script: GeneratedScript
    @EnvironmentObject var aiClient: AIScriptClient
    @State private var showSavedAlert = false
    @State private var saveResult = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Script info
                VStack(alignment: .leading, spacing: 8) {
                    Text(script.description)
                        .font(.headline)

                    HStack(spacing: 12) {
                        Label(script.scriptType.displayName, systemImage: "doc.text")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label(formatDate(script.timestamp), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Code block
                Text(script.code)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .modifier(SelectableTextModifier())

                // Save button
                Button {
                    saveResult = aiClient.saveScript(script)
                    showSavedAlert = true
                } label: {
                    Label("保存到本地", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(16)
        }
        .navigationTitle("脚本详情")
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: $showSavedAlert) {
            Alert(
                title: Text("保存结果"),
                message: Text(saveResult ? "脚本已保存到 Documents/GeneratedScripts/" : "保存失败，请重试"),
                dismissButton: .default(Text("确定"))
            )
        }
    }
}

/// iOS 14-compatible date formatting helper.
private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yy/MM/dd HH:mm"
    return formatter.string(from: date)
}

/// iOS 14-compatible text selection modifier.
struct SelectableTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}
