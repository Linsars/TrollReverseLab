import SwiftUI
import UIKit

// MARK: - Coordinate Overlay Window

/// Floating overlay for picking screen coordinates
/// Shown as a transparent full-screen overlay above all content
struct CoordinateOverlayView: View {

    @ObservedObject var manager: CoordinatePickerManager

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent background to indicate pick mode
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .gesture(
                        TapGesture()
                            .onEnded {
                                // Use location from UIKit gesture instead
                            }
                    )

                // Pick instruction banner
                VStack {
                    pickInstructionView
                    Spacer()
                }

                // Picked point markers
                if let point = manager.pickedPoint {
                    PickedPointMarker(point: point, color: manager.currentActionType.color)
                        .position(point)
                }

                if let end = manager.pickedEndPoint, let start = manager.pickedPoint {
                    SwipeArrowPath(start: start, end: end, color: manager.currentActionType.color)
                }

                // Bottom toolbar
                VStack {
                    Spacer()
                    bottomToolbar
                }
            }
            .background(
                // Transparent tap catcher
                TapCatcherView { location in
                    manager.handlePick(at: location)
                }
                .ignoresSafeArea()
            )
        }
    }

    // MARK: - Instruction Banner

    private var pickInstructionView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: manager.currentActionType.iconName)
                    .foregroundColor(.white)
                Text(pickInstructionText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(Color.black.opacity(0.85))
            )
            .padding(.top, 60)
        }
    }

    private var pickInstructionText: String {
        switch manager.currentActionType {
        case .tap:
            return manager.pickedPoint == nil ? "点击屏幕拾取单击坐标" : "已拾取，输入备注确认"
        case .longPress:
            return manager.pickedPoint == nil ? "点击屏幕拾取长按坐标" : "已拾取，输入备注确认"
        case .swipe:
            if manager.pickedPoint == nil {
                return "点击屏幕拾取滑动起点"
            } else if manager.pickedEndPoint == nil {
                return "点击屏幕拾取滑动终点"
            } else {
                return "已拾取，输入备注确认"
            }
        case .textInput:
            return manager.pickedPoint == nil ? "点击屏幕拾取输入框坐标" : "已拾取，输入备注确认"
        case .waitLoad:
            return manager.pickedPoint == nil ? "点击屏幕拾取等待区域坐标" : "已拾取，输入备注确认"
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 16) {
            // Action type selector
            ForEach(CoordinateActionType.allCases, id: \.self) { type in
                Button(action: {
                    manager.currentActionType = type
                    manager.pickedPoint = nil
                    manager.pickedEndPoint = nil
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: type.iconName)
                            .font(.system(size: 18))
                        Text(type.displayName)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(manager.currentActionType == type ? .white : .white.opacity(0.5))
                    .frame(width: 56, height: 56)
                    .background(
                        Circle().fill(
                            manager.currentActionType == type
                            ? Color(type.color)
                            : Color.white.opacity(0.15)
                        )
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.85))
        )
        .padding(.bottom, 100)
    }
}

// MARK: - Picked Point Marker

struct PickedPointMarker: View {
    let point: CGPoint
    let color: UIColor

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(color))
                .frame(width: 40, height: 40)
                .opacity(0.3)

            Circle()
                .stroke(Color(color), lineWidth: 3)
                .frame(width: 40, height: 40)

            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)

            // Crosshair lines
            Rectangle()
                .fill(Color(color).opacity(0.5))
                .frame(width: 1, height: 30)
            Rectangle()
                .fill(Color(color).opacity(0.5))
                .frame(width: 30, height: 1)
        }
    }
}

// MARK: - Swipe Arrow

struct SwipeArrowPath: View {
    let start: CGPoint
    let end: CGPoint
    let color: UIColor

    var body: some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)

            // Arrow head
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLen: CGFloat = 15
            let arrowAngle: CGFloat = .pi / 6

            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - arrowLen * cos(angle - arrowAngle),
                y: end.y - arrowLen * sin(angle - arrowAngle)
            ))
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - arrowLen * cos(angle + arrowAngle),
                y: end.y - arrowLen * sin(angle + arrowAngle)
            ))
        }
        .stroke(Color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

// MARK: - UIKit Tap Gesture Bridge

/// Transparent view that captures tap locations using UIKit gesture recognizer
struct TapCatcherView: UIViewRepresentable {
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> TapCatcherUIView {
        let view = TapCatcherUIView()
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: TapCatcherUIView, context: Context) {
        uiView.onTap = onTap
    }
}

class TapCatcherUIView: UIView {
    var onTap: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        // Add haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        onTap?(point)
    }
}
