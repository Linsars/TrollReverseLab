//
//  AIScriptView.swift
//  TrollReverseLab
//
//  Module 3: AI-assisted script generation UI.
//  Natural language input generates Frida/Lua scripts for local
//  reverse engineering research.
//

import SwiftUI
import UIKit

struct AIScriptView: View {
    @EnvironmentObject var aiClient: AIScriptClient
    @EnvironmentObject var appScanner: AppScannerViewModel
    @EnvironmentObject var captureEngine: PacketCaptureEngine
    @EnvironmentObject var backupManager: AppBackupManager
    @EnvironmentObject var conversationManager: AIConversationManager
    @EnvironmentObject var fridaEngine: FridaEngine
    @State private var description = ""
    @State private var scriptType: ScriptType = .fridaJS
    @State private var appContext = ""
    @State private var selectedApp: TrollStoreApp?
    @State private var showAppPicker = false
    @State private var errorMessage: String?
    @State private var attachTraffic = false
    @State private var trafficHostFilter = ""
    @State private var showConversationHistory = false
    @State private var showFridaInjectAlert = false
    @State private var fridaInjectResult = ""

    // Custom colors (avoid iOS 15+ system colors)
    private let accentBlue = Color(red: 0.25, green: 0.47, blue: 0.90)
    private let cardBg = Color(.secondarySystemBackground)

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Input area
                VStack(spacing: 14) {
                    // Script type selector with label
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.below.ecg")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text("脚本类型")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Picker("脚本类型", selection: $scriptType) {
                            ForEach(ScriptType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Target app selector
                    Button {
                        showAppPicker = true
                    } label: {
                        HStack(spacing: 10) {
                            if let app = selectedApp {
                                AppIconView(bundlePath: app.bundlePath)
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Text(app.bundleIdentifier)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.accentColor.opacity(0.12))
                                    Image(systemName: "app.badge")
                                        .font(.title3)
                                        .foregroundColor(.accentColor)
                                }
                                .frame(width: 32, height: 32)
                                Text("选择目标应用（可选）")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(cardBg)
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Traffic context
                    if captureEngine.hasCapturedData {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $attachTraffic) {
                                HStack(spacing: 4) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.caption)
                                    Text("附加抓包数据")
                                        .font(.caption)
                                    Text("(\(captureEngine.captureCount) 条)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if attachTraffic {
                                TextField("按主机过滤（如 api.example.com）", text: $trafficHostFilter)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .autocapitalization(.none)
                            }
                        }
                        Divider()
                    }

                    // Auto-backup
                    if selectedApp != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                Toggle(isOn: Binding(
                                    get: { backupManager.autoBackupEnabled },
                                    set: { backupManager.setAutoBackup($0) }
                                )) {
                                    Text("AI 操作前自动备份")
                                        .font(.caption)
                                }
                            }
                            NavigationLink(destination: AppBackupView()) {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("管理备份 (\(backupManager.backups.count))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        Divider()
                    }

                    // Description input
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text("分析需求描述")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(description.count) 字")
                                .font(.caption2)
                                .foregroundColor(description.count > 500 ? .red : .secondary)
                        }
                        ZStack(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("例如: 读取本地存档文件并解析其数据结构...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $description)
                                .frame(height: 90)
                                .font(.body)
                                .padding(4)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.separator), lineWidth: 0.5)
                                )
                        }
                    }

                    // App context
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text("应用上下文（可选）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        TextField("例如: 某单机游戏的本地存档格式", text: $appContext)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .autocapitalization(.none)
                    }

                    // Generate button
                    Button {
                        Task { await generateScript() }
                    } label: {
                        HStack(spacing: 6) {
                            if aiClient.isGenerating {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(aiClient.isGenerating ? "生成中..." : "生成脚本")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)
                        .background(
                            description.isEmpty || aiClient.isGenerating
                                ? Color.gray.opacity(0.4)
                                : accentBlue
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(description.isEmpty || aiClient.isGenerating)

                    if let error = errorMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                        }
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding(16)

                Divider()

                // Generated scripts list
                if aiClient.generatedScripts.isEmpty {
                    emptyState
                } else {
                    List(aiClient.generatedScripts.reversed()) { script in
                        NavigationLink(destination: ScriptDetailView(script: script)) {
                            ScriptRow(script: script)
                        }
                        .listRowBackground(Color(.systemBackground))
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("AI 脚本生成")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button {
                    showConversationHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                },
                trailing: Button {
                    aiClient.resetConversation()
                    OperationLogger.shared.logInfo(module: "AI脚本", action: "重置对话")
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
            )
            .sheet(isPresented: $showAppPicker) {
                AppPickerView(
                    apps: appScanner.apps,
                    selectedApp: $selectedApp,
                    isPresented: $showAppPicker
                )
            }
            .sheet(isPresented: $showConversationHistory) {
                ConversationHistoryView(conversationManager: conversationManager)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 30))
                    .foregroundColor(.accentColor)
            }
            VStack(spacing: 6) {
                Text("尚未生成脚本")
                    .font(.headline)
                Text("描述你的本地逆向分析需求\nAI 将生成对应的调试脚本")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func generateScript() async {
        errorMessage = nil

        if let app = selectedApp {
            backupManager.autoBackupIfNeeded(for: app)
        }

        // Auto-attach traffic if available and not explicitly toggled
        let actualAttachTraffic = attachTraffic || (captureEngine.hasCapturedData && !attachTraffic && selectedApp != nil)
        let trafficContext: String? = actualAttachTraffic
            ? captureEngine.exportForAI(
                hostFilter: trafficHostFilter.isEmpty ? nil : trafficHostFilter
              )
            : nil

        // Get or create conversation session
        let session = conversationManager.getOrCreateSession(
            forAppBundleId: selectedApp?.bundleIdentifier,
            appName: selectedApp?.displayName ?? "通用",
            scriptType: scriptType
        )

        do {
            _ = try await aiClient.generateScriptWithSession(
                description: description,
                scriptType: scriptType,
                appContext: appContext.isEmpty ? nil : appContext,
                targetApp: selectedApp,
                trafficContext: trafficContext,
                sessionMessages: session.messages
            )

            // Save messages to session
            let userMessage = ChatMessage(role: "user", content: description)
            let assistantMessage = ChatMessage(role: "assistant", content: aiClient.generatedScripts.last?.fullResponse ?? "")
            conversationManager.appendMessages(toSession: session.id, messages: [userMessage, assistantMessage])

            OperationLogger.shared.logSuccess(
                module: "AI脚本",
                action: "生成\(scriptType.displayName)脚本",
                detail: selectedApp?.displayName ?? "通用"
            )

            description = ""
            appContext = ""
        } catch {
            errorMessage = error.localizedDescription
            OperationLogger.shared.logFailure(
                module: "AI脚本",
                action: "生成脚本",
                detail: error.localizedDescription
            )
        }
    }
}

// MARK: - Script Row

private struct ScriptRow: View {
    let script: GeneratedScript

    private var typeColor: Color {
        switch script.scriptType {
        case .fridaJS:
            return Color(red: 0.25, green: 0.47, blue: 0.90)
        case .lua:
            return Color(red: 0.20, green: 0.60, blue: 0.40)
        }
    }

    private var typeIcon: String {
        switch script.scriptType {
        case .fridaJS:
            return "ladybug"
        case .lua:
            return "moon"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(script.description)
                .font(.body)
                .lineLimit(2)
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: typeIcon)
                        .font(.caption2)
                    Text(script.scriptType.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(typeColor.opacity(0.15))
                .foregroundColor(typeColor)
                .cornerRadius(5)

                Spacer()

                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(formatDate(script.timestamp))
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Script Detail View

struct ScriptDetailView: View {
    let script: GeneratedScript
    @EnvironmentObject var aiClient: AIScriptClient
    @EnvironmentObject var fridaEngine: FridaEngine
    @State private var showSavedAlert = false
    @State private var saveResult = false
    @State private var copied = false
    @State private var showInjectAlert = false
    @State private var injectResult = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Script info card
                VStack(alignment: .leading, spacing: 10) {
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
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // Code block
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("脚本代码")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = script.code
                            withAnimation { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { copied = false }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.caption2)
                                Text(copied ? "已复制" : "复制")
                                    .font(.caption2)
                            }
                            .foregroundColor(copied ? .green : .accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Text(script.code)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .modifier(SelectableTextModifier())
                }

                // Inject to Frida button
                Button {
                    injectToFreeze()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ladybug.fill")
                        Text("注入到 Frida 执行")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(Color(red: 0.85, green: 0.45, blue: 0.20))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())

                // Save button
                Button {
                    saveResult = aiClient.saveScript(script)
                    showSavedAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("保存到本地")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(Color.accentColor)
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
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
        .alert(isPresented: $showInjectAlert) {
            Alert(
                title: Text("Frida 注入"),
                message: Text(injectResult),
                dismissButton: .default(Text("确定"))
            )
        }
    }

    private func injectToFreeze() {
        if fridaEngine.state == .disconnected {
            injectResult = "Frida 未连接，请先在 Frida 调试页面选择目标应用并连接。"
            showInjectAlert = true
            OperationLogger.shared.logFailure(module: "AI脚本", action: "注入Frida", detail: "Frida未连接")
            return
        }

        let scriptName = script.description.prefix(20)
        fridaEngine.executeScript(script.code, name: String(scriptName))
        injectResult = "脚本已发送到 Frida 引擎，请查看 Frida 调试页面的控制台输出。"
        showInjectAlert = true
        OperationLogger.shared.logSuccess(module: "AI脚本", action: "注入Frida执行", detail: String(scriptName))
    }
}

// MARK: - Helpers

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yy/MM/dd HH:mm"
    return formatter.string(from: date)
}

struct SelectableTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}

// MARK: - Conversation History View

struct ConversationHistoryView: View {
    @ObservedObject var conversationManager: AIConversationManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if conversationManager.sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("暂无对话记录")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("生成脚本时会自动保存对话历史\n按应用分组，方便回溯")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(conversationManager.sessionsByApp, id: \.0) { appName, sessions in
                            Section(header: Text(appName)) {
                                ForEach(sessions) { session in
                                    NavigationLink(destination: ConversationDetailView(session: session)) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(session.displayTitle)
                                                .font(.subheadline)
                                                .lineLimit(1)
                                            HStack(spacing: 8) {
                                                Text("\(session.messageCount) 条消息")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text(session.scriptType == "frida-js" ? "Frida JS" : "Lua")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 1)
                                                    .background(Color.accentColor.opacity(0.12))
                                                    .foregroundColor(.accentColor)
                                                    .cornerRadius(4)
                                                Spacer()
                                                Text(session.lastActivity)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                                .onDelete { offsets in
                                    for offset in offsets {
                                        let session = sessions[offset]
                                        conversationManager.deleteSession(session.id)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("对话历史")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("完成")
                }
            )
        }
    }
}

// MARK: - Conversation Detail View

struct ConversationDetailView: View {
    let session: AIConversationSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(session.messages.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: message.role == "user" ? "person.fill" : "sparkles")
                                .font(.caption2)
                                .foregroundColor(message.role == "user" ? .accentColor : .purple)
                            Text(message.role == "user" ? "用户" : "AI")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(message.role == "user" ? .accentColor : .purple)
                        }
                        Text(message.content)
                            .font(.system(.caption))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .modifier(SelectableTextModifier())
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
