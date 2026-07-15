import SwiftUI
import UIKit
import Foundation
import Combine

// MARK: - Material Editor Manager

class MaterialEditorManager: ObservableObject {

    @Published var projects: [MaterialProject] = []
    @Published var currentProject: MaterialProject?
    @Published var isRefining: Bool = false
    @Published var refineError: String?
    @Published var showImagePicker: Bool = false
    @Published var showPlatformPicker: Bool = false

    private let fileManager = FileManager.default

    var saveDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Materials", isDirectory: true)
    }

    var imageDir: URL {
        saveDir.appendingPathComponent("Images", isDirectory: true)
    }

    init() {
        createDirectories()
        loadProjects()
    }

    // MARK: - Directory Setup

    private func createDirectories() {
        try? fileManager.createDirectory(at: saveDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imageDir, withIntermediateDirectories: true)
    }

    // MARK: - Persistence

    private func loadProjects() {
        let file = saveDir.appendingPathComponent("projects.json")
        guard fileManager.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file) else { return }
        if let decoded = try? JSONDecoder().decode([MaterialProject].self, from: data) {
            projects = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func saveProjects() {
        let file = saveDir.appendingPathComponent("projects.json")
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: file)
        }
    }

    // MARK: - Project CRUD

    func createProject(title: String, platformId: String) -> MaterialProject {
        let project = MaterialProject(title: title, platformId: platformId)
        projects.insert(project, at: 0)
        saveProjects()
        return project
    }

    func updateProject(_ project: MaterialProject) {
        var updated = project
        updated.updatedAt = Date()
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = updated
        }
        saveProjects()
    }

    func deleteProject(_ project: MaterialProject) {
        projects.removeAll { $0.id == project.id }
        // Delete associated image
        if let imageName = project.imageFileName {
            let imagePath = imageDir.appendingPathComponent(imageName)
            try? fileManager.removeItem(at: imagePath)
        }
        saveProjects()
    }

    func selectProject(_ project: MaterialProject) {
        currentProject = project
    }

    // MARK: - Image Management

    func saveImage(_ image: UIImage, forProjectId projectId: UUID) -> String? {
        let fileName = "material_\(projectId.uuidString)_\(Int(Date().timeIntervalSince1970)).jpg"
        let fileURL = imageDir.appendingPathComponent(fileName)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try data.write(to: fileURL)
            return fileName
        } catch {
            return nil
        }
    }

    func loadImage(fileName: String) -> UIImage? {
        let fileURL = imageDir.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: fileURL.path)
    }

    /// Static image loader for use in row views without creating a manager instance
    static func loadImageStatic(fileName: String) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageDir = docs.appendingPathComponent("Materials/Images", isDirectory: true)
        let fileURL = imageDir.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: fileURL.path)
    }

    /// Crop image to match platform aspect ratio
    func cropImage(_ image: UIImage, aspectRatio: CGFloat) -> UIImage {
        let imageSize = image.size
        let imageAspect = imageSize.width / imageSize.height

        var cropRect: CGRect
        if imageAspect > aspectRatio {
            // Image is wider, crop sides
            let newWidth = imageSize.height * aspectRatio
            let x = (imageSize.width - newWidth) / 2
            cropRect = CGRect(x: x, y: 0, width: newWidth, height: imageSize.height)
        } else {
            // Image is taller, crop top/bottom
            let newHeight = imageSize.width / aspectRatio
            let y = (imageSize.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: y, width: imageSize.width, height: newHeight)
        }

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Resize image to fit within max dimension while preserving aspect ratio
    func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        if scale >= 1.0 { return image }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - AI Text Refinement

    func refineText(
        project: MaterialProject,
        style: RefinementStyle,
        aiClient: AIScriptClient,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard !aiClient.config.apiKey.isEmpty else {
            completion(.failure(AIScriptError.missingAPIKey))
            return
        }

        isRefining = true
        refineError = nil

        let platformName = project.platform?.name ?? "通用"
        let systemPrompt = """
        你是一个原创内容文案助手。用户会提供原创文案，你需要根据指定风格进行处理。
        平台格式: \(platformName)
        重要约束:
        1. 仅处理用户提供的原创文案，不生成搬运内容
        2. 保持原文核心意思不变
        3. 输出纯文本，不要包含代码块标记
        4. 适合手动发布使用
        """

        let userPrompt = """
        \(style.promptInstruction)

        原始文案:
        \(project.content)

        平台: \(platformName)
        字数限制: \(project.platform?.maxTextLength ?? 500) 字
        """

        let messages: [ChatMessage] = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userPrompt)
        ]

        Task {
            do {
                let response = try await aiClient.processText(messages: messages)
                let refinedText = response.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    self.isRefining = false
                    completion(.success(refinedText))
                }
            } catch {
                await MainActor.run {
                    self.isRefining = false
                    self.refineError = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Export

    func exportAsText(_ project: MaterialProject) -> String {
        var output = ""
        output += "标题: \(project.title)\n"
        output += "平台: \(project.platform?.name ?? "通用")\n"
        output += "标签: \(project.tags.joined(separator: " "))\n"
        output += "状态: \(project.status.displayName)\n"
        output += "---\n"
        output += project.content
        if !project.tags.isEmpty {
            output += "\n\n\(project.tags.map { "#\($0)" }.joined(separator: " "))"
        }
        return output
    }

    func exportAllAsJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(projects) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Statistics

    var draftCount: Int { projects.filter { $0.status == .draft }.count }
    var readyCount: Int { projects.filter { $0.status == .ready }.count }
    var publishedCount: Int { projects.filter { $0.status == .published }.count }
    var refiningCount: Int { projects.filter { $0.status == .refining }.count }
}
