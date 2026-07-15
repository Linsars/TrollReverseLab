import SwiftUI

// MARK: - Node Detail Sheet

struct NodeDetailSheet: View {
    @Binding var node: WorkflowNode
    let onDelete: () -> Void
    let onAIOptimize: () -> Void

    @Environment(\.presentationMode) var presentationMode
    @State private var newParamKey: String = ""
    @State private var newParamValue: String = ""
    @State private var showAIOptimizeConfirm: Bool = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Node header
                    nodeHeader

                    // AI Note
                    aiNoteSection

                    // Parameters
                    parametersSection

                    // Ports info
                    portsSection

                    // Risk info
                    if node.riskLevel != .none {
                        riskSection
                    }

                    // Actions
                    actionsSection
                }
                .padding()
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .navigationTitle("节点详情")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.white),
                trailing: Button("保存") {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.white)
            )
        }
    }

    // MARK: - Node Header

    private var nodeHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: node.category.gradientColors.map { Color($0) }),
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: node.iconSystemName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("节点名称", text: $node.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Circle().fill(node.category.swiftUIColor).frame(width: 6, height: 6)
                    Text(node.category.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    if node.riskLevel != .none {
                        Text("· \(node.riskLevel.label)")
                            .font(.system(size: 11))
                            .foregroundColor(node.riskLevel.requiresConfirmation ? .red : .orange)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    // MARK: - AI Note

    private var aiNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14))
                    .foregroundColor(.purple)
                Text("AI 备注")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if node.aiOptimized {
                    Text("已优化")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.2)))
                }
            }

            TextEditor(text: $node.aiNote)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
                .frame(minHeight: 60)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))

            Button(action: { showAIOptimizeConfirm = true }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("AI 优化此节点")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.4)))
            }
            .alert(isPresented: $showAIOptimizeConfirm) {
                Alert(
                    title: Text("AI 优化"),
                    message: Text("AI 将分析此节点的参数并自动优化。是否继续？"),
                    primaryButton: .cancel(Text("取消")),
                    secondaryButton: .default(Text("确认优化"), action: { onAIOptimize() })
                )
            }        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Parameters

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                Text("参数配置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            if node.parameters.isEmpty {
                Text("暂无参数")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }

            ForEach(Array(node.parameters.keys.sorted()), id: \.self) { key in
                HStack(spacing: 8) {
                    Text(key)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 80, alignment: .leading)

                    TextField("值", text: Binding(
                        get: { node.parameters[key] ?? "" },
                        set: { node.parameters[key] = $0 }
                    ))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))

                    Button(action: { node.parameters.removeValue(forKey: key) }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
            }

            // Add new parameter
            HStack(spacing: 8) {
                TextField("键", text: $newParamKey)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                    .frame(width: 80)

                TextField("值", text: $newParamValue)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))

                Button(action: {
                    guard !newParamKey.isEmpty else { return }
                    node.parameters[newParamKey] = newParamValue
                    newParamKey = ""
                    newParamValue = ""
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Ports

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tuningfork")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                Text("端口")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            HStack(alignment: .top, spacing: 16) {
                // Input ports
                VStack(alignment: .leading, spacing: 4) {
                    Text("输入")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    ForEach(Array(node.inputPorts.enumerated()), id: \.element.id) { idx, port in
                        HStack(spacing: 4) {
                            Circle().fill(Color.white).frame(width: 6, height: 6)
                            Text(port.label)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }

                Divider().frame(height: 40)

                // Output ports
                VStack(alignment: .leading, spacing: 4) {
                    Text("输出")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    ForEach(Array(node.outputPorts.enumerated()), id: \.element.id) { idx, port in
                        HStack(spacing: 4) {
                            Circle().fill(Color.white).frame(width: 6, height: 6)
                            Text(port.label)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Risk

    private var riskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("风险提示")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red)
            }

            Text("此节点风险等级: \(node.riskLevel.label)")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))

            if node.riskLevel.requiresConfirmation {
                Toggle("已确认风险", isOn: $node.isRiskConfirmed)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 8) {
            Toggle("启用此节点", isOn: $node.isEnabled)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))

            Button(action: onDelete) {
                HStack {
                    Image(systemName: "trash")
                    Text("删除节点")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
            }
        }
    }
}
