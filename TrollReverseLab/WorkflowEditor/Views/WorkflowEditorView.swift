import SwiftUI

// MARK: - Workflow Editor View (Main Container)

struct WorkflowEditorView: View {
    @EnvironmentObject var aiClient: AIScriptClient
    @StateObject private var engine = WorkflowEngine()
    @State private var showSavedWorkflows: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var showClearConfirm: Bool = false
    @State private var workflowNameInput: String = ""
    @State private var showSaveSheet: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Canvas
            WorkflowCanvasView(engine: engine)
                .ignoresSafeArea(edges: .bottom)

            // AI Input Bar
            AIInputBar(engine: engine)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .navigationBarTitle("工作流", displayMode: .inline)
        .navigationBarItems(
            leading: leadingButtons,
            trailing: trailingButtons
        )
        .onAppear {
            engine.aiClient = aiClient
        }
        .sheet(isPresented: $showSavedWorkflows) {
            WorkflowListView(
                onLoad: { workflow in
                    engine.loadWorkflow(workflow)
                    showSavedWorkflows = false
                },
                onDelete: { id in
                    Workflow.delete(id: id)
                }
            )
        }
        .sheet(isPresented: $showExportSheet) {
            ExportView(engine: engine)
        }
        .sheet(isPresented: $showSaveSheet) {
            saveSheet
        }
        .alert(isPresented: $showClearConfirm) {
            Alert(
                title: Text("清空画布"),
                message: Text("将删除所有节点和连线，此操作不可撤销。"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("确认清空"), action: { engine.clearAll() })
            )
        }
    }

    // MARK: - Leading Buttons

    private var leadingButtons: some View {
        HStack(spacing: 12) {
            // New workflow
            Button(action: {
                showClearConfirm = true
            }) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }

            // Open saved
            Button(action: {
                showSavedWorkflows = true
            }) {
                Image(systemName: "folder.open")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Trailing Buttons

    private var trailingButtons: some View {
        HStack(spacing: 12) {
            // Node count badge
            Text("\(engine.nodes.count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.15)))

            // Save
            Button(action: {
                workflowNameInput = engine.workflowName
                showSaveSheet = true
            }) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }

            // Export
            Button(action: {
                showExportSheet = true
            }) {
                Image(systemName: "doc.text")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Save Sheet

    private var saveSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)

                Text("保存工作流")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                TextField("工作流名称", text: $workflowNameInput)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1)))

                Text("\(engine.nodes.count) 个节点 · \(engine.connections.count) 条连线")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()
            }
            .padding()
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .navigationTitle("保存")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { showSaveSheet = false }
                    .foregroundColor(.white),
                trailing: Button("保存") {
                    engine.workflowName = workflowNameInput
                    engine.saveWorkflow()
                    showSaveSheet = false
                }
                .foregroundColor(.white)
            )
        }
    }
}

// MARK: - Workflow List View

struct WorkflowListView: View {
    let onLoad: (Workflow) -> Void
    let onDelete: (UUID) -> Void

    @State private var workflows: [Workflow] = []
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Group {
                if workflows.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.3))
                        Text("暂无保存的工作流")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                } else {
                    List {
                        ForEach(workflows) { workflow in
                            Button(action: {
                                onLoad(workflow)
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                WorkflowRow(workflow: workflow)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let wf = workflows[index]
                                onDelete(wf.id)
                            }
                            loadWorkflows()
                        }
                    }
                }
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .navigationTitle("工作流列表")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.white)
            )
        }
        .onAppear { loadWorkflows() }
    }

    private func loadWorkflows() {
        workflows = Workflow.loadAll()
    }
}

// MARK: - Workflow Row

struct WorkflowRow: View {
    let workflow: Workflow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(workflow.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Text("\(workflow.nodeCount) 节点")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            if !workflow.userInput.isEmpty {
                Text(workflow.userInput)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
            }

            // Category dots
            HStack(spacing: 4) {
                ForEach(workflow.nodes.prefix(8), id: \.id) { node in
                    Circle()
                        .fill(node.category.swiftUIColor)
                        .frame(width: 8, height: 8)
                }
                if workflow.nodes.count > 8 {
                    Text("+\(workflow.nodes.count - 8)")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer()
                Text(formatDate(workflow.updatedAt))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Export View

struct ExportView: View {
    @ObservedObject var engine: WorkflowEngine
    @Environment(\.presentationMode) var presentationMode
    @State private var exportText: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("工作流导出")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text("执行顺序脚本 (可用于 AI 脚本生成参考)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))

                    Text(exportText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                }
                .padding()
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("关闭") {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.white),
                trailing: Button("复制") {
                    UIPasteboard.general.string = exportText
                }
                .foregroundColor(.white)
            )
        }
        .onAppear {
            exportText = engine.exportAsScript()
        }
    }
}
