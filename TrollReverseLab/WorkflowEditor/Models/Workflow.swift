import Foundation

// MARK: - Workflow Model

struct Workflow: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var nodes: [WorkflowNode]
    var connections: [NodeConnection]
    var createdAt: Date
    var updatedAt: Date
    var userInput: String          // 原始用户自然语言输入
    var isExecuted: Bool

    init(
        id: UUID = UUID(),
        name: String = "新工作流",
        description: String = "",
        nodes: [WorkflowNode] = [],
        connections: [NodeConnection] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        userInput: String = "",
        isExecuted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.nodes = nodes
        self.connections = connections
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userInput = userInput
        self.isExecuted = isExecuted
    }

    var nodeCount: Int { nodes.count }
    var connectionCount: Int { connections.count }

    // Get connections for a specific node
    func outgoingConnections(for nodeID: UUID) -> [NodeConnection] {
        connections.filter { $0.fromNodeID == nodeID }
    }

    func incomingConnections(for nodeID: UUID) -> [NodeConnection] {
        connections.filter { $0.toNodeID == nodeID }
    }

    // Topological sort for execution order
    func executionOrder() -> [UUID]? {
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

        var queue: [UUID] = inDegree.filter { $0.value == 0 }.map { $0.key }
        var result: [UUID] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            result.append(current)
            for neighbor in adj[current] ?? [] {
                inDegree[neighbor]! -= 1
                if inDegree[neighbor]! == 0 {
                    queue.append(neighbor)
                }
            }
        }

        return result.count == nodes.count ? result : nil
    }

    // Get node by ID
    func node(with id: UUID) -> WorkflowNode? {
        nodes.first { $0.id == id }
    }
}

// MARK: - Workflow Persistence

extension Workflow {
    static let workflowsDirectory: String = {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        return docs + "/Workflows"
    }()

    static func saveDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: workflowsDirectory) {
            try? fm.createDirectory(atPath: workflowsDirectory, withIntermediateDirectories: true)
        }
    }

    func saveToDisk() {
        Self.saveDirectory()
        let path = "\(Self.workflowsDirectory)/\(id.uuidString).json"
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    static func loadAll() -> [Workflow] {
        saveDirectory()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: workflowsDirectory) else { return [] }
        return files.filter { $0.hasSuffix(".json") }.compactMap { file in
            let path = "\(workflowsDirectory)/\(file)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
            return try? JSONDecoder().decode(Workflow.self, from: data)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func delete(id: UUID) {
        let path = "\(workflowsDirectory)/\(id.uuidString).json"
        try? FileManager.default.removeItem(atPath: path)
    }
}
