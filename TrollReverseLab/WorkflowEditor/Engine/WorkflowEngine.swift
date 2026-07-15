import SwiftUI
import Combine

// MARK: - Workflow Engine

class WorkflowEngine: ObservableObject {

    // Canvas state
    @Published var canvasOffset: CGSize = .zero
    @Published var canvasScale: CGFloat = 1.0
    @Published var minScale: CGFloat = 0.3
    @Published var maxScale: CGFloat = 2.5

    // Nodes & connections
    @Published var nodes: [WorkflowNode] = []
    @Published var connections: [NodeConnection] = []
    @Published var selectedNodeID: UUID?
    @Published var selectedConnectionID: UUID?

    // Interaction state
    @Published var draggingNodeID: UUID?
    @Published var connectingFromNodeID: UUID?
    @Published var connectingFromPortIndex: Int = 0
    @Published var dragOffset: CGSize = .zero

    // AI state
    @Published var isGenerating: Bool = false
    @Published var aiMessages: [String] = []
    @Published var lastUserInput: String = ""

    // Workflow metadata
    @Published var workflowName: String = "新工作流"
    @Published var workflowID: UUID = UUID()
    @Published var hasUnsavedChanges: Bool = false

    // Risk confirmation
    @Published var pendingRiskNode: WorkflowNode?
    @Published var showRiskAlert: Bool = false

    // AI context (from other modules)
    var trafficContext: String?
    var targetAppBundleId: String?
    var targetAppName: String?

    // AI client
    var aiClient: AIScriptClient

    init(aiClient: AIScriptClient = AIScriptClient()) {
        self.aiClient = aiClient
    }

    // MARK: - Node Operations

    func addNode(_ node: WorkflowNode) {
        nodes.append(node)
        hasUnsavedChanges = true
    }

    func addNode(from template: NodeTemplate, at position: CGPoint? = nil) -> WorkflowNode {
        let pos = position ?? autoLayoutPosition()
        let node = NodeRegistry.createNode(from: template, position: pos)
        addNode(node)
        return node
    }

    func removeNode(_ id: UUID) {
        nodes.removeAll { $0.id == id }
        connections.removeAll { $0.involves(nodeID: id) }
        if selectedNodeID == id {
            selectedNodeID = nil
        }
        hasUnsavedChanges = true
    }

