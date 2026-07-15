import SwiftUI
import UIKit

// MARK: - Node Card View

struct NodeCardView: View {
    let node: WorkflowNode
    let isSelected: Bool
    let isDragging: Bool
    let scale: CGFloat
    let onTap: () -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void
    let onDoubleClick: () -> Void
    let onPortTap: (Bool, Int) -> Void  // isInput, portIndex

    @State private var dragAccumulated: CGSize = .zero
    @State private var lastTapTime: Date = .distantPast

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Node body
            nodeBody

            // Input ports (left side)
            ForEach(Array(node.inputPorts.enumerated()), id: \.element.id) { index, port in
                portCircle(isInput: true, index: index, port: port)
            }

            // Output ports (right side)
            ForEach(Array(node.outputPorts.enumerated()), id: \.element.id) { index, port in
                portCircle(isInput: false, index: index, port: port)
            }
        }
        .position(
            x: node.position.x + WorkflowNode.width / 2,
            y: node.position.y + WorkflowNode.height / 2
        )
        .offset(isDragging ? dragAccumulated : .zero)
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastTapTime) < 0.3 {
                onDoubleClick()
            } else {
                onTap()
            }
            lastTapTime = now
        }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    dragAccumulated = value.translation
                    onDrag(value.translation)
                }
                .onEnded { _ in
                    // Apply accumulated drag to node position
                    let newX = node.position.x + dragAccumulated.width / scale
                    let newY = node.position.y + dragAccumulated.height / scale
                    nodeUpdated(position: CGPoint(x: newX, y: newY))
                    dragAccumulated = .zero
                    onDragEnd()
                }
        )
        .contextMenu {
            Button(action: { onDoubleClick() }) {
                Label("AI优化此节点", systemImage: "wand.and.stars")
            }
            Button(action: { /* duplicate */ }) {
                Label("复制节点", systemImage: "doc.on.doc")
            }
            Button(action: { /* toggle enabled */ }) {
                Label(node.isEnabled ? "禁用节点" : "启用节点",
                      systemImage: node.isEnabled ? "checkmark.circle" : "circle")
            }
            Divider()
            Button(action: { /* delete */ }) {
                Label("删除节点", systemImage: "trash")
                    .foregroundColor(.red)
            }
        }
    }

    private func nodeUpdated(position: CGPoint) {
        // This will be handled by the engine through onDragEnd
    }

    // MARK: - Node Body

    private var nodeBody: some View {
        VStack(spacing: 0) {
            // Header with icon and title
            HStack(spacing: 8) {
                Image(systemName: node.iconSystemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Text(node.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                // Risk badge
                if node.riskLevel.requiresConfirmation {
                    Image(systemName: node.isRiskConfirmed ? "checkmark.shield" : "exclamationmark.shield")
                        .font(.system(size: 12))
                        .foregroundColor(node.isRiskConfirmed ? .white : .yellow)
                }

                // Disabled indicator
                if !node.isEnabled {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // AI Note
            if !node.aiNote.isEmpty {
                Text(node.aiNote)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            // Category tag
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 5, height: 5)
                Text(node.category.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if node.aiOptimized {
                    Text("AI")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .frame(width: WorkflowNode.width, height: WorkflowNode.height)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: node.category.gradientColors.map { Color($0) }),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.white : Color.white.opacity(0.2),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.4 : 0.2),
                radius: isSelected ? 8 : 4, x: 0, y: 2)
        .opacity(node.isEnabled ? 1.0 : 0.5)
    }

    // MARK: - Port Circle

    private func portCircle(isInput: Bool, index: Int, port: NodePort) -> some View {
        let x: CGFloat = isInput ? -NodePort.portSpacing/2 : WorkflowNode.width - NodePort.portSpacing/2 + 12
        let y: CGFloat = 40 + CGFloat(index) * NodePort.portSpacing - 6

        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(node.category.swiftUIColor, lineWidth: 2))
            .frame(width: 12, height: 12)
            .position(x: x + 6, y: y + 6)
            .onTapGesture {
                onPortTap(isInput, index)
            }
    }
}
