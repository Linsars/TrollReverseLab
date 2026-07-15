import SwiftUI
import UIKit

// MARK: - Image Picker (iOS 14 compatible)

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Material Editor View

struct MaterialEditorView: View {
    @EnvironmentObject var manager: MaterialEditorManager
    @EnvironmentObject var aiClient: AIScriptClient

    var body: some View {
        NavigationView {
            List {
                // Stats section
                Section(header: Text("素材概览")) {
                    HStack {
                        StatBadge(title: "草稿", count: manager.draftCount, color: .gray)
                        StatBadge(title: "润色中", count: manager.refiningCount, color: .orange)
                        StatBadge(title: "待发布", count: manager.readyCount, color: .blue)
                        StatBadge(title: "已发布", count: manager.publishedCount, color: .green)
                    }
                }

                // Projects list
                Section(header: Text("我的素材")) {
                    if manager.projects.isEmpty {
                        Text("暂无素材项目，点击右上角创建")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    ForEach(manager.projects) { project in
                        NavigationLink(destination: MaterialDetailView(project: project)) {
                            MaterialRowView(project: project)
                        }
                    }
                    .onDelete(perform: deleteProject)
                }

                // Platform templates info
                Section(header: Text("平台格式模板")) {
                    ForEach(PlatformTemplate.allTemplates) { template in
                        HStack {
                            Image(systemName: template.iconName)
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(template.name)
                                    .font(.subheadline)
                                Text("\(template.recommendedImageSize) | \(template.maxTextLength)字")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("素材编辑器")
            .navigationBarItems(trailing: Button(action: showCreateSheet) {
                Image(systemName: "plus")
            })
            .sheet(isPresented: $createSheetShown) {
                CreateProjectSheet(isPresented: $createSheetShown)
            }
        }
    }

    @State private var createSheetShown = false

    private func showCreateSheet() {
        createSheetShown = true
    }

    private func deleteProject(at offsets: IndexSet) {
        for index in offsets {
            manager.deleteProject(manager.projects[index])
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Material Row

struct MaterialRowView: View {
    let project: MaterialProject

    var body: some View {
        HStack {
            // Image thumbnail
            if let imageName = project.imageFileName,
               let image = MaterialEditorManager.loadImageStatic(fileName: imageName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: project.platform?.iconName ?? "doc.text")
                    .foregroundColor(.accentColor)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title.isEmpty ? "未命名" : project.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Image(systemName: project.status.iconName)
                        .font(.caption2)
                    Text(project.status.displayName)
                        .font(.caption2)
                    Text("\(project.characterCount)字")
                        .font(.caption2)
                        .foregroundColor(project.isOverLimit ? .red : .secondary)
                }
                .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Create Project Sheet

struct CreateProjectSheet: View {
    @EnvironmentObject var manager: MaterialEditorManager
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var selectedPlatformId = "general_square"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("素材标题")) {
                    TextField("输入素材标题", text: $title)
                }
                Section(header: Text("选择平台格式")) {
                    ForEach(PlatformTemplate.allTemplates) { template in
                        Button {
                            selectedPlatformId = template.id
                        } label: {
                            HStack {
                                Image(systemName: template.iconName)
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(template.name)
                                    Text(template.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedPlatformId == template.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle("新建素材")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { isPresented = false },
                trailing: Button("创建") {
                    let project = manager.createProject(title: title, platformId: selectedPlatformId)
                    isPresented = false
                    manager.selectProject(project)
                }
                .disabled(title.isEmpty)
            )
        }
    }
}

// MARK: - Material Detail View

struct MaterialDetailView: View {
    @EnvironmentObject var manager: MaterialEditorManager
    @EnvironmentObject var aiClient: AIScriptClient
    @State var project: MaterialProject
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage? = nil
    @State private var showRefineSheet = false
    @State private var showExportSheet = false
    @State private var exportText = ""
    @State private var showExportPreview = false
    @State private var tagInput = ""

    var body: some View {
        Form {
            // Title section
            Section(header: Text("标题")) {
                TextField("素材标题", text: $project.title, onCommit: {
                    manager.updateProject(project)
                })
            }

            // Platform section
            Section(header: Text("平台格式")) {
                if let platform = project.platform {
                    HStack {
                        Image(systemName: platform.iconName)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text(platform.name)
                            Text(platform.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("推荐尺寸")
                        Spacer()
                        Text(platform.recommendedImageSize)
                            .foregroundColor(.secondary)
                            .font(.system(.caption, design: .monospaced))
                    }
                    HStack {
                        Text("字数限制")
                        Spacer()
                        Text("\(project.characterCount) / \(platform.maxTextLength)")
                            .foregroundColor(project.isOverLimit ? .red : .secondary)
                            .font(.caption)
                    }
                }
            }

            // Content editor
            Section(header: Text("文案内容"), footer: Text("仅用于个人原创内容编辑，手动发布")) {
                TextEditor(text: $project.content)
                    .frame(minHeight: 200)
                    .onChange(of: project.content) { _ in
                        manager.updateProject(project)
                    }
            }

            // AI refinement
            Section(header: Text("AI 文案处理"), footer: Text("基于原创文案进行润色、精简、扩写等处理")) {
                Button {
                    showRefineSheet = true
                } label: {
                    Label("AI 文案处理", systemImage: "wand.and.stars")
                }
                .disabled(project.content.isEmpty || manager.isRefining)

                if manager.isRefining {
                    HStack {
                        ProgressView()
                        Text("正在处理...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Image section
            Section(header: Text("配图")) {
                if let imageName = project.imageFileName,
                   let image = manager.loadImage(fileName: imageName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)

                    Button("更换图片") { showImagePicker = true }
                    Button("裁切到平台比例") {
                        cropImageToPlatform(image: image)
                    }
                    Button("删除图片") {
                        var updated = project
                        if let name = updated.imageFileName {
                            let path = manager.imageDir.appendingPathComponent(name)
                            try? FileManager.default.removeItem(at: path)
                        }
                        updated.imageFileName = nil
                        project = updated
                        manager.updateProject(updated)
                    }
                    .foregroundColor(.red)
                } else {
                    Button {
                        showImagePicker = true
                    } label: {
                        Label("添加配图", systemImage: "photo.badge.plus")
                    }
                }
            }

            // Tags
            Section(header: Text("标签")) {
                ForEach(project.tags.indices, id: \.self) { index in
                    Text("#\(project.tags[index])")
                }
                HStack {
                    TextField("添加标签", text: $tagInput)
                    Button("添加") {
                        if !tagInput.isEmpty {
                            project.tags.append(tagInput)
                            tagInput = ""
                            manager.updateProject(project)
                        }
                    }
                }
            }

            // Status
            Section(header: Text("状态")) {
                Picker("状态", selection: $project.status) {
                    ForEach(MaterialStatus.allCases, id: \.self) { status in
                        Label(status.displayName, systemImage: status.iconName).tag(status)
                    }
                }
                .onChange(of: project.status) { _ in
                    manager.updateProject(project)
                }
            }

            // Export
            Section(header: Text("导出")) {
                Button {
                    exportText = manager.exportAsText(project)
                    showExportPreview = true
                } label: {
                    Label("导出为文本", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle(project.title.isEmpty ? "编辑素材" : project.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: Binding(
                get: { selectedImage },
                set: { newImage in
                    selectedImage = newImage
                    if let image = newImage {
                        if let name = manager.saveImage(image, forProjectId: project.id) {
                            var updated = project
                            updated.imageFileName = name
                            project = updated
                            manager.updateProject(updated)
                        }
                    }
                }
            ))
        }
        .sheet(isPresented: $showRefineSheet) {
            RefineSheet(project: project, isPresented: $showRefineSheet)
        }
        .sheet(isPresented: $showExportPreview) {
            ExportPreviewView(text: exportText, isPresented: $showExportPreview)
        }
    }

    private func cropImageToPlatform(image: UIImage) {
        guard let ratio = project.platform?.aspectRatio else { return }
        let cropped = manager.cropImage(image, aspectRatio: ratio)
        if let name = manager.saveImage(cropped, forProjectId: project.id) {
            var updated = project
            updated.imageFileName = name
            project = updated
            manager.updateProject(updated)
        }
    }
}

// MARK: - Refine Sheet

struct RefineSheet: View {
    @EnvironmentObject var manager: MaterialEditorManager
    @EnvironmentObject var aiClient: AIScriptClient
    let project: MaterialProject
    @Binding var isPresented: Bool
    @State private var selectedStyle: RefinementStyle = .polish
    @State private var resultText = ""
    @State private var hasResult = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("处理方式")) {
                    ForEach(RefinementStyle.allCases, id: \.self) { style in
                        Button {
                            selectedStyle = style
                        } label: {
                            HStack {
                                Image(systemName: style.iconName)
                                    .foregroundColor(.accentColor)
                                Text(style.displayName)
                                Spacer()
                                if selectedStyle == style {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Section(header: Text("原始文案")) {
                    Text(project.content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if hasResult {
                    Section(header: Text("处理结果")) {
                        Text(resultText)
                            .font(.body)
                    }

                    Button("替换文案") {
                        var updated = project
                        updated.content = resultText
                        updated.status = .refining
                        manager.updateProject(updated)
                        isPresented = false
                    }
                }

                if manager.isRefining {
                    Section {
                        HStack {
                            ProgressView()
                            Text("AI 正在处理...")
                        }
                    }
                }
            }
            .navigationTitle("AI 文案处理")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { isPresented = false },
                trailing: Button("处理") {
                    manager.refineText(project: project, style: selectedStyle, aiClient: aiClient) { result in
                        switch result {
                        case .success(let text):
                            resultText = text
                            hasResult = true
                        case .failure(let error):
                            resultText = "处理失败: \(error.localizedDescription)"
                            hasResult = true
                        }
                    }
                }
                .disabled(manager.isRefining || project.content.isEmpty)
            )
        }
    }
}

// MARK: - Export Preview

struct ExportPreviewView: View {
    let text: String
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            .navigationTitle("导出预览")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") { isPresented = false })
        }
    }
}
