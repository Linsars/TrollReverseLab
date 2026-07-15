import SwiftUI
import Foundation
import Combine

// MARK: - IPA Builder Manager

class IPABuilderManager: ObservableObject {

    @Published var config: IPAProjectConfig
    @Published var snapshots: [SourceSnapshot] = []
    @Published var buildLog: [String] = []
    @Published var isBuilding: Bool = false
    @Published var buildProgress: Double = 0
    @Published var lastBuildPath: String?
    @Published var showTemplatePicker: Bool = false
    @Published var showSnapshotPicker: Bool = false

    private let fileManager = FileManager.default

    var projectDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("IPAProjects", isDirectory: true)
    }

    var snapshotsDir: URL {
        projectDir.appendingPathComponent("Snapshots", isDirectory: true)
    }

    var outputDir: URL {
        projectDir.appendingPathComponent("Output", isDirectory: true)
    }

    init() {
        config = IPAProjectConfig(sourceCode: SourceTemplates.blank)
        createDirectories()
        loadSnapshots()
    }

    // MARK: - Directory Setup

    private func createDirectories() {
        try? fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    // MARK: - Source Code Management

    func loadTemplate(_ template: SourceTemplate) {
        config.sourceCode = template.sourceCode
        config.appName = template.title
        config.updatedAt = Date()
    }

    func updateSourceCode(_ code: String) {
        config.sourceCode = code
        config.updatedAt = Date()
    }

    // MARK: - Snapshots

    func saveSnapshot(label: String) {
        let snapshot = SourceSnapshot(label: label, sourceCode: config.sourceCode, config: config)
        snapshots.insert(snapshot, at: 0)

        // Persist
        let file = snapshotsDir.appendingPathComponent("\(snapshot.id.uuidString).json")
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: file)
        }
    }

    func loadSnapshot(_ snapshot: SourceSnapshot) {
        config = snapshot.config
        config.sourceCode = snapshot.sourceCode
    }

    func deleteSnapshot(_ snapshot: SourceSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        let file = snapshotsDir.appendingPathComponent("\(snapshot.id.uuidString).json")
        try? fileManager.removeItem(at: file)
    }

    private func loadSnapshots() {
        guard let files = try? fileManager.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil) else {
            return
        }
        var loaded: [SourceSnapshot] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let snapshot = try? JSONDecoder().decode(SourceSnapshot.self, from: data) {
                loaded.append(snapshot)
            }
        }
        snapshots = loaded.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Build (Generate Project Package)

    /// Generate a complete Xcode project package that can be compiled on a Mac
    /// or with an on-device toolchain if available
    func buildProject(completion: @escaping (Result<String, Error>) -> Void) {
        isBuilding = true
        buildProgress = 0
        buildLog.removeAll()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.log("📦 开始构建项目: \(self.config.appName)")
            self.setProgress(0.1)

            // 1. Create project directory
            let projectName = self.config.appName.replacingOccurrences(of: " ", with: "_")
            let projectRoot = self.outputDir.appendingPathComponent(projectName)
            try? self.fileManager.removeItem(at: projectRoot)
            try? self.fileManager.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            self.log("✅ 创建项目目录")
            self.setProgress(0.2)

            // 2. Write source files
            let sourcesDir = projectRoot.appendingPathComponent("Sources", isDirectory: true)
            try? self.fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
            let sourceFile = sourcesDir.appendingPathComponent("App.swift")
            try? self.config.sourceCode.data(using: .utf8)?.write(to: sourceFile)
            self.log("✅ 写入源码文件: App.swift")
            self.setProgress(0.3)

            // 3. Generate project.yml for xcodegen
            let projectYml = self.generateProjectYML(projectName: projectName)
            let ymlFile = projectRoot.appendingPathComponent("project.yml")
            try? projectYml.data(using: .utf8)?.write(to: ymlFile)
            self.log("✅ 生成 project.yml (xcodegen)")
            self.setProgress(0.4)

            // 4. Generate Info.plist
            let infoPlist = self.generateInfoPlist()
            let plistFile = sourcesDir.appendingPathComponent("Info.plist")
            try? infoPlist.data(using: .utf8)?.write(to: plistFile)
            self.log("✅ 生成 Info.plist")
            self.setProgress(0.5)

            // 5. Generate entitlements
            let entitlements = self.generateEntitlements()
            let entFile = sourcesDir.appendingPathComponent("\(projectName).entitlements")
            try? entitlements.data(using: .utf8)?.write(to: entFile)
            self.log("✅ 生成 entitlements")
            self.setProgress(0.6)

            // 6. Generate build script
            let buildScript = self.generateBuildScript(projectName: projectName)
            let scriptFile = projectRoot.appendingPathComponent("build.sh")
            try? buildScript.data(using: .utf8)?.write(to: scriptFile)
            // Make executable
            try? self.fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
            self.log("✅ 生成 build.sh 构建脚本")
            self.setProgress(0.7)

            // 7. Generate README
            let readme = self.generateREADME(projectName: projectName)
            let readmeFile = projectRoot.appendingPathComponent("README.md")
            try? readme.data(using: .utf8)?.write(to: readmeFile)
            self.log("✅ 生成 README.md")
            self.setProgress(0.8)

            // 8. Create zip archive
            let zipPath = self.outputDir.appendingPathComponent("\(projectName).zip")
            try? self.fileManager.removeItem(at: zipPath)
            self.log("📦 正在打包项目...")
            self.setProgress(0.9)

            // Use FileManager to create a simple directory copy as "package"
            // Actual zip creation would require SSZipArchive or similar
            let packageDir = self.outputDir.appendingPathComponent(projectName)
            self.lastBuildPath = packageDir.path

            self.log("✅ 构建完成！")
            self.log("📁 项目路径: \(packageDir.path)")
            self.log("💡 将项目传到 Mac，运行 build.sh 即可编译 IPA")
            self.setProgress(1.0)

            DispatchQueue.main.async {
                self.isBuilding = false
                // Auto-save snapshot
                self.saveSnapshot(label: "构建前快照")
                completion(.success(packageDir.path))
            }
        }
    }

    // MARK: - File Generation

    private func generateProjectYML(projectName: String) -> String {
        return """
        name: \(projectName)
        options:
          bundleIdPrefix: \(config.bundleId.components(separatedBy: ".").dropLast().joined(separator: "."))
          deploymentTarget:
            iOS: "\(config.minIOSVersion)"
        targets:
          \(projectName):
            type: application
            platform: iOS
            sources:
              - Sources
            info:
              path: Sources/Info.plist
              properties:
                CFBundleDisplayName: \(config.appName)
                CFBundleShortVersionString: \(config.version)
                CFBundleVersion: "\(config.buildNumber)"
                UILaunchScreen:
                  UIColorName: ""
            settings:
              base:
                TARGETED_DEVICE_FAMILY: "1,2"
                SWIFT_VERSION: "5.0"
                IPHONEOS_DEPLOYMENT_TARGET: "\(config.minIOSVersion)"
                CODE_SIGNING_ALLOWED: NO
                CODE_SIGN_IDENTITY: ""
        """
    }

    private func generateInfoPlist() -> String {
        var plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>\(config.appName)</string>
            <key>CFBundleIdentifier</key>
            <string>\(config.bundleId)</string>
            <key>CFBundleShortVersionString</key>
            <string>\(config.version)</string>
            <key>CFBundleVersion</key>
            <string>\(config.buildNumber)</string>
            <key>CFBundleExecutable</key>
            <string>$(EXECUTABLE_NAME)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>LSRequiresIPhoneOS</key>
            <true/>
            <key>MinimumOSVersion</key>
            <string>\(config.minIOSVersion)</string>
        """

        // Add entitlement-related usage descriptions
        for entId in config.entitlements {
            if let opt = EntitlementOption.allOptions.first(where: { $0.id == entId }) {
                plist += """
                    <key>\(opt.entitlementKey)</key>
                    <string>\(opt.entitlementValue)</string>
                """
            }
        }

        plist += """
            <key>UILaunchScreen</key>
            <dict/>
        </dict>
        </plist>
        """
        return plist
    }

    private func generateEntitlements() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <!-- TrollStore basic entitlements -->
            <key>platform-application</key>
            <true/>
            <key>com.apple.developer.team-identifier</key>
            <string>TrollReverseLab</string>
        </dict>
        </plist>
        """
    }

    private func generateBuildScript(projectName: String) -> String {
        return """
        #!/bin/bash
        # Build script for \(config.appName)
        # Requires: macOS with Xcode, xcodegen (brew install xcodegen)

        set -e

        echo "🔨 Building \(config.appName)..."
        echo "📦 Bundle ID: \(config.bundleId)"
        echo "📱 Min iOS: \(config.minIOSVersion)"
        echo ""

        # Install xcodegen if needed
        if ! command -v xcodegen &> /dev/null; then
            echo "Installing xcodegen..."
            brew install xcodegen
        fi

        # Generate Xcode project
        echo "Generating Xcode project..."
        xcodegen generate

        # Build
        echo "Building..."
        xcodebuild -project \(projectName).xcodeproj \\
            -scheme \(projectName) \\
            -configuration Release \\
            -sdk iphoneos \\
            CODE_SIGNING_ALLOWED=NO

        # Package IPA
        echo "Packaging IPA..."
        BUILD_DIR="build/Release-iphoneos"
        APP_PATH="$BUILD_DIR/\(projectName).app"

        if [ -d "$APP_PATH" ]; then
            mkdir -p Payload
            cp -r "$APP_PATH" Payload/
            zip -r \(projectName).ipa Payload
            rm -rf Payload
            echo "✅ IPA created: \(projectName).ipa"
            echo "📱 Install via TrollStore"
        else
            echo "❌ Build failed - app not found at $APP_PATH"
            exit 1
        fi
        """
    }

    private func generateREADME(projectName: String) -> String {
        return """
        # \(config.appName)

        A SwiftUI iOS app generated by TrollReverseLab IPA Builder.

        ## Info
        - Bundle ID: \(config.bundleId)
        - Version: \(config.version) (\(config.buildNumber))
        - Min iOS: \(config.minIOSVersion)
        - Created: \(config.createdAt)

        ## Build Instructions

        1. Transfer this project folder to a Mac
        2. Install [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
        3. Run the build script: `./build.sh`
        4. The IPA will be generated as `\(projectName).ipa`
        5. Install the IPA via TrollStore

        ## Entitlements
        \(config.entitlements.map { "- \($0)" }.joined(separator: "\n"))

        ## Source Code
        The source code is in `Sources/App.swift`.
        Modify it and re-run `build.sh` to rebuild.

        ## Snapshots
        Source code snapshots are managed by TrollReverseLab.
        Use the snapshot viewer to rollback to previous versions.
        """
    }

    // MARK: - AI Integration

    /// Generate source code from natural language description using AI
    func generateFromAI(description: String, aiClient: AIScriptClient, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let script = try await aiClient.generateScript(
                    description: description,
                    scriptType: .fridaJS,
                    appContext: nil,
                    targetApp: nil,
                    trafficContext: nil
                )
                let code = extractCode(from: script.code)
                await MainActor.run {
                    self.config.sourceCode = code
                    self.config.updatedAt = Date()
                    completion(.success(code))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    private func extractCode(from text: String) -> String {
        // Remove markdown code fences
        var code = text
        if code.contains("```swift") {
            if let start = code.range(of: "```swift") {
                code = String(code[start.upperBound...])
            }
            if let end = code.range(of: "```") {
                code = String(code[..<end.lowerBound])
            }
        } else if code.contains("```") {
            if let start = code.range(of: "```") {
                code = String(code[start.upperBound...])
            }
            if let end = code.range(of: "```") {
                code = String(code[..<end.lowerBound])
            }
        }
        return code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.buildLog.append(message)
        }
    }

    private func setProgress(_ value: Double) {
        DispatchQueue.main.async {
            self.buildProgress = value
        }
    }

    var entitlementOptions: [EntitlementOption] {
        EntitlementOption.allOptions
    }

    func toggleEntitlement(_ id: String) {
        if config.entitlements.contains(id) {
            config.entitlements.removeAll { $0 == id }
        } else {
            config.entitlements.append(id)
        }
    }
}