    func updateNode(_ node: WorkflowNode) {
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            nodes[index] = node
            hasUnsavedChanges = true
        }
    }

    func moveNode(_ id: UUID, to position: CGPoint) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes[index].position = position
            hasUnsavedChanges = true
        }
    }

    func toggleNodeEnabled(_ id: UUID) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes[index].isEnabled.toggle()
            hasUnsavedChanges = true
        }
    }

    func selectNode(_ id: UUID?) {
        selectedNodeID = id
    }

    // MARK: - Connection Operations

    func addConnection(from: UUID, fromPort: Int = 0, to: UUID, toPort: Int = 0) {
        // Prevent self-connection
        guard from != to else { return }

        // Prevent duplicate connections
        let exists = connections.contains { $0.fromNodeID == from && $0.fromPortIndex == fromPort && $0.toNodeID == to && $0.toPortIndex == toPort }
        guard !exists else { return }

        // Remove existing connection to the same input port (one input one connection)
        connections.removeAll { $0.toNodeID == to && $0.toPortIndex == toPort }

        let conn = NodeConnection(fromNodeID: from, fromPortIndex: fromPort, toNodeID: to, toPortIndex: toPort)
        connections.append(conn)
        hasUnsavedChanges = true
    }

    func removeConnection(_ id: UUID) {
        connections.removeAll { $0.id == id }
        if selectedConnectionID == id {
            selectedConnectionID = nil
        }
        hasUnsavedChanges = true
    }

    // MARK: - Canvas Operations

    func resetCanvas() {
        canvasOffset = .zero
        canvasScale = 1.0
    }

    func clearAll() {
        nodes.removeAll()
        connections.removeAll()
        selectedNodeID = nil
        selectedConnectionID = nil
        hasUnsavedChanges = false
    }

    // MARK: - Auto Layout

    private func autoLayoutPosition() -> CGPoint {
        let baseX: CGFloat = 40
        let baseY: CGFloat = 120
        let stepX: CGFloat = WorkflowNode.width + 80
        let stepY: CGFloat = WorkflowNode.height + 40

        let count = nodes.count
        let col = count % 4
        let row = count / 4

        return CGPoint(x: baseX + CGFloat(col) * stepX, y: baseY + CGFloat(row) * stepY)
    }

    // Auto-layout all nodes in a left-to-right flow based on topological order
    func autoLayoutAll() {
        var inDegree: [UUID: Int] = [:]
        var adj: [UUID: [UUID]] = [:]

        for node in nodes {
            inDegree[node.id] = 0
            adj[node.id] = []
        }

        for conn in connections {
            adj[conn.fromNodeID]?.append(conn.toNodeID)
            inDegree[conn.toNodeID, default: 0] += 1
        }

        // BFS by layers
        var layers: [[UUID]] = []
        var currentLayer = inDegree.filter { $0.value == 0 }.map { $0.key }
        var remaining = inDegree

        while !currentLayer.isEmpty {
            layers.append(currentLayer)
            var nextLayer: [UUID] = []
            for nodeID in currentLayer {
                for neighbor in adj[nodeID] ?? [] {
                    remaining[neighbor]! -= 1
                    if remaining[neighbor]! == 0 {
                        nextLayer.append(neighbor)
                    }
                }
            }
            currentLayer = nextLayer
        }

        // Position nodes by layer
        let baseX: CGFloat = 40
        let baseY: CGFloat = 120
        let stepX: CGFloat = WorkflowNode.width + 100
        let stepY: CGFloat = WorkflowNode.height + 30

        for (colIndex, layer) in layers.enumerated() {
            for (rowIndex, nodeID) in layer.enumerated() {
                let centerY = CGFloat(layer.count) * stepY / 2
                let x = baseX + CGFloat(colIndex) * stepX
                let y = baseY + CGFloat(rowIndex) * stepY - centerY + 200
                if let index = nodes.firstIndex(where: { $0.id == nodeID }) {
                    nodes[index].position = CGPoint(x: x, y: y)
                }
            }
        }

        hasUnsavedChanges = true
    }

    // MARK: - AI Workflow Generation

    func generateWorkflow(from userInput: String) {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isGenerating = true
        lastUserInput = userInput
        aiMessages.append("🤖 正在分析需求: \(userInput)")

        aiClient.generateWorkflow(
            userInput: userInput,
            trafficContext: trafficContext,
            targetAppName: targetAppName,
            targetAppBundleId: targetAppBundleId
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isGenerating = false

                switch result {
                case .success(let response):
                    self.parseAIWorkflowResponse(response)
                    self.aiMessages.append("✅ 工作流已生成 (\(self.nodes.count) 个节点)")

                case .failure(let error):
                    self.aiMessages.append("❌ 生成失败: \(error.localizedDescription)")
                    // Fallback: create a basic workflow
                    self.createFallbackWorkflow(from: userInput)
                }
            }
        }
    }

    // MARK: - Parse AI Response

    private func parseAIWorkflowResponse(_ response: String) {
        // Try to extract JSON from the response
        guard let jsonData = extractJSON(from: response),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let nodeDicts = parsed["nodes"] as? [[String: Any]] else {
            createFallbackWorkflow(from: lastUserInput)
            return
        }

        clearAll()

        var nodeIDMap: [String: UUID] = [:]
        var createdNodes: [(String, WorkflowNode)] = []

        for (index, dict) in nodeDicts.enumerated() {
            let templateId = dict["templateId"] as? String ?? dict["id"] as? String ?? ""
            let title = dict["title"] as? String ?? "未命名节点"
            let categoryStr = dict["category"] as? String ?? "appControl"
            let category = NodeCategory(rawValue: categoryStr) ?? .appControl
            let icon = dict["icon"] as? String ?? category.iconSystemName
            let note = dict["note"] as? String ?? dict["aiNote"] as? String ?? ""
            let riskStr = dict["riskLevel"] as? String ?? "none"
            let riskLevel = RiskLevel(rawValue: riskStr) ?? .none
            let params = dict["parameters"] as? [String: String] ?? [:]
            let nodeId = dict["nodeId"] as? String ?? "node_\(index)"

            // Try to find matching template
            let template = NodeRegistry.template(id: templateId)
            let node: WorkflowNode
            if let template = template {
                node = NodeRegistry.createNode(from: template, position: .zero)
                var mutableNode = node
                if !title.isEmpty { mutableNode.title = title }
                mutableNode.aiNote = note
                mutableNode.parameters.merge(params) { _, new in new }
                mutableNode.riskLevel = riskLevel
                node = mutableNode
            } else {
                let inputPorts = (dict["inputPorts"] as? [String] ?? ["输入"]).map { NodePort(label: $0, isInput: true) }
                let outputPorts = (dict["outputPorts"] as? [String] ?? ["输出"]).map { NodePort(label: $0, isInput: false) }
                node = WorkflowNode(
                    title: title, category: category, iconSystemName: icon,
                    aiNote: note, parameters: params, inputPorts: inputPorts,
                    outputPorts: outputPorts, riskLevel: riskLevel
                )
            }

            nodeIDMap[nodeId] = node.id
            createdNodes.append((nodeId, node))
        }

        // Auto-layout positions
        let baseX: CGFloat = 40
        let baseY: CGFloat = 120
        let stepX: CGFloat = WorkflowNode.width + 100
        let stepY: CGFloat = WorkflowNode.height + 30

        for (index, (nodeId, var node)) in createdNodes.enumerated() {
            let col = index
            node.position = CGPoint(x: baseX + CGFloat(col) * stepX, y: baseY)
            nodes.append(node)
        }

        // Parse connections
        if let connDicts = parsed["connections"] as? [[String: Any]] {
            for connDict in connDicts {
                let fromId = connDict["from"] as? String ?? connDict["fromNode"] as? String ?? ""
                let toId = connDict["to"] as? String ?? connDict["toNode"] as? String ?? ""
                let fromPort = connDict["fromPort"] as? Int ?? 0
                let toPort = connDict["toPort"] as? Int ?? 0

                if let fromUUID = nodeIDMap[fromId], let toUUID = nodeIDMap[toId] {
                    connections.append(NodeConnection(
                        fromNodeID: fromUUID, fromPortIndex: fromPort,
                        toNodeID: toUUID, toPortIndex: toPort
                    ))
                }
            }
        }

        // Apply auto-layout for better positioning
        autoLayoutAll()

        hasUnsavedChanges = true
    }

    private func extractJSON(from text: String) -> Data? {
        // Try direct parse
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        // Try to find JSON block in markdown code fence
        if let start = text.range(of: "```json"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            let jsonStr = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return jsonStr.data(using: .utf8)
        }

        // Try to find first { and last }
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}") {
            let jsonStr = String(text[firstBrace...lastBrace])
            return jsonStr.data(using: .utf8)
        }

        return nil
    }

    // MARK: - Fallback Workflow

    private func createFallbackWorkflow(from input: String) {
        clearAll()

        // Create a basic 3-node workflow
        let node1 = NodeRegistry.createNode(
            from: NodeRegistry.template(id: "file.readPhotos")!,
            position: CGPoint(x: 40, y: 120)
        )
        var node1Var = node1
        node1Var.aiNote = "AI自动生成: 读取相册竖屏视频"

        let node2 = NodeRegistry.createNode(
            from: NodeRegistry.template(id: "app.open")!,
            position: CGPoint(x: 300, y: 120)
        )
        var node2Var = node2
        node2Var.aiNote = "AI自动生成: 打开目标应用"

        let node3 = NodeRegistry.createNode(
            from: NodeRegistry.template(id: "file.writeNote")!,
            position: CGPoint(x: 560, y: 120)
        )
        var node3Var = node3
        node3Var.aiNote = "AI自动生成: 记录到备忘录"

        nodes = [node1Var, node2Var, node3Var]

        connections = [
            NodeConnection(fromNodeID: node1Var.id, toNodeID: node2Var.id),
            NodeConnection(fromNodeID: node2Var.id, toNodeID: node3Var.id)
        ]

        hasUnsavedChanges = true
    }

    // MARK: - Risk Management

    func checkRisk(for node: WorkflowNode) {
        if node.riskLevel.requiresConfirmation && !node.isRiskConfirmed {
            pendingRiskNode = node
            showRiskAlert = true
        }
    }

    func confirmRisk() {
        guard var node = pendingRiskNode else { return }
        node.isRiskConfirmed = true
        updateNode(node)
        pendingRiskNode = nil
        showRiskAlert = false
    }

    func dismissRisk() {
        pendingRiskNode = nil
        showRiskAlert = false
    }

    // MARK: - Save / Load

    func saveWorkflow() {
        let workflow = Workflow(
            id: workflowID,
            name: workflowName,
            description: lastUserInput,
            nodes: nodes,
            connections: connections,
            createdAt: Date(),
            updatedAt: Date(),
            userInput: lastUserInput
        )
        workflow.saveToDisk()
        hasUnsavedChanges = false
        aiMessages.append("💾 工作流已保存: \(workflowName)")
    }

    func loadWorkflow(_ workflow: Workflow) {
        workflowID = workflow.id
        workflowName = workflow.name
        nodes = workflow.nodes
        connections = workflow.connections
        lastUserInput = workflow.userInput
        hasUnsavedChanges = false
        resetCanvas()
    }

    // MARK: - Export

    func exportAsScript() -> String {
        var script = "// TrollReverseLab Workflow Script\n"
        script += "// Generated from: \(lastUserInput)\n"
        script += "// Nodes: \(nodes.count), Connections: \(connections.count)\n\n"

        if let order = Workflow(nodes: nodes, connections: connections).executionOrder() {
            script += "// Execution Order:\n"
            for (index, nodeID) in order.enumerated() {
                if let node = nodes.first(where: { $0.id == nodeID }) {
                    script += "// \(index + 1). [\(node.category.displayName)] \(node.title)\n"
                    script += "//    备注: \(node.aiNote)\n"
                    if !node.parameters.isEmpty {
                        script += "//    参数: \(node.parameters.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))\n"
                    }
                    script += "\n"
                }
            }
        } else {
            script += "// Warning: Workflow contains cycles, cannot determine execution order\n\n"
            for node in nodes {
                script += "// [\(node.category.displayName)] \(node.title) - \(node.aiNote)\n"
            }
        }

        return script
    }
}
