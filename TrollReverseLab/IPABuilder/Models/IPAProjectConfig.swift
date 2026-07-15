import SwiftUI
import Foundation
import Combine

// MARK: - Project Configuration

struct IPAProjectConfig: Codable {
    var appName: String
    var bundleId: String
    var version: String
    var buildNumber: String
    var minIOSVersion: String
    var iconColor: String        // hex color for default icon
    var entitlements: [String]   // entitlement identifiers
    var sourceCode: String       // SwiftUI source code
    var createdAt: Date
    var updatedAt: Date

    init(
        appName: String = "MyTool",
        bundleId: String = "com.trollreverse.mytool",
        version: String = "1.0.0",
        buildNumber: String = "1",
        minIOSVersion: String = "14.0",
        iconColor: String = "#007AFF",
        entitlements: [String] = [],
        sourceCode: String = ""
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.version = version
        self.buildNumber = buildNumber
        self.minIOSVersion = minIOSVersion
        self.iconColor = iconColor
        self.entitlements = entitlements
        self.sourceCode = sourceCode
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Source Snapshot

struct SourceSnapshot: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let label: String
    let sourceCode: String
    let config: IPAProjectConfig

    init(label: String, sourceCode: String, config: IPAProjectConfig) {
        self.id = UUID()
        self.timestamp = Date()
        self.label = label
        self.sourceCode = sourceCode
        self.config = config
    }
}

// MARK: - Available Entitlements

struct EntitlementOption: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let entitlementKey: String
    let entitlementValue: String

    static let allOptions: [EntitlementOption] = [
        EntitlementOption(
            id: "photos", title: "相册读写",
            description: "读取和保存照片到相册",
            icon: "photo.on.rectangle",
            entitlementKey: "NSPhotoLibraryUsageDescription",
            entitlementValue: "需要访问相册来管理图片"
        ),
        EntitlementOption(
            id: "camera", title: "相机",
            description: "使用设备相机拍照",
            icon: "camera",
            entitlementKey: "NSCameraUsageDescription",
            entitlementValue: "需要使用相机拍照"
        ),
        EntitlementOption(
            id: "files", title: "本地文件访问",
            description: "读写本地文件系统",
            icon: "folder",
            entitlementKey: "NSDocumentsFolderUsageDescription",
            entitlementValue: "需要访问文件管理文件"
        ),
        EntitlementOption(
            id: "background", title: "后台运行",
            description: "应用在后台保持运行",
            icon: "moon.fill",
            entitlementKey: "UIBackgroundModes",
            entitlementValue: "background-processing"
        ),
        EntitlementOption(
            id: "location", title: "定位权限",
            description: "获取设备地理位置",
            icon: "location",
            entitlementKey: "NSLocationWhenInUseUsageDescription",
            entitlementValue: "需要获取位置信息"
        ),
        EntitlementOption(
            id: "network", title: "网络访问",
            description: "发起网络请求",
            icon: "network",
            entitlementKey: "NSAppTransportSecurity",
            entitlementValue: "NSAllowsArbitraryLoads"
        ),
        EntitlementOption(
            id: "notifications", title: "通知推送",
            description: "发送本地通知",
            icon: "bell",
            entitlementKey: "UIUserNotificationType",
            entitlementValue: "alert,sound,badge"
        ),
    ]
}

// MARK: - Source Code Templates

struct SourceTemplate: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let sourceCode: String

    static let templates: [SourceTemplate] = [
        SourceTemplate(
            id: "blank",
            title: "空白应用",
            description: "基础 SwiftUI 应用模板",
            icon: "app",
            sourceCode: SourceTemplates.blank
        ),
        SourceTemplate(
            id: "keyword_tool",
            title: "关键词查询工具",
            description: "输入行业词根，批量生成长尾关键词",
            icon: "magnifyingglass",
            sourceCode: SourceTemplates.keywordTool
        ),
        SourceTemplate(
            id: "asset_manager",
            title: "素材管理器",
            description: "分类管理本地图文素材，支持标签筛选",
            icon: "photo.on.rectangle",
            sourceCode: SourceTemplates.assetManager
        ),
        SourceTemplate(
            id: "stats_tool",
            title: "数据统计工具",
            description: "记录和可视化展示运营数据",
            icon: "chart.bar",
            sourceCode: SourceTemplates.statsTool
        ),
        SourceTemplate(
            id: "text_generator",
            title: "文案生成器",
            description: "基于模板批量生成文案内容",
            icon: "text.bubble",
            sourceCode: SourceTemplates.textGenerator
        ),
    ]
}

