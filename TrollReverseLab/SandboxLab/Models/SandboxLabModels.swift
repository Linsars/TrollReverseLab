import Foundation

// MARK: - Sandbox Path Category

/// Categories of iOS sandbox paths for educational demonstration.
enum SandboxPathCategory: String, CaseIterable, Codable {
    case system = "system"
    case bundle = "bundle"
    case data = "data"
    case documents = "documents"
    case library = "library"
    case caches = "caches"
    case tmp = "tmp"
    case group = "group"
    case keychain = "keychain"

    var displayName: String {
        switch self {
        case .system: return "系统路径"
        case .bundle: return "应用包目录"
        case .data: return "数据容器"
        case .documents: return "Documents"
        case .library: return "Library"
        case .caches: return "Caches"
        case .tmp: return "临时目录"
        case .group: return "App Group"
        case .keychain: return "Keychain"
        }
    }

    var iconName: String {
        switch self {
        case .system: return "internaldrive"
        case .bundle: return "shippingbox"
        case .data: return "folder.fill"
        case .documents: return "doc.fill"
        case .library: return "books.vertical.fill"
        case .caches: return "tray.fill"
        case .tmp: return "clock.arrow.circlepath"
        case .group: return "person.3.fill"
        case .keychain: return "lock.fill"
        }
    }
}

// MARK: - Sandbox Path Info

/// Information about a sandbox path's accessibility.
/// Used for educational demonstration of iOS sandbox boundaries.
struct SandboxPathInfo: Identifiable {
    let id: String
    let path: String
    let category: SandboxPathCategory
    let isAccessible: Bool
    let itemCount: Int
    let error: String?
    let educationalNote: String

    init(path: String, category: SandboxPathCategory, educationalNote: String) {
        self.id = path
        self.path = path
        self.category = category
        self.educationalNote = educationalNote

        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            self.isAccessible = true
            if let items = try? fm.contentsOfDirectory(atPath: path) {
                self.itemCount = items.count
            } else {
                self.itemCount = 0
            }
            self.error = nil
        } else {
            self.isAccessible = false
            self.itemCount = 0
            self.error = "路径不可访问 (沙盒限制)"
        }
    }
}

// MARK: - Container Info

/// Information about an app's container structure.
struct ContainerInfo: Identifiable {
    let id: String
    let bundleId: String
    let displayName: String
    let bundlePath: String
    let dataContainerPath: String
    let containerType: String
    let isAccessible: Bool

    init(bundleId: String, displayName: String, bundlePath: String, dataContainerPath: String, containerType: String) {
        self.id = bundleId
        self.bundleId = bundleId
        self.displayName = displayName
        self.bundlePath = bundlePath
        self.dataContainerPath = dataContainerPath
        self.containerType = containerType
        self.isAccessible = FileManager.default.fileExists(atPath: dataContainerPath)
    }
}

// MARK: - Process Info

/// Information about the current process for educational display.
struct ProcessInfoItem: Identifiable {
    let id: String
    let label: String
    let value: String
    let icon: String
}

// MARK: - Educational Section

/// Educational content about iOS security mechanisms.
struct EducationalSection: Identifiable {
    let id: String
    let title: String
    let iconName: String
    let summary: String
    let details: [String]
    let keyConcepts: [(String, String)]

