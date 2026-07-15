import SwiftUI
import UIKit

// MARK: - Workflow Canvas View

struct WorkflowCanvasView: View {
    @ObservedObject var engine: WorkflowEngine

    @State private var canvasSize: CGSize = .zero
    @State private var tempConnectionEnd: CGPoint?
    @State private var showNodePalette: Bool = false
    @State private var paletteCategory: NodeCategory = .appControl

    // Node detail sheet
    @State private var editingNode: WorkflowNode?
    @State private var showNodeDetail: Bool = false

    // AI menu state
    @State private var aiMenuNode: WorkflowNode?
    @State private var showAIMenu: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                canvasBackground(in: geometry)

                // Canvas content (transformed)
                ZStack {
                    // Connections (behind nodes)
                    ForEach(engine.connections) { conn in
                        connectionView(conn)
                    }

                    // Temporary connection while dragging
                    if let from = tempConnectionStart, let to = tempConnectionEnd {
                        TempConnection(from: from, to: to)
                    }

                    // Nodes
                    ForEach(engine.nodes) { node in
                        NodeCardView(
                            node: node,
                            isSelected: engine.selectedNodeID == node.id,
                            isDragging: engine.draggingNodeID == node.id,
                            scale: engine.canvasScale,
                            onTap: {
                                engine.selectNode(node.id)
                                engine.checkRisk(for: node)
                            },
                            onDrag: { translation in
                                engine.draggingNodeID = node.id
                            },
                            onDragEnd: {
                                engine.draggingNodeID = nil
                            },
                            onDoubleClick: {
                                editingNode = node
                                showNodeDetail = true
                            },
                            onPortTap: { isInput, portIndex in
                                handlePortTap(node: node, isInput: isInput, portIndex: portIndex)
                            }
                        )
                    }
                }
                .scaleEffect(engine.canvasScale)
                .offset(engine.canvasOffset)

                // Top toolbar overlay
                toolbarOverlay(in: geometry)

                // Node palette (slide from top)
                if showNodePalette {
                    nodePaletteOverlay(in: geometry)
                }

                // AI generating overlay
                if engine.isGenerating {
                    generatingOverlay(in: geometry)
                }

