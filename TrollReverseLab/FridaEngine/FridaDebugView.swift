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
    @State private var scriptInput = ""
    @State private var scriptName = ""
    @State private var showHostAppPicker = false
    @State private var showScriptLibrary = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 当前托管目标栏
                TargetAppBar(target: fridaEngine.currentTarget)

                Divider()

                // 目标死讯大字报
                if case .terminated(let procName, let reason) = fridaEngine.state {
                    DeathNoticeBar(processName: procName, reason: reason)
                }

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
                    // 主入口：选 app 真后台启动 + 自动 attach
                    Button {
                        showHostAppPicker = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }

                    Button {
                        showScriptLibrary = true
                    } label: {
                        Image(systemName: "books.vertical")
                    }

                    Menu {
                        Button {
                            fridaEngine.detach()
                        } label: {
                            Label("断开 frida（app 继续运行）", systemImage: "xmark.circle")
                        }

                        if fridaEngine.currentTarget != nil {
                            Button {
                                fridaEngine.releaseHostedApp()
                            } label: {
                                Label("关闭目标 app", systemImage: "power")
                                    .foregroundColor(.red)
                            }
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
            .sheet(isPresented: $showHostAppPicker) {
                HostAppPickerView(
                    fridaEngine: fridaEngine,
                    isPresented: $showHostAppPicker
                )
            }
            .sheet(isPresented: $showScriptLibrary) {
                ScriptLibraryView(fridaEngine: fridaEngine)
            }
        }
    }
}

/// 当前托管目标栏
struct TargetAppBar: View {
    let target: LocalProcess?

    var body: some View {
        HStack(spacing: 10) {
            if let t = target {
                Image(systemName: "hourglass.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("PID \(t.pid) · 真后台常驻")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "target")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("点右上角 + 选 app → 真后台启动 → 自动 attach")
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

/// 选 app 真后台托管 + frida attach（唯一目标入口）
struct HostAppPickerView: View {
    @ObservedObject var fridaEngine: FridaEngine
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var apps: [SceneHostApp] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                    .padding(8)

                List(filteredApps, id: \.bundleId) { app in
                    Button {
                        isPresented = false
                        fridaEngine.hostAndAttach(bundleId: app.bundleId, appName: app.name)
                    } label: {
                        HStack(spacing: 12) {
                            if let icon = AppSceneHost.shared().icon(forBundleId: app.bundleId) {
                                Image(uiImage: icon)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.body)
                                Text(app.bundleId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "hourglass")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("选 app 真后台 + frida")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { isPresented = false }
            )
            .onAppear {
                apps = AppSceneHost.shared().installedApps()
            }
        }
    }

    private var filteredApps: [SceneHostApp] {
        if searchText.isEmpty { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }
}

/// 目标死讯大字报——进程被系统回收/连接被掐时的醒目横幅
struct DeathNoticeBar: View {
    let processName: String
    let reason: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("目标进程已被系统回收")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("\(processName) 已失联（\(reason)）——iOS 后台 app 会被 jetsam 杀掉，请保持目标在前台后重新附加")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.red)
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
        case .terminated: return .red
        case .error: return .red
        }
    }

    private var statusText: String {
        switch state {
        case .disconnected: return "未连接 — 请选择目标进程"
        case .connecting: return "正在连接..."
        case .attached(let name): return "已附加: \(name) — 脚本未加载，正常状态"
        case .scriptLoaded(let name): return "脚本已加载: \(name) — 会话继续可用，非断开"
        case .terminated(let name, let reason): return "⚠️ 目标已死: \(name)（\(reason)）"
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
    @State private var isExpanded = false

    /// 超过这个行数/字符数 = 折叠成卡片
    private static let collapseLineCount = 6
    private static let expandCharThreshold = 600
    /// 展开后的卡片最大高度（超高内容卡片内滚动）
    private static let expandedMaxHeight: CGFloat = 320

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

            Group {
                if isExpandable && !isExpanded {
                    // 截断卡片：前 N 行 + 展开提示
                    VStack(alignment: .leading, spacing: 4) {
                        Text(collapsedText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                            Text("已截断 · 全文 \(lineCount) 行 \(message.text.count) 字符 · 点开查看")
                        }
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    }
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { isExpanded = true }
                } else if isExpandable {
                    // 展开卡片：内部滚动 + 收起
                    VStack(alignment: .leading, spacing: 4) {
                        ScrollView {
                            Text(message.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                        }
                        .frame(maxHeight: Self.expandedMaxHeight)
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                            Text("收起")
                        }
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    }
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { isExpanded = false }
                } else {
                    Text(message.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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

    private var lines: [String] {
        message.text.components(separatedBy: .newlines)
    }

    private var lineCount: Int { lines.count }

    private var isExpandable: Bool {
        lineCount > Self.collapseLineCount || message.text.count > Self.expandCharThreshold
    }

    private var collapsedText: String {
        lines.prefix(Self.collapseLineCount).joined(separator: "\n")
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
