import SwiftUI
import UIKit

// MARK: - Coordinate Picker Main View

struct CoordinatePickerView: View {

    @EnvironmentObject var manager: CoordinatePickerManager
    @EnvironmentObject var appScanner: AppScannerViewModel

    @State private var selectedGroupId: UUID?
    @State private var showActionPicker = false
    @State private var showExportSheet = false
    @State private var showImportSheet = false
    @State private var importText = ""
    @State private var showScreenshotViewer = false
    @State private var annotatedScreenshot: UIImage?
    @State private var showAppPicker = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if manager.groups.isEmpty {
                    emptyStateView
                } else {
                    groupListView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("坐标拾取")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(
                leading: EditButton(),
                trailing: HStack {
                    Button(action: { showImportSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Button(action: { showExportSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            )
            .sheet(isPresented: $showExportSheet) {
                ExportSheet(manager: manager)
            }
            .sheet(isPresented: $showImportSheet) {
                ImportSheet(manager: manager, importText: $importText)
            }
            .sheet(isPresented: $showAppPicker) {
                CoordAppPickerSheet(
                    apps: appScanner.apps,
                    onPick: { app in
                        showAppPicker = false
                        showActionPicker = true
                    }
                )
            }
            .sheet(isPresented: $showActionPicker) {
                ActionTypePicker(
                    onPick: { actionType in
                        showActionPicker = false
                        // Here we would activate the overlay
                        // For now, just set the manager state
                        manager.currentActionType = actionType
                    }
                )
            }
            // Overlay for picking mode
            .overlay(
                Group {
                    if manager.isPickMode {
                        CoordinateOverlayView(manager: manager)
                            .ignoresSafeArea()
                            .zIndex(1000)
                    }
                }
            )
            // Label input sheet (iOS 14 compatible, no .alert with TextField)
            .sheet(isPresented: $manager.showLabelInput) {
                CoordinateLabelInputSheet(manager: manager)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "scope")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("暂无坐标数据")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("选择一个应用开始拾取屏幕坐标")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showAppPicker = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("选择应用开始拾取")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.accentColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Group List

    private var groupListView: some View {
        List {
            ForEach(manager.groups) { group in
                NavigationLink(
                    destination: CoordinateGroupDetailView(group: group)
                ) {
                    GroupRowView(group: group)
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    manager.deleteGroup(manager.groups[offset])
                }
            }

            Section {
                Button(action: { showAppPicker = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("选择应用开始拾取")
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
}

// MARK: - Group Row

struct GroupRowView: View {
    let group: CoordinateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.appName)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(group.coordinateCount) 个点位")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(group.bundleId)
                .font(.caption)
                .foregroundColor(.secondary)

            // Action type summary
            HStack(spacing: 8) {
                ForEach(CoordinateActionType.allCases, id: \.self) { type in
                    let count = group.coordinates.filter { $0.actionType == type }.count
                    if count > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: type.iconName)
                                .font(.system(size: 9))
                            Text("\(count)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Color(type.color))
                    }
                }
            }

            Text("更新于 \(formattedDate(group.updatedAt))")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Group Detail View

struct CoordinateGroupDetailView: View {
    let group: CoordinateGroup
    @EnvironmentObject var manager: CoordinatePickerManager
    @State private var showAnnotatedScreenshot = false
    @State private var annotatedImage: UIImage?

    var currentGroup: CoordinateGroup {
        manager.groups.first { $0.id == group.id } ?? group
    }

    var body: some View {
        List {
            // Action bar
            Section {
                HStack {
                    Button(action: generateAnnotatedScreenshot) {
                        Label("生成标注截图", systemImage: "photo.on.rectangle")
                    }
                    .foregroundColor(.accentColor)

                    Spacer()

                    Button(action: exportGroup) {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .foregroundColor(.accentColor)
                }
            }

            // Coordinates list
            Section(header: Text("坐标点位 (\(currentGroup.coordinateCount))")) {
                if currentGroup.coordinates.isEmpty {
                    Text("暂无坐标，点击右上角开始拾取")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(Array(currentGroup.coordinates.enumerated()), id: \.element.id) { index, coord in
                        CoordinateRowView(index: index, coordinate: coord)
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            let coord = currentGroup.coordinates[offset]
                            manager.deleteCoordinate(coord, from: currentGroup)
                        }
                    }
                    .onMove { source, destination in
                        manager.moveCoordinate(from: source, to: destination, in: currentGroup)
                    }
                }
            }

            // AI Export preview
            if !currentGroup.coordinates.isEmpty {
                Section(header: Text("AI 上下文预览")) {
                    Text(currentGroup.aiExport)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle(group.appName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: EditButton())
        .sheet(isPresented: $showAnnotatedScreenshot) {
            if let image = annotatedImage {
                AnnotatedScreenshotView(image: image, appName: group.appName)
            }
        }
    }

    private func generateAnnotatedScreenshot() {
        // Take a screenshot of current screen
        guard let screenshot = manager.captureScreen() else { return }
        annotatedImage = manager.annotateScreenshot(screenshot, coordinates: currentGroup.coordinates)
        showAnnotatedScreenshot = true
    }

    private func exportGroup() {
        // Copy to clipboard
        UIPasteboard.general.string = manager.exportGroupAsText(currentGroup)
    }
}

// MARK: - Coordinate Row

struct CoordinateRowView: View {
    let index: Int
    let coordinate: ScreenCoordinate

    var body: some View {
        HStack(spacing: 12) {
            // Number badge
            ZStack {
                Circle()
                    .fill(Color(coordinate.actionType.color))
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: coordinate.actionType.iconName)
                        .font(.system(size: 10))
                        .foregroundColor(Color(coordinate.actionType.color))
                    Text(coordinate.label.isEmpty ? "未命名" : coordinate.label)
                        .font(.system(size: 14, weight: .medium))
                }

                HStack(spacing: 6) {
                    Text("(\(Int(coordinate.x)), \(Int(coordinate.y)))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    if coordinate.actionType == .swipe, let ex = coordinate.endX, let ey = coordinate.endY {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                        Text("(\(Int(ex)), \(Int(ey)))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if coordinate.actionType == .textInput, let text = coordinate.textContent {
                        Text("\"\(text)\"")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if coordinate.actionType == .waitLoad, let dur = coordinate.waitDuration {
                        Text("\(String(format: "%.1f", dur))s")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Text("±\(coordinate.tolerance)px")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Annotated Screenshot Viewer

struct AnnotatedScreenshotView: View {
    let image: UIImage
    let appName: String
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .background(Color.black)
            .navigationTitle("\(appName) - 标注截图")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("关闭") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Action Type Picker

struct ActionTypePicker: View {
    let onPick: (CoordinateActionType) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                ForEach(CoordinateActionType.allCases, id: \.self) { type in
                    Button(action: {
                        onPick(type)
                    }) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color(type.color))
                                    .frame(width: 36, height: 36)
                                Image(systemName: type.iconName)
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                            }
                            Text(type.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("选择动作类型")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - App Picker Sheet

struct CoordAppPickerSheet: View {
    let apps: [TrollStoreApp]
    let onPick: (TrollStoreApp) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                ForEach(apps) { app in
                    Button(action: {
                        onPick(app)
                    }) {
                        HStack {
                            Image(systemName: "app")
                                .frame(width: 40, height: 40)
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading) {
                                Text(app.displayName)
                                    .foregroundColor(.primary)
                                Text(app.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("选择应用")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Export Sheet

struct ExportSheet: View {
    @ObservedObject var manager: CoordinatePickerManager
    @Environment(\.presentationMode) var presentationMode
    @State private var copied = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("坐标数据导出")
                        .font(.headline)

                    Text(manager.exportAllAsText())
                        .font(.system(size: 12, design: .monospaced))
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))

                    if let json = manager.exportAsJSON() {
                        Text("JSON 格式:")
                            .font(.headline)
                        Text(json)
                            .font(.system(size: 10, design: .monospaced))
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                    }

                    Button(action: {
                        UIPasteboard.general.string = manager.exportAllAsText()
                        copied = true
                    }) {
                        Text(copied ? "已复制到剪贴板 ✓" : "复制为文本")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Capsule().fill(Color.accentColor))
                            .foregroundColor(.white)
                    }
                }
                .padding()
            }
            .navigationTitle("导出坐标")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Import Sheet

struct ImportSheet: View {
    @ObservedObject var manager: CoordinatePickerManager
    @Binding var importText: String
    @Environment(\.presentationMode) var presentationMode
    @State private var result: String?

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("粘贴 JSON 格式的坐标数据:")
                    .font(.headline)

                TextEditor(text: $importText)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))

                if let result = result {
                    Text(result)
                        .foregroundColor(result.contains("成功") ? .green : .red)
                        .font(.subheadline)
                }

                Button(action: {
                    if manager.importFromJSON(importText) {
                        result = "导入成功！"
                        importText = ""
                    } else {
                        result = "导入失败，请检查 JSON 格式"
                    }
                }) {
                    Text("导入")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundColor(.white)
                }
            }
            .padding()
            .navigationTitle("导入坐标")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Coordinate Label Input Sheet (iOS 14 compatible replacement for .alert with TextField)

struct CoordinateLabelInputSheet: View {
    @ObservedObject var manager: CoordinatePickerManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("坐标信息")) {
                    if let point = manager.pickedPoint {
                        HStack {
                            Text("坐标")
                            Spacer()
                            Text("(\(Int(point.x)), \(Int(point.y)))")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        if let end = manager.pickedEndPoint {
                            HStack {
                                Text("终点")
                                Spacer()
                                Text("(\(Int(end.x)), \(Int(end.y)))")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack {
                            Text("动作")
                            Spacer()
                            Text(manager.currentActionType.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("备注名称")) {
                    TextField("如: 搜索按钮", text: $manager.pendingLabel)
                }

                if manager.currentActionType == .textInput {
                    Section(header: Text("输入文本内容")) {
                        TextField("要输入的文本", text: $manager.pendingText)
                    }
                }

                if manager.currentActionType == .waitLoad {
                    Section(header: Text("等待时长 (秒)")) {
                        Slider(value: $manager.pendingWait, in: 0.5...30, step: 0.5) {
                            Text("等待时长")
                        }
                        Text(String(format: "%.1f 秒", manager.pendingWait))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("确认坐标")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") {
                    manager.resetPickStatePublic()
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("确认") {
                    manager.confirmPick(label: manager.pendingLabel)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(manager.pendingLabel.isEmpty)
            )
        }
    }
}