                // Risk alert
                if engine.showRiskAlert, let riskNode = engine.pendingRiskNode {
                    riskAlertOverlay(riskNode)
                }
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.10))
            .clipped()
            .gesture(canvasPanGesture)
            .gesture(canvasZoomGesture)
            .onTapGesture {
                engine.selectNode(nil)
                tempConnectionEnd = nil
            }
            .onAppear {
                canvasSize = geometry.size
            }
        }
        .sheet(isPresented: $showNodeDetail) {
            if let node = editingNode {
                NodeDetailSheet(
                    node: Binding(
                        get: { node },
                        set: { newNode in
                            engine.updateNode(newNode)
                            editingNode = newNode
                        }
                    ),
                    onDelete: {
                        engine.removeNode(node.id)
                        showNodeDetail = false
                    },
                    onAIOptimize: {
                        // Trigger AI optimization for this node
                        editingNode?.aiOptimized = true
                        if var n = editingNode {
                            n.aiOptimized = true
                            engine.updateNode(n)
                            editingNode = n
                        }
                    }
                )
            }
        }
    }

    // MARK: - Temp Connection

    private var tempConnectionStart: CGPoint? {
        guard let nodeID = engine.connectingFromNodeID,
              let node = engine.nodes.first(where: { $0.id == nodeID }) else { return nil }
        return node.canvasOutputPortPosition(at: engine.connectingFromPortIndex)
    }

    // MARK: - Connection View

    private func connectionView(_ conn: NodeConnection) -> some View {
        let fromNode = engine.nodes.first { $0.id == conn.fromNodeID }
        let toNode = engine.nodes.first { $0.id == conn.toNodeID }

        guard let from = fromNode, let to = toNode else {
            return AnyView(EmptyView())
        }

        let startPoint = from.canvasOutputPortPosition(at: conn.fromPortIndex)
        let endPoint = to.canvasInputPortPosition(at: conn.toPortIndex)

        // Use source node's category color for the connection
        let connColor = from.category.swiftUIColor
        let isSelected = engine.selectedConnectionID == conn.id

        return AnyView(
            ConnectionPath(
                from: startPoint, to: endPoint,
                color: connColor, isSelected: isSelected,
                isAnimated: !from.isEnabled || !to.isEnabled
            )
            .onTapGesture {
                engine.selectedConnectionID = conn.id
            }
            .contextMenu {
                Button(action: {
                    engine.removeConnection(conn.id)
                }) {
                    Label("删除连线", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
        )
    }

    // MARK: - Port Tap Handler

    private func handlePortTap(node: WorkflowNode, isInput: Bool, portIndex: Int) {
        if !isInput {
            // Start connecting from output port
            engine.connectingFromNodeID = node.id
            engine.connectingFromPortIndex = portIndex
            tempConnectionEnd = node.canvasOutputPortPosition(at: portIndex)
        } else {
            // Tapped an input port — if we're connecting, complete the connection
            if let fromID = engine.connectingFromNodeID {
                engine.addConnection(
                    from: fromID, fromPort: engine.connectingFromPortIndex,
                    to: node.id, toPort: portIndex
                )
                engine.connectingFromNodeID = nil
                tempConnectionEnd = nil
            }
        }
    }

    // MARK: - Canvas Background

    private func canvasBackground(in geometry: GeometryProxy) -> some View {
        CanvasGridView()
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
    }

    // MARK: - Canvas Gestures

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if engine.connectingFromNodeID != nil {
                    // Update temp connection end point
                    tempConnectionEnd = canvasPoint(from: value.location)
                } else {
                    engine.canvasOffset = CGSize(
                        width: value.translation.width,
                        height: value.translation.height
                    )
                }
            }
            .onEnded { value in
                if engine.connectingFromNodeID == nil {
                    // Apply pan offset permanently by adjusting all node positions
                    let dx = value.translation.width / engine.canvasScale
                    let dy = value.translation.height / engine.canvasScale
                    for i in engine.nodes.indices {
                        engine.nodes[i].position.x += dx
                        engine.nodes[i].position.y += dy
                    }
                    engine.canvasOffset = .zero
                } else {
                    // Cancel connection
                    engine.connectingFromNodeID = nil
                    tempConnectionEnd = nil
                }
            }
    }

    private var canvasZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let delta = scale / (engine.canvasScale > 0 ? 1 : 1)
                let newScale = min(max(engine.canvasScale * delta, engine.minScale), engine.maxScale)
                engine.canvasScale = newScale
            }
    }

    private func canvasPoint(from screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - engine.canvasOffset.width) / engine.canvasScale,
            y: (screenPoint.y - engine.canvasOffset.height) / engine.canvasScale
        )
    }

    // MARK: - Toolbar Overlay

    private func toolbarOverlay(in geometry: GeometryProxy) -> some View {
        VStack {
            HStack {
                // Add node button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showNodePalette.toggle()
                    }
                }) {
                    Image(systemName: showNodePalette ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }

                Spacer()

                // Zoom controls
                HStack(spacing: 12) {
                    Button(action: { zoomOut() }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.3)))
                    }
                    Text("\(Int(engine.canvasScale * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Button(action: { zoomIn() }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.3)))
                    }
                    Button(action: { resetZoom() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.3)))
                    }
                }

                Spacer()

                // Layout button
                Button(action: {
                    engine.autoLayoutAll()
                }) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            engine.canvasScale = min(engine.canvasScale * 1.2, engine.maxScale)
        }
    }

    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            engine.canvasScale = max(engine.canvasScale / 1.2, engine.minScale)
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.3)) {
            engine.canvasScale = 1.0
            engine.canvasOffset = .zero
        }
    }

    // MARK: - Node Palette

    private func nodePaletteOverlay(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NodeCategory.allCases, id: \.self) { cat in
                        Button(action: { paletteCategory = cat }) {
                            HStack(spacing: 4) {
                                Image(systemName: cat.iconSystemName)
                                    .font(.system(size: 11))
                                Text(cat.displayName)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(paletteCategory == cat ? cat.swiftUIColor : Color.white.opacity(0.1))
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)

            // Templates
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(NodeRegistry.templates(in: paletteCategory)) { template in
                        Button(action: {
                            let _ = engine.addNode(from: template)
                            withAnimation { showNodePalette = false }
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: template.iconSystemName)
                                        .font(.system(size: 14))
                                    Text(template.title)
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                }
                                Text(template.description)
                                    .font(.system(size: 9))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            .foregroundColor(.white)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(paletteCategory.gradientColors.first.map { Color($0).opacity(0.3) }
                                          ?? Color.gray.opacity(0.3))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(paletteCategory.swiftUIColor.opacity(0.5), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
        )
        .padding(.horizontal, 12)
        .padding(.top, 50)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Generating Overlay

    private func generatingOverlay(in geometry: GeometryProxy) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .accentColor(.white)

                Text("AI 正在生成工作流...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                if !engine.lastUserInput.isEmpty {
                    Text(engine.lastUserInput)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // AI messages
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(engine.aiMessages.suffix(3), id: \.self) { msg in
                            Text(msg)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .frame(maxHeight: 80)
            }
            .padding(32)
        }
    }

    // MARK: - Risk Alert

    private func riskAlertOverlay(_ node: WorkflowNode) -> some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)

                Text("⚠️ 高风险操作警告")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.red)

                Text("\(node.title)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text("此节点涉及 \(node.riskLevel.label) 操作，可能对目标应用造成不可逆的修改。请确认你了解风险并仅在授权环境下操作。")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(node.aiNote)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 24)

                HStack(spacing: 16) {
                    Button(action: { engine.dismissRisk() }) {
                        Text("取消")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                    }

                    Button(action: { engine.confirmRisk() }) {
                        Text("确认风险并继续")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.red))
                    }
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.12, green: 0.08, blue: 0.08))
            )
            .padding(32)
        }
    }
}

// MARK: - Canvas Grid Background

struct CanvasGridView: View {
    private let gridSize: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height

                var x: CGFloat = 0
                while x <= width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                    x += gridSize
                }

                var y: CGFloat = 0
                while y <= height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                    y += gridSize
                }
            }
            .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }
}
