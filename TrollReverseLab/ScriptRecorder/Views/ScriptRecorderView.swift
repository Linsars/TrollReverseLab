import SwiftUI
import UIKit

// MARK: - Script Recorder View

struct ScriptRecorderView: View {
    @EnvironmentObject var manager: ScriptRecorderManager

    var body: some View {
        NavigationView {
            List {
                // Recording section
                Section(header: Text("录制操作")) {
                    if manager.isRecording {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "record.circle.fill")
                                    .foregroundColor(.red)
                                Text("正在录制...")
                                    .foregroundColor(.red)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(manager.liveActions.count) 个动作")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Button("停止录制并保存") {
                                _ = manager.stopRecording()
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        Button {
                            manager.startRecording(targetBundleId: "", targetAppName: "通用录制")
                        } label: {
                            Label("开始新录制", systemImage: "record.circle")
                        }
                    }
                }

                // Scripts list
                Section(header: Text("录制脚本")) {
                    if manager.scripts.isEmpty {
                        Text("暂无录制脚本，开始录制或手动创建")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    ForEach(manager.scripts) { script in
                        NavigationLink(destination: ScriptDetailView(script: script)) {
                            ScriptRowView(script: script)
                        }
                    }
                    .onDelete(perform: deleteScript)
                }

                // Educational info
                Section(header: Text("动作类型说明"), footer: Text("手动录制交互动作用于学习 iOS App 交互流程和 UI 自动化技术，回放为教学演示，不执行实际自动化操作")) {
                    ForEach(RecordedActionType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.iconName)
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(type.displayName)
                                    .font(.subheadline)
                                Text(type.educationalNote)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("脚本录制")
            .navigationBarItems(trailing: NavigationLink(destination: CreateScriptView()) {
                Image(systemName: "plus")
            })
        }
    }

    private func deleteScript(at offsets: IndexSet) {
        for index in offsets {
            manager.deleteScript(manager.scripts[index])
        }
    }
}

// MARK: - Script Row

struct ScriptRowView: View {
    let script: ScriptRecord

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }

    var body: some View {
        HStack {
            Image(systemName: "play.rectangle")
                .foregroundColor(.accentColor)
                .font(.caption)
            VStack(alignment: .leading, spacing: 4) {
                Text(script.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack {
                    Text("\(script.actionCount) 个动作")
                        .font(.caption2)
                    Text(dateFormatter.string(from: script.createdAt))
                        .font(.caption2)
                    if let lastPlayed = script.lastPlayedAt {
                        Text("上次回放: \(dateFormatter.string(from: lastPlayed))")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Create Script View

struct CreateScriptView: View {
    @EnvironmentObject var manager: ScriptRecorderManager
    @Environment(\.presentationMode) var presentationMode
    @State private var name = ""
    @State private var description = ""

    var body: some View {
        Form {
            Section(header: Text("脚本信息")) {
                TextField("脚本名称", text: $name)
                TextField("描述", text: $description)
            }

            Section(header: Text("动作类型")) {
                ForEach(RecordedActionType.allCases, id: \.self) { type in
                    HStack {
                        Image(systemName: type.iconName)
                            .foregroundColor(.accentColor)
                        Text(type.displayName)
                        Spacer()
                        Text(type.educationalNote)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("新建脚本")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(
            leading: Button("取消") { presentationMode.wrappedValue.dismiss() },
            trailing: Button("创建") {
                let script = manager.createScript(name: name.isEmpty ? "未命名脚本" : name)
                presentationMode.wrappedValue.dismiss()
            }
            .disabled(name.isEmpty)
        )
    }
}

// MARK: - Script Detail View

struct ScriptDetailView: View {
    @EnvironmentObject var manager: ScriptRecorderManager
    @State var script: ScriptRecord
    @State private var showAddAction = false
    @State private var showPlayback = false
    @State private var showExportPreview = false
    @State private var exportText = ""
    @State private var showAIContext = false
    @State private var aiContextText = ""

    var body: some View {
        Form {
            // Script info
            Section(header: Text("脚本信息")) {
                TextField("名称", text: $script.name, onCommit: {
                    manager.updateScript(script)
                })
                if !script.targetAppName.isEmpty {
                    HStack {
                        Text("目标应用")
                        Spacer()
                        Text(script.targetAppName).foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text("动作数量")
                    Spacer()
                    Text("\(script.actionCount)").foregroundColor(.secondary)
                }
                HStack {
                    Text("录制时长")
                    Spacer()
                    Text(String(format: "%.1f s", script.totalDuration)).foregroundColor(.secondary)
                }
            }

            // Actions list
            Section(header: Text("动作序列")) {
                if script.actions.isEmpty {
                    Text("暂无动作，点击下方添加")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                ForEach(script.actions) { action in
                    ActionRowView(action: action, index: action.order)
                }
                .onDelete { offsets in
                    for index in offsets {
                        manager.removeActionFromScript(script, at: index)
                    }
                    if let updated = manager.scripts.first(where: { $0.id == script.id }) {
                        script = updated
                    }
                }
            }

            // Add action
            Section(header: Text("添加动作")) {
                Button {
                    showAddAction = true
                } label: {
                    Label("手动添加动作", systemImage: "plus.circle")
                }
            }

            // Playback
            Section(header: Text("回放演示"), footer: Text("回放仅用于教学演示，展示动作序列和学习要点，不执行实际自动化操作")) {
                Button {
                    manager.startPlayback(script: script)
                    showPlayback = true
                } label: {
                    Label("开始回放演示", systemImage: "play.fill")
                }
                .disabled(script.actions.isEmpty)
            }

            // Export
            Section(header: Text("导出")) {
                Button {
                    exportText = manager.exportAsText(script)
                    showExportPreview = true
                } label: {
                    Label("导出为文本", systemImage: "doc.text")
                }
                Button {
                    aiContextText = manager.aiContext(script)
                    showAIContext = true
                } label: {
                    Label("生成 AI 学习上下文", systemImage: "brain")
                }
            }
        }
        .navigationTitle(script.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddAction) {
            AddActionSheet(script: $script)
        }
        .sheet(isPresented: $showPlayback) {
            PlaybackView(script: script)
        }
        .sheet(isPresented: $showExportPreview) {
            ExportTextPreview(text: exportText, title: "脚本导出")
        }
        .sheet(isPresented: $showAIContext) {
            ExportTextPreview(text: aiContextText, title: "AI 学习上下文")
        }
    }
}

// MARK: - Action Row

struct ActionRowView: View {
    let action: RecordedAction
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: action.type.iconName)
                    .foregroundColor(.accentColor)
                    .font(.caption)
                Text("#\(index + 1) \(action.type.displayName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "+%.2fs", action.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(action.description)
                .font(.caption)
                .foregroundColor(.secondary)
            if !action.label.isEmpty {
                Text("标注: \(action.label)")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }
            Text(action.type.educationalNote)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }
}

// MARK: - Add Action Sheet

struct AddActionSheet: View {
    @EnvironmentObject var manager: ScriptRecorderManager
    @Binding var script: ScriptRecord
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedType: RecordedActionType = .tap
    @State private var x: String = ""
    @State private var y: String = ""
    @State private var endX: String = ""
    @State private var endY: String = ""
    @State private var text: String = ""
    @State private var duration: String = "1.0"
    @State private var label: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("动作类型")) {
                    Picker("类型", selection: $selectedType) {
                        ForEach(RecordedActionType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName).tag(type)
                        }
                    }
                }

                Section(header: Text("参数")) {
                    switch selectedType {
                    case .tap, .longPress:
                        TextField("X 坐标", text: $x).keyboardType(.numberPad)
                        TextField("Y 坐标", text: $y).keyboardType(.numberPad)
                        if selectedType == .longPress {
                            TextField("持续时间(秒)", text: $duration).keyboardType(.decimalPad)
                        }
                    case .swipe:
                        TextField("起点 X", text: $x).keyboardType(.numberPad)
                        TextField("起点 Y", text: $y).keyboardType(.numberPad)
                        TextField("终点 X", text: $endX).keyboardType(.numberPad)
                        TextField("终点 Y", text: $endY).keyboardType(.numberPad)
                    case .textInput, .note:
                        TextEditor(text: $text).frame(minHeight: 80)
                    case .wait:
                        TextField("等待时间(秒)", text: $duration).keyboardType(.decimalPad)
                    case .screenshot:
                        Text("截图动作用于标记截图位置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("标注")) {
                    TextField("动作标注（可选）", text: $label)
                }

                Section(header: Text("教学说明")) {
                    Text(selectedType.educationalNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("添加动作")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { presentationMode.wrappedValue.dismiss() },
                trailing: Button("添加") { addAction() }
            )
        }
    }

    private func addAction() {
        let xVal = CGFloat(Double(x) ?? 0)
        let yVal = CGFloat(Double(y) ?? 0)
        let endXVal = Double(endX).map { CGFloat($0) }
        let endYVal = Double(endY).map { CGFloat($0) }
        let dur = Double(duration) ?? 1.0

        let action = RecordedAction(
            type: selectedType,
            x: xVal,
            y: yVal,
            endX: endXVal,
            endY: endYVal,
            textContent: text.isEmpty ? nil : text,
            duration: selectedType == .wait || selectedType == .longPress ? dur : nil,
            label: label
        )

        manager.addActionToScript(script, action: action)
        if let updated = manager.scripts.first(where: { $0.id == script.id }) {
            script = updated
        }
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Playback View

struct PlaybackView: View {
    @EnvironmentObject var manager: ScriptRecorderManager
    let script: ScriptRecord
    @State private var currentIndex = 0
    @State private var currentAction: RecordedAction? = nil
    @State private var isFinished = false
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Progress
                VStack {
                    Text("回放演示")
                        .font(.title2)
                        .fontWeight(.bold)

                    ProgressView(value: Double(currentIndex), total: Double(max(script.actionCount, 1)))
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)

                    Text("\(currentIndex) / \(script.actionCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                // Current action
                if let action = currentAction {
                    VStack(spacing: 12) {
                        Image(systemName: action.type.iconName)
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)

                        Text(action.type.displayName)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(action.description)
                            .font(.body)

                        if !action.label.isEmpty {
                            Text("标注: \(action.label)")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }

                        // Educational note
                        VStack(alignment: .leading, spacing: 4) {
                            Text("教学要点")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(action.type.educationalNote)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                } else if isFinished {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("回放完成")
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                    .padding()
                }

                Spacer()

                // Controls
                HStack {
                    Button("上一步") {
                        if currentIndex > 0 {
                            currentIndex -= 1
                            currentAction = script.actions[currentIndex]
                        }
                    }
                    .disabled(currentIndex == 0)

                    Spacer()

                    if currentIndex < script.actionCount {
                        Button("下一步") {
                            if currentIndex < script.actionCount {
                                currentAction = script.actions[currentIndex]
                                currentIndex += 1
                            }
                            if currentIndex >= script.actionCount {
                                isFinished = true
                            }
                        }
                        .buttonStyle(DefaultButtonStyle())
                    } else {
                        Button("完成") {
                            manager.stopPlayback()
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("回放: \(script.name)")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !script.actions.isEmpty {
                    currentAction = script.actions[0]
                    currentIndex = 1
                }
            }
            .onDisappear {
                manager.stopPlayback()
            }
        }
    }
}

// MARK: - Export Text Preview

struct ExportTextPreview: View {
    let text: String
    let title: String
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