    init(id: String, title: String, iconName: String, summary: String, details: [String], keyConcepts: [(String, String)]) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.summary = summary
        self.details = details
        self.keyConcepts = keyConcepts
    }

    static let allSections: [EducationalSection] = [
        EducationalSection(
            id: "sandbox",
            title: "iOS 沙盒机制",
            iconName: "shield.lefthalf.filled",
            summary: "沙盒是 iOS 的核心安全机制，每个 App 运行在独立的沙盒容器中，无法访问其他 App 的数据。",
            details: [
                "每个 App 有自己的 Bundle 目录（只读）和数据容器目录（可读写）",
                "沙盒通过 entitlements 和 TCC 机制控制文件系统访问权限",
                "TrollStore 安装的应用可以通过特殊 entitlements 突破沙盒限制",
                "沙盒隔离是 iOS 安全模型的基础，防止恶意软件窃取其他 App 数据"
            ],
            keyConcepts: [
                ("Bundle Container", "应用安装包目录，包含可执行文件和资源，通常只读"),
                ("Data Container", "应用数据目录，包含 Documents/Library/tmp，可读写"),
                ("Entitlements", "应用权限声明文件，定义沙盒内外访问能力"),
                ("TCC", "Transparency, Consent and Control — 用户隐私权限管理框架")
            ]
        ),
        EducationalSection(
            id: "entitlements",
            title: "Entitlements 权限体系",
            iconName: "key.fill",
            summary: "Entitlements 是 iOS 应用权限的核心声明机制，决定了应用能访问哪些系统资源。",
            details: [
                "com.apple.private.security.no-sandbox — 禁用沙盒限制",
                "com.apple.private.security.no-container — 无容器限制",
                "task_for_pid-allow — 允许获取其他进程的任务端口",
                "platform-application — 系统平台应用标识",
                "TrollStore 利用这些 entitlements 实现免越狱高级权限"
            ],
            keyConcepts: [
                ("no-sandbox", "禁用沙盒逃逸检查，可访问文件系统任意路径"),
                ("container-manager", "允许管理其他应用的数据容器"),
                ("task_for_pid-allow", "允许 task_for_pid 调用，用于进程调试"),
                ("file-read-write", "文件系统读写权限声明")
            ]
        ),
        EducationalSection(
            id: "privacy",
            title: "App 隐私检测原理",
            iconName: "hand.raised.fill",
            summary: "App 通过读取设备信息进行环境检测，逆向研究这些检测逻辑有助于理解隐私保护机制。",
            details: [
                "设备标识: IDFA/IDFV/UUID 用于唯一标识设备或安装",
                "越狱检测: 检查 cydia://、/Applications/Cydia.app 等路径",
                "调试器检测: 通过 sysctl 检查 P_TRACED 标志",
                "代理检测: 检查 HTTP_PROXY 环境变量和系统代理设置",
                "Frida 检测: 扫描 27042 端口、检查 frida-agent 内存映射"
            ],
            keyConcepts: [
                ("IDFA", "Identifier for Advertising — 广告标识符，需用户授权"),
                ("IDFV", "Identifier for Vendor — 同一开发者的 App 共享"),
                ("P_TRACED", "进程被调试器附加时设置的标志位"),
                ("DTrace", "动态追踪框架，可用于分析系统调用")
            ]
        ),
        EducationalSection(
            id: "hook",
            title: "进程 Hook 技术",
            iconName: "link",
            summary: "Frida/Gadget 通过注入动态库实现函数 Hook，是逆向工程的核心技术之一。",
            details: [
                "Frida 通过 ptrace 注入 JavaScript 引擎到目标进程",
                "Gadget 模式: 将 frida-gadget.dylib 嵌入 App 实现自注入",
                "Interceptor.attach: 在函数入口/出口插入回调代码",
                "Objective-C Hook: 通过 method_exchangeImplementations 替换方法",
                "学习 Hook 技术有助于理解 App 的运行时行为和数据流向"
            ],
            keyConcepts: [
                ("ptrace", "进程追踪系统调用，Frida 用于注入目标进程"),
                ("Interceptor", "Frida API，用于拦截和修改函数调用"),
                ("fishhook", "Facebook 开源的 C 函数 Hook 库"),
                ("Swizzle", "Objective-C 方法混淆技术")
            ]
        ),
        EducationalSection(
            id: "container",
            title: "容器隔离原理",
            iconName: "shippingbox.fill",
            summary: "iOS 通过容器化隔离每个 App 的数据，Persona 机制可用于研究隔离边界。",
            details: [
                "每个 App 安装时系统创建独立的 Bundle 和 Data 容器",
                "Data Container 内: Documents(用户数据) / Library(配置) / tmp(临时)",
                "App Group Container: 同一开发者的 App 可共享数据",
                "Keychain: 加密存储敏感数据，按 keychain access group 隔离",
                "Persona: iOS 的用户身份隔离机制，每个 persona 有独立的数据空间"
            ],
            keyConcepts: [
                ("Bundle ID", "应用唯一标识，决定容器路径和 keychain 命名空间"),
                ("App Group", "同一开发者的多 App 共享数据容器"),
                ("Keychain", "iOS 加密键值存储，按 access group 隔离"),
                ("Container Manager", "MobileContainerManager — 管理应用容器系统服务")
            ]
        )
    ]
}