// MARK: - Source Templates Content

enum SourceTemplates {
    static let blank = """
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "app")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                Text("Hello, TrollStore!")
                    .font(.title)
            }
            .navigationTitle("我的工具")
        }
    }
}
"""

    static let keywordTool = """
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            KeywordToolView()
        }
    }
}

struct KeywordToolView: View {
    @State private var rootWord = ""
    @State private var keywords: [String] = []
    @State private var prefixes = ["如何", "怎么", "为什么", "最好的", "免费", "2024最新"]
    @State private var suffixes = ["教程", "技巧", "指南", "大全", "推荐", "对比"]

    var body: some View {
        NavigationView {
            VStack {
                TextField("输入行业词根", text: $rootWord)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                Button("生成关键词") {
                    generateKeywords()
                }
                .buttonStyle(DefaultButtonStyle())
                .padding()

                List(keywords, id: \\.self) { kw in
                    Text(kw)
                }
            }
            .navigationTitle("关键词工具")
        }
    }

    func generateKeywords() {
        keywords = []
        guard !rootWord.isEmpty else { return }
        for p in prefixes {
            keywords.append("\\(p)\\(rootWord)")
        }
        for s in suffixes {
            keywords.append("\\(rootWord)\\(s)")
        }
        for p in prefixes {
            for s in suffixes {
                keywords.append("\\(p)\\(rootWord)\\(s)")
            }
        }
    }
}
"""

    static let assetManager = """
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            AssetManagerView()
        }
    }
}

struct AssetItem: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let tags: [String]
}

struct AssetManagerView: View {
    @State private var assets: [AssetItem] = []
    @State private var filterTag = ""
    @State private var showingAdd = false

    var filteredAssets: [AssetItem] {
        if filterTag.isEmpty { return assets }
        return assets.filter { $0.tags.contains(filterTag) }
    }

    var body: some View {
        NavigationView {
            List(filteredAssets) { asset in
                VStack(alignment: .leading) {
                    Text(asset.name).font(.headline)
                    HStack {
                        Text(asset.type).font(.caption).foregroundColor(.secondary)
                        ForEach(asset.tags, id: \\.self) { tag in
                            Text(tag).font(.caption2).padding(2).background(Color.blue.opacity(0.2)).cornerRadius(4)
                        }
                    }
                }
            }
            .navigationTitle("素材管理")
            .navigationBarItems(trailing: Button("添加") { showingAdd = true })
            .sheet(isPresented: $showingAdd) {
                Text("添加素材")
            }
        }
    }
}
"""

    static let statsTool = """
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            StatsView()
        }
    }
}

struct StatsRecord: Identifiable {
    let id = UUID()
    let date: Date
    let category: String
    let count: Int
}

struct StatsView: View {
    @State private var records: [StatsRecord] = []

    var body: some View {
        NavigationView {
            VStack {
                if records.isEmpty {
                    Text("暂无数据").foregroundColor(.secondary)
                } else {
                    List(records) { record in
                        HStack {
                            Text(record.category)
                            Spacer()
                            Text("\\(record.count)")
                            Text(record.date, style: .date).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("数据统计")
        }
    }
}
"""

    static let textGenerator = """
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            TextGeneratorView()
        }
    }
}

struct TextGeneratorView: View {
    @State private var template = "【标题】\\n\\n正文内容...\\n\\n#标签1 #标签2"
    @State private var keywords = ""
    @State private var outputs: [String] = []

    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $template)
                    .frame(height: 120)
                    .border(Color.secondary)

                TextField("关键词 (逗号分隔)", text: $keywords)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                Button("批量生成") { generate() }
                    .buttonStyle(DefaultButtonStyle())
                    .padding()

                List(outputs, id: \\.self) { text in
                    Text(text).font(.caption)
                }
            }
            .navigationTitle("文案生成器")
        }
    }

    func generate() {
        let kwArray = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        outputs = kwArray.map { kw in
            template.replacingOccurrences(of: "【标题】", with: kw)
        }
    }
}
"""
}
