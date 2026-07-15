import SwiftUI
import UIKit
import Foundation
import Combine

// MARK: - Coordinate Picker Manager

class CoordinatePickerManager: ObservableObject {

    @Published var groups: [CoordinateGroup] = []
    @Published var isPickMode: Bool = false
    @Published var currentActionType: CoordinateActionType = .tap
    @Published var pickedPoint: CGPoint? = nil
    @Published var pickedEndPoint: CGPoint? = nil  // for swipe
    @Published var showLabelInput: Bool = false
    @Published var pendingLabel: String = ""
    @Published var pendingText: String = ""         // for textInput
    @Published var pendingWait: Double = 2.0        // for waitLoad
    @Published var currentBundleId: String = ""
    @Published var currentAppName: String = ""

    private var cancellables = Set<AnyCancellable>()
    private let fileManager = FileManager.default

    var saveDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Coordinates", isDirectory: true)
    }

    var screenshotDir: URL {
        saveDir.appendingPathComponent("Screenshots", isDirectory: true)
    }

    init() {
        createDirectories()
        loadGroups()
    }

    // MARK: - Directory Setup

    private func createDirectories() {
        try? fileManager.createDirectory(at: saveDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
    }

    // MARK: - Persistence

    func loadGroups() {
        let file = saveDir.appendingPathComponent("groups.json")
        guard fileManager.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file) else { return }
        if let decoded = try? JSONDecoder().decode([CoordinateGroup].self, from: data) {
            groups = decoded
        }
    }

    func saveGroups() {
        let file = saveDir.appendingPathComponent("groups.json")
        if let data = try? JSONEncoder().encode(groups) {
            try? data.write(to: file)
        }
    }

    // MARK: - Group Management

    func group(for bundleId: String) -> CoordinateGroup? {
        groups.first { $0.bundleId == bundleId }
    }

    func ensureGroup(appName: String, bundleId: String) -> CoordinateGroup {
        if let existing = group(for: bundleId) {
            return existing
        }
        var newGroup = CoordinateGroup(appName: appName, bundleId: bundleId)
        groups.append(newGroup)
        saveGroups()
        return newGroup
    }

    func deleteGroup(_ group: CoordinateGroup) {
        groups.removeAll { $0.id == group.id }
        saveGroups()
    }

    // MARK: - Coordinate Picking

    func startPicking(appName: String, bundleId: String, actionType: CoordinateActionType) {
        currentAppName = appName
        currentBundleId = bundleId
        currentActionType = actionType
        pickedPoint = nil
        pickedEndPoint = nil
        isPickMode = true
    }

    func stopPicking() {
        isPickMode = false
        pickedPoint = nil
        pickedEndPoint = nil
        showLabelInput = false
    }

    /// Called when user taps on the overlay to pick a coordinate
    func handlePick(at point: CGPoint) {
        if currentActionType == .swipe {
            if pickedPoint == nil {
                pickedPoint = point
            } else {
                pickedEndPoint = point
                showLabelInput = true
            }
        } else {
            pickedPoint = point
            showLabelInput = true
        }
    }

    /// Confirm the picked coordinate with label and save
    func confirmPick(label: String) {
        guard let point = pickedPoint else { return }

        let coord = ScreenCoordinate(
            x: point.x,
            y: point.y,
            actionType: currentActionType,
            label: label,
            endX: pickedEndPoint?.x,
            endY: pickedEndPoint?.y,
            textContent: currentActionType == .textInput ? pendingText : nil,
            waitDuration: currentActionType == .waitLoad ? pendingWait : nil
        )

        // Ensure group exists
        _ = ensureGroup(appName: currentAppName, bundleId: currentBundleId)

        // Find and update group
        if let idx = groups.firstIndex(where: { $0.bundleId == currentBundleId }) {
            groups[idx].coordinates.append(coord)
            groups[idx].updatedAt = Date()
        }

        saveGroups()
        resetPickState()
    }

    /// Public method to reset pick state (called from view)
    func resetPickStatePublic() {
        resetPickState()
    }

    private func resetPickState() {
        pickedPoint = nil
        pickedEndPoint = nil
        showLabelInput = false
        pendingLabel = ""
        pendingText = ""
        pendingWait = 2.0
    }

    // MARK: - Coordinate CRUD

    func deleteCoordinate(_ coordinate: ScreenCoordinate, from group: CoordinateGroup) {
        guard let gIdx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[gIdx].coordinates.removeAll { $0.id == coordinate.id }
        groups[gIdx].updatedAt = Date()
        saveGroups()
    }

    func updateCoordinate(_ coordinate: ScreenCoordinate, in group: CoordinateGroup) {
        guard let gIdx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        if let cIdx = groups[gIdx].coordinates.firstIndex(where: { $0.id == coordinate.id }) {
            groups[gIdx].coordinates[cIdx] = coordinate
            groups[gIdx].updatedAt = Date()
            saveGroups()
        }
    }

    func moveCoordinate(from source: IndexSet, to destination: Int, in group: CoordinateGroup) {
        guard let gIdx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[gIdx].coordinates.move(fromOffsets: source, toOffset: destination)
        groups[gIdx].updatedAt = Date()
        saveGroups()
    }

    // MARK: - Screenshot Annotation

    func saveScreenshot(_ image: UIImage, for group: CoordinateGroup) -> String? {
        let fileName = "screenshot_\(group.bundleId)_\(Int(Date().timeIntervalSince1970)).jpg"
        let fileURL = screenshotDir.appendingPathComponent(fileName)
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            return nil
        }
    }

    /// Take a screenshot of current screen
    func captureScreen() -> UIImage? {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return UIApplication.shared.windows.first?.screenCapture
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    /// Annotate screenshot with coordinate markers
    func annotateScreenshot(_ image: UIImage, coordinates: [ScreenCoordinate]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            // Draw original screenshot
            image.draw(in: CGRect(origin: .zero, size: image.size))

            // Draw markers for each coordinate
            for (index, coord) in coordinates.enumerated() {
                let point = CGPoint(x: coord.x, y: coord.y)
                let color = coord.actionType.color

                // Draw circle marker
                let radius: CGFloat = 20
                let rect = CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )

                // Outer circle
                color.setFill()
                UIBezierPath(ovalIn: rect).fill()

                // Inner white circle
                UIColor.white.setFill()
                UIBezierPath(ovalIn: rect.insetBy(dx: 5, dy: 5)).fill()

                // Number label
                let numText = "\(index + 1)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: color
                ]
                let textSize = (numText as NSString).size(withAttributes: attrs)
                let textRect = CGRect(
                    x: point.x - textSize.width / 2,
                    y: point.y - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                (numText as NSString).draw(in: textRect, withAttributes: attrs)

                // Label text below marker
                if !coord.label.isEmpty {
                    let labelText = coord.label
                    let labelAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 11),
                        .foregroundColor: UIColor.white,
                        .backgroundColor: color.withAlphaComponent(0.8)
                    ]
                    let labelSize = (labelText as NSString).size(withAttributes: labelAttrs)
                    let labelRect = CGRect(
                        x: point.x - labelSize.width / 2,
                        y: point.y + radius + 4,
                        width: labelSize.width,
                        height: labelSize.height
                    )
                    (labelText as NSString).draw(in: labelRect, withAttributes: labelAttrs)
                }

                // Draw swipe arrow
                if coord.actionType == .swipe, let endX = coord.endX, let endY = coord.endY {
                    let endPoint = CGPoint(x: endX, y: endY)
                    let path = UIBezierPath()
                    path.move(to: point)
                    path.addLine(to: endPoint)
                    color.setStroke()
                    path.lineWidth = 3
                    path.stroke()

                    // Arrow head
                    let angle = atan2(endPoint.y - point.y, endPoint.x - point.x)
                    let arrowLen: CGFloat = 12
                    let arrowAngle: CGFloat = .pi / 6
                    let p1 = CGPoint(
                        x: endPoint.x - arrowLen * cos(angle - arrowAngle),
                        y: endPoint.y - arrowLen * sin(angle - arrowAngle)
                    )
                    let p2 = CGPoint(
                        x: endPoint.x - arrowLen * cos(angle + arrowAngle),
                        y: endPoint.y - arrowLen * sin(angle + arrowAngle)
                    )
                    let arrowPath = UIBezierPath()
                    arrowPath.move(to: endPoint)
                    arrowPath.addLine(to: p1)
                    arrowPath.move(to: endPoint)
                    arrowPath.addLine(to: p2)
                    arrowPath.stroke()
                }
            }
        }
    }

    // MARK: - Export

    func exportAllAsText() -> String {
        if groups.isEmpty { return "暂无坐标数据" }
        return groups.map { $0.aiExport }.joined(separator: "\n\n---\n\n")
    }

    func exportGroupAsText(_ group: CoordinateGroup) -> String {
        group.aiExport
    }

    /// Export all coordinates as JSON for backup/import
    func exportAsJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(groups) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Import coordinates from JSON
    func importFromJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CoordinateGroup].self, from: data) else {
            return false
        }
        // Merge: replace groups with same bundleId
        for imported in decoded {
            if let idx = groups.firstIndex(where: { $0.bundleId == imported.bundleId }) {
                groups[idx] = imported
            } else {
                groups.append(imported)
            }
        }
        saveGroups()
        return true
    }

    // MARK: - AI Integration

    /// Generate coordinate context for AI prompt
    func aiContext(for bundleId: String? = nil) -> String {
        if let bid = bundleId, let group = group(for: bid) {
            return group.aiExport
        }
        return exportAllAsText()
    }
}

// MARK: - UIWindow Screen Capture Extension

extension UIScreen {
    var screenCapture: UIImage? {
        guard let window = UIApplication.shared.windows.first else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}
