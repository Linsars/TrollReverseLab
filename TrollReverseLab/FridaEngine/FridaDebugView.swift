//
//  FridaDebugView.swift
//  TrollReverseLab
//
//  Module 2: Frida debug engine UI.
//  Shows process attachment, script execution, console output,
//  and function tracing for local reverse engineering research.
//

import SwiftUI

struct FridaDebugView: View {
    @EnvironmentObject var fridaEngine: FridaEngine
    @State private var scriptInput = ""
    @State private var scriptName = ""
    @State private var showProcessPicker = false
    @State private var selectedProcess: LocalProcess?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Connection status bar
                ConnectionStatusBar(state: fridaEngine.state)

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
                    }
                )
            }
            .navigationTitle("Frida 调试")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
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

                        Divider()

                        Button {
                            fridaEngine.clearConsole()
                        } label: {
                            Label("清除控制台", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showProcessPicker) {
                ProcessPickerView(
                    fridaEngine: fridaEngine,
                    selectedProcess: $selectedProcess,
                    isPresented: $showProcessPicker
                )
            }
        }
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

/// Script input area with editor and execute button.
struct ScriptInputArea: View {
    @Binding var scriptInput: String
    @Binding var scriptName: String
    let onExecute: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("脚本名称", text: $scriptName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                Spacer()

                Button("执行脚本") {
                    onExecute()
                }
                .buttonStyle(.borderedProminent)
                .disabled(scriptInput.isEmpty)
            }

            TextEditor(text: $scriptInput)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
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
                List(filteredProcesses, id: \.id) { process in
                    Button {
                        selectedProcess = process
                        fridaEngine.attach(to: process, isUserSelected: true)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
            }
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
