//
//  FridaDebugView.swift
//  TrollReverseLab
//
//  Module 2: Frida debug engine UI.
//  Shows process attachment, script execution, console output,
//  and function tracing for local reverse engineering research.
//
//  INTEGRATED FROM: Material 3 — H5GG process enumeration & script management
//  - Process list UI with TrollStore app filtering
//  - Local script library management (Lua/Frida JS)
//  - iOS 14 compatibility fixes (.navigationBarItems instead of .toolbar)
//

import SwiftUI

struct FridaDebugView: View {
    @EnvironmentObject var fridaEngine: FridaEngine
    @EnvironmentObject var appScanner: AppScannerViewModel
    @State private var scriptInput = ""
    @State private var scriptName = ""
    @State private var showProcessPicker = false
    @State private var selectedProcess: LocalProcess?
    @State private var showScriptLibrary = false
    @State private var showAppPicker = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Target app status bar
                TargetAppBar(targetApp: fridaEngine.selectedTargetApp)

                Divider()

                // Connection status bar
                ConnectionStatusBar(state: fridaEngine.state)

                Divider()

                // SSH 管理面板
                SSHPanelView(sshManager: fridaEngine.sshManager)

                Divider()

                // Console output
                ConsoleOutputView(messages: fridaEngine.consoleOutput)
                    .frame(maxHeight: .infinity)

                Divider()

                // Script input area
                ScriptInputArea(
                    scriptInput: $scriptInput,
                    scriptName: $scriptName,
                    onExecute: {
                        fridaEngine.executeScript(scriptInput, name: scriptName.isEmpty ? "untitled" : scriptName)
                    },
                    onSave: {
                        fridaEngine.saveScriptToLocal(
                            name: scriptName.isEmpty ? "untitled" : scriptName,
                            content: scriptInput,
                            type: "frida_js"
                        )
                    }
                )
            }
            .navigationTitle("Frida 调试")
            .navigationBarItems(
                trailing: HStack {
                    Button {
                        showScriptLibrary = true
                    } label: {
                        Image(systemName: "books.vertical")
                    }

                    Menu {
                        Button {
                            showAppPicker = true
                        } label: {
                            Label("选择目标应用", systemImage: "app.badge.checkmark")
                        }

                        Button {
                            showProcessPicker = true
                        } label: {
                            Label("选择应用进程", systemImage: "dot.radiowaves.left.and.right")
                        }

                        Button {
                            fridaEngine.detach()
                        } label: {
                            Label("断开连接", systemImage: "xmark.circle")
                        }

                        Button {
                            fridaEngine.clearConsole()
                        } label: {
                            Label("清除控制台", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            )
            .sheet(isPresented: $showProcessPicker) {
                ProcessPickerView(
                    fridaEngine: fridaEngine,
                    selectedProcess: $selectedProcess,
                    isPresented: $showProcessPicker
                )
            }
            .sheet(isPresented: $showScriptLibrary) {
                ScriptLibraryView(fridaEngine: fridaEngine)
            }
            .sheet(isPresented: $showAppPicker) {
                AppPickerView(
                    apps: appScanner.apps,
                    selectedApp: $fridaEngine.selectedTargetApp,
                    isPresented: $showAppPicker
                )
            }
        }
    }
}

/// Shows the currently selected target TrollStore app.
struct TargetAppBar: View {
    let targetApp: TrollStoreApp?

    var body: some View {
        HStack(spacing: 10) {
            if let app = targetApp {
                AppIconView(bundlePath: app.bundlePath)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(app.bundleIdentifier)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "target")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("未选择目标应用")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}

/// Connection status indicator bar.
struct ConnectionStatusBar: View {
    let state: FridaSessionState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var statusColor: Color {
        switch state {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .attached: return .green
        case .scriptLoaded: return .blue
        case .error: return .red
        }
    }

    private var statusText: String {
        switch state {
        case .disconnected: return "未连接 — 请选择应用进程"
        case .connecting: return "正在连接..."
        case .attached(let name): return "已附加: \(name)"
        case .scriptLoaded(let name): return "脚本已加载: \(name)"
        case .error(let msg): return "错误: \(msg)"
        }
    }
}

/// Console output display.
struct ConsoleOutputView: View {
    let messages: [ConsoleMessage]

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(messages) { msg in
                        ConsoleMessageView(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(8)
            }
        }
        .background(Color(.systemBackground))
    }
}

struct ConsoleMessageView: View {
    let message: ConsoleMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(prefix)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(color)
                .frame(width: 40, alignment: .leading)

            Text(message.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: message.timestamp)
    }

    private var prefix: String {
        switch message.type {
        case .info: return "[INF]"
        case .error: return "[ERR]"
        case .output: return "[OUT]"
        }
    }

    private var color: Color {
        switch message.type {
        case .info: return .blue
        case .error: return .red
        case .output: return .primary
        }
    }
}

/// Script input area with editor, execute and save buttons.
struct ScriptInputArea: View {
    @Binding var scriptInput: String
    @Binding var scriptName: String
    let onExecute: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("脚本名称", text: $scriptName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                Spacer()

                Button("保存") {
                    onSave()
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(scriptInput.isEmpty)

                Button("执行脚本") {
                    onExecute()
                }
                .buttonStyle(DefaultButtonStyle())
                .disabled(scriptInput.isEmpty)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $scriptInput)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                if scriptInput.isEmpty {
                    Text("// 输入 Frida JS 脚本...\n// 例如: send(Process.id);")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
    }
}

/// Process picker sheet for selecting which app to attach to.
struct ProcessPickerView: View {
    @ObservedObject var fridaEngine: FridaEngine
    @Binding var selectedProcess: LocalProcess?
    @Binding var isPresented: Bool

    @State private var processes: [LocalProcess] = []
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $searchText)
                    .padding(8)

                // Process list
                if processes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "ladybug")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("暂无可附加进程")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Frida-gadget 未运行或无可附加的 TrollStore 应用进程")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredProcesses, id: \.id) { process in
                        Button {
                            selectedProcess = process
                            fridaEngine.attach(to: process)
                            isPresented = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(process.name)
                                        .font(.body)
                                    Text("PID: \(process.pid)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "link.badge.plus")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }

                // Security notice
                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.green)
                    Text("仅可附加用户自选的 TrollStore 应用进程")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
            }
            .navigationTitle("选择应用进程")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { isPresented = false }
            )
            .onAppear {
                processes = fridaEngine.listAttachableProcesses()
            }
        }
    }

    private var filteredProcesses: [LocalProcess] {
        if searchText.isEmpty {
            return processes
        }
        return processes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
}

