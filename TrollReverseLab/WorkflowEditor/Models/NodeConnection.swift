import Foundation

// MARK: - Node Connection

struct NodeConnection: Identifiable, Codable, Equatable {
    let id: UUID
    var fromNodeID: UUID
    var fromPortIndex: Int
    var toNodeID: UUID
    var toPortIndex: Int

    init(
        id: UUID = UUID(),
        fromNodeID: UUID,
        fromPortIndex: Int = 0,
        toNodeID: UUID,
        toPortIndex: Int = 0
    ) {
        self.id = id
        self.fromNodeID = fromNodeID
        self.fromPortIndex = fromPortIndex
        self.toNodeID = toNodeID
        self.toPortIndex = toPortIndex
    }

    // Check if this connection involves a specific node
    func involves(nodeID: UUID) -> Bool {
        fromNodeID == nodeID || toNodeID == nodeID
    }
}
