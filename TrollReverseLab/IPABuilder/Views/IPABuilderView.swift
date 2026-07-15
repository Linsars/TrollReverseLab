import SwiftUI

// MARK: - IPA Builder View

struct IPABuilderView: View {

    @EnvironmentObject var manager: IPABuilderManager
    @EnvironmentObject var aiClient: AIScriptClient

    @State private var showAIGenerator = false
    @State private var aiDescription = ""
    @State private var showBuildResult = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Configuration form
                Form {
                    Section(header: Text("应用信息")) {
                        TextField("应用名称", text: $manager.config.appName)
                        TextField("Bundle ID", text: $manager.config.bundleId)
                        HStack {
                            TextField("版本", text: $manager.config.version)
                            TextField("Build", text: $manager.config.buildNumber)
                        }
                        Picker("最低 iOS 版本", selection: $manager.config.minIOSVersion) {
                            ForEach(["14.0", "15.0", "16.0", "17.0"], id: \.self) { Text($0) }
                        }
                    }

                    Section(header: Text("权限配置")) {
                        ForEach(manager.entitlementOptions) { opt in
                            Toggle(isOn: Binding(
                                get: { manager.config.entitlements.contains(opt.id) },
                                set: { _ in manager.toggleEntitlement(opt.id) }
                            )) {
                                HStack {
                                    Image(systemName: opt.icon)
                                        .foregroundColor(.accentColor)
                                        .frame(width: 24)
                                    VStack(alignment: .leading) {
                                        Text(opt.title)
                                        Text(opt.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Section(header: Text("源码")) {
                        Button(action: { manager.showTemplatePicker = true }) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("从模板选择")
                            }
                        }

                        Button(action: { showAIGenerator = true }) {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("AI 生成源码")
                            }
                            .foregroundColor(.purple)
                        }

                        Button(action: { manager.showSnapshotPicker = true }) {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("历史快照 (\(manager.snapshots.count))")
                            }
                        }

                        NavigationLink(destination: SourceEditorView(sourceCode: $manager.config.sourceCode)) {
                            HStack {
                                Image(systemName: "chevron.left.slash.chevron.right")
                                Text("编辑源码")
                            }
                        }
                    }

                    Section(header: Text("构建")) {
                        Button(action: buildProject) {
                            HStack {
                                Image(systemName: "hammer.fill")
                                Text(manager.isBuilding ? "构建中..." : "构建项目")
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(manager.isBuilding ? Color.gray : Color.accentColor)
                            )
                        }
                        .disabled(manager.isBuilding)
                        .listRowBackground(Color.clear)

                        if manager.isBuilding {
                            ProgressView(value: manager.buildProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                        }

                        if !manager.buildLog.isEmpty {
                            NavigationLink(destination: BuildLogView(log: manager.buildLog)) {
                                HStack {
                                    Image(systemName: "doc.text.magnifyingglass")
                                    Text("构建日志")
                                    Spacer()
                                    Text("\(manager.buildLog.count) 行")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        if let path = manager.lastBuildPath {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("输出: \(path)")
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("IPA 编译")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $manager.showTemplatePicker) {
                TemplatePickerSheet(manager: manager)
            }
            .sheet(isPresented: $manager.showSnapshotPicker) {
                SnapshotPickerSheet(manager: manager)
            }
            .sheet(isPresented: $showAIGenerator) {
                AIGeneratorSheet(
                    description: $aiDescription,
                    manager: manager,
                    aiClient: aiClient
                )
            }
        }
    }

    private func buildProject() {
        manager.buildProject { result in
            switch result {
            case .success:
                showBuildResult = true
            case .failure(let error):
                manager.buildLog.append("❌ 构建失败: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Source Editor View

struct SourceEditorView: View {
    @Binding var sourceCode: String

    var body: some View {
        VStack(spacing: 0) {
            Text("源码编辑器")
                .font(.headline)
                .padding()

            TextEditor(text: $sourceCode)
                .font(.system(size: 13, design: .monospaced))
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .navigationTitle("编辑源码")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Template Picker

struct TemplatePickerSheet: View {
    @ObservedObject var manager: IPABuilderManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                ForEach(SourceTemplate.templates) { template in
                    Button(action: {
                        manager.loadTemplate(template)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Image(systemName: template.icon)
                                .foregroundColor(.accentColor)
                                .frame(width: 32)
                            VStack(alignment: .leading) {
                                Text(template.title)
                                    .foregroundColor(.primary)
                                Text(template.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("选择模板")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { presentationMode.wrappedValue.dismiss() }
            )
        }
    }
}

// MARK: - Snapshot Picker

struct SnapshotPickerSheet: View {
    @ObservedObject var manager: IPABuilderManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                if manager.snapshots.isEmpty {
                    Text("暂无快照")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(manager.snapshots) { snapshot in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(snapshot.label)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(formattedDate(snapshot.timestamp))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(snapshot.config.appName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: { manager.deleteSnapshot(snapshot) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            manager.loadSnapshot(snapshot)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("历史快照")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { presentationMode.wrappedValue.dismiss() },
                trailing: Button("保存当前") {
                    manager.saveSnapshot(label: "手动保存")
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - AI Generator Sheet

struct AIGeneratorSheet: View {
    @Binding var description: String
    @ObservedObject var manager: IPABuilderManager
    @ObservedObject var aiClient: AIScriptClient
    @Environment(\.presentationMode) var presentationMode
    @State private var isGenerating = false
    @State private var result: String?

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("描述你想要的工具:")
                    .font(.headline)

                TextEditor(text: $description)
                    .frame(height: 120)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))

                // Suggestions
                VStack(alignment: .leading, spacing: 8) {
                    Text("建议:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach([
                        "一个记录每日发帖数据并生成统计图表的工具",
                        "一个批量管理本地图片素材并添加标签的工具",
                        "一个生成短视频脚本模板的文案工具",
                        "一个记录设备状态变化日志的监控工具"
                    ], id: \.self) { suggestion in
                        Button(action: { description = suggestion }) {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .padding(.vertical, 4)
                        }
                    }
                }

                if isGenerating {
                    HStack {
                        ProgressView()
                        Text("AI 正在生成源码...")
                    }
                }

                if let result = result {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("成功") ? .green : .red)
                }

                Spacer()

                Button(action: generate) {
                    Text("生成源码")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Capsule().fill(Color.purple))
                        .foregroundColor(.white)
                }
                .disabled(description.isEmpty || isGenerating)
            }
            .padding()
            .navigationTitle("AI 生成")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { presentationMode.wrappedValue.dismiss() },
                trailing: Button("使用") {
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(result == nil || !result!.contains("成功"))
            )
        }
    }

    private func generate() {
        isGenerating = true
        result = nil
        manager.generateFromAI(description: description, aiClient: aiClient) { res in
            isGenerating = false
            switch res {
            case .success:
                result = "✅ 源码生成成功！点击「使用」查看。"
            case .failure(let error):
                result = "❌ 生成失败: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Build Log View

struct BuildLogView: View {
    let log: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(line.contains("❌") ? .red :
                                        line.contains("✅") ? .green : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle("构建日志")
        .navigationBarTitleDisplayMode(.inline)
    }
}