/// Local script library view — shows saved Lua/Frida JS scripts.
struct ScriptLibraryView: View {
    @ObservedObject var fridaEngine: FridaEngine
    @Environment(\.presentationMode) var presentationMode
    @State private var scripts: [LocalScriptModel] = []

    var body: some View {
        NavigationView {
            Group {
                if scripts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("暂无保存的脚本")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(scripts) { script in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(script.scriptName)
                                .font(.body)
                            HStack(spacing: 8) {
                                Text(script.scriptType)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .cornerRadius(4)
                                Text(script.targetAppUUID)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("本地脚本库")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .onAppear {
                scripts = fridaEngine.loadLocalScripts()
            }
        }
    }
}

struct SearchBar: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.placeholder = "搜索应用..."
        searchBar.delegate = context.coordinator
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, UISearchBarDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }
    }
}

/// Picker for selecting a TrollStore app as the Frida target.
struct AppPickerView: View {
    let apps: [TrollStoreApp]
    @Binding var selectedApp: TrollStoreApp?
    @Binding var isPresented: Bool
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                    .padding(8)

                if apps.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "app.badge")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("暂无 TrollStore 应用")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("请先在「沙盒浏览」标签页完成应用扫描")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredApps, id: \.id) { app in
                        Button {
                            selectedApp = app
                            isPresented = false
                        } label: {
                            HStack(spacing: 12) {
                                AppIconView(bundlePath: app.bundlePath)
                                    .frame(width: 40, height: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.displayName)
                                        .font(.body)
                                    Text(app.bundleIdentifier)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if selectedApp?.id == app.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("选择目标应用")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { isPresented = false }
            )
        }
    }

    private var filteredApps: [TrollStoreApp] {
        if searchText.isEmpty { return apps }
        return apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }
}
