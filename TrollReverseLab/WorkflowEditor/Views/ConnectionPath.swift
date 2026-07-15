import SwiftUI

// MARK: - Connection Path View

struct ConnectionPath: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    let isSelected: Bool
    let isAnimated: Bool

    @State private var dashOffset: CGFloat = 0

    var body: some View {
        Path { path in
            path.move(to: from)

            // Calculate control points for smooth bezier curve
            let dx = to.x - from.x
            let dy = to.y - from.y
            let distance = sqrt(dx * dx + dy * dy)

            // Control point offset based on distance
            let offset = max(40, min(distance * 0.4, 120))

            let cp1 = CGPoint(x: from.x + offset, y: from.y)
            let cp2 = CGPoint(x: to.x - offset, y: to.y)

            path.addCurve(to: to, control1: cp1, control2: cp2)
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: isSelected ? 3 : 2,
                lineCap: .round,
                lineJoin: .round,
                dash: isAnimated ? [8, 4] : [],
                dashPhase: isAnimated ? dashOffset : 0
            )
        )
        .shadow(color: color.opacity(0.4), radius: 2, x: 0, y: 0)
        .onAppear {
            if isAnimated {
                withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: false)) {
                    dashOffset = 12
                }
            }
        }
        // Arrow at the destination
        .overlay(
            arrowAtDestination
        )
    }

    private var arrowAtDestination: some View {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let angle = atan2(dy, dx)
        let arrowLength: CGFloat = 8

        return Path { path in
            let tip = to
            let left = CGPoint(
                x: tip.x - arrowLength * cos(angle - 0.4),
                y: tip.y - arrowLength * sin(angle - 0.4)
            )
            let right = CGPoint(
                x: tip.x - arrowLength * cos(angle + 0.4),
                y: tip.y - arrowLength * sin(angle + 0.4)
            )
            path.move(to: left)
            path.addLine(to: tip)
            path.addLine(to: right)
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Temporary Connection (while dragging from a port)

struct TempConnection: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        Path { path in
            path.move(to: from)
            let cp1 = CGPoint(x: from.x + 60, y: from.y)
            let cp2 = CGPoint(x: to.x - 60, y: to.y)
            path.addCurve(to: to, control1: cp1, control2: cp2)
        }
        .stroke(
            Color.white.opacity(0.5),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])
        )
    }
}
