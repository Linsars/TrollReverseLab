import SwiftUI
import UIKit

// MARK: - Workflow Node

struct WorkflowNode: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var category: NodeCategory
    var iconSystemName: String
    var aiNote: String           // AI自动备注 (例: 批量导入9:16视频素材)
    var position: CGPoint        // 画布坐标
    var parameters: [String: String]  // 节点参数
    var inputPorts: [NodePort]
    var outputPorts: [NodePort]
    var riskLevel: RiskLevel
    var isRiskConfirmed: Bool    // 高风险节点是否已确认
    var isEnabled: Bool          // 是否启用
    var aiOptimized: Bool        // AI是否已优化

    init(
        id: UUID = UUID(),
        title: String,
        category: NodeCategory,
        iconSystemName: String = "square.dashed",
        aiNote: String = "",
        position: CGPoint = .zero,
        parameters: [String: String] = [:],
        inputPorts: [NodePort] = [NodePort(label: "输入", isInput: true)],
        outputPorts: [NodePort] = [NodePort(label: "输出", isInput: false)],
        riskLevel: RiskLevel = .none,
        isRiskConfirmed: Bool = false,
        isEnabled: Bool = true,
        aiOptimized: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.iconSystemName = iconSystemName
        self.aiNote = aiNote
        self.position = position
        self.parameters = parameters
        self.inputPorts = inputPorts
        self.outputPorts = outputPorts
        self.riskLevel = riskLevel
        self.isRiskConfirmed = isRiskConfirmed
        self.isEnabled = isEnabled
        self.aiOptimized = aiOptimized
    }

    // Node dimensions
    static let width: CGFloat = 160
    static let height: CGFloat = 88
    static let portRadius: CGFloat = 6
    static let portSpacing: CGFloat = 24

    // Port positions in node-local coordinates (relative to node top-left)
    func inputPortPosition(at index: Int) -> CGPoint {
        let y = CGFloat(index) * NodePort.portSpacing + 40
        return CGPoint(x: 0, y: y)
    }

    func outputPortPosition(at index: Int) -> CGPoint {
        let y = CGFloat(index) * NodePort.portSpacing + 40
        return CGPoint(x: WorkflowNode.width, y: y)
    }

    // Port position in canvas coordinates
    func canvasInputPortPosition(at index: Int) -> CGPoint {
        CGPoint(x: position.x, y: position.y + 40 + CGFloat(index) * NodePort.portSpacing)
    }

    func canvasOutputPortPosition(at index: Int) -> CGPoint {
        CGPoint(x: position.x + WorkflowNode.width, y: position.y + 40 + CGFloat(index) * NodePort.portSpacing)
    }
}

extension NodePort {
    static let portSpacing: CGFloat = 24
}
