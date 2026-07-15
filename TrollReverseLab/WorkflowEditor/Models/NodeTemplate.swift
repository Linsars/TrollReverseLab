import Foundation

// MARK: - Node Template

struct NodeTemplate: Identifiable, Equatable {
    let id: String
    let title: String
    let category: NodeCategory
    let iconSystemName: String
    let defaultParameters: [String: String]
    let inputPortLabels: [String]
    let outputPortLabels: [String]
    let riskLevel: RiskLevel
    let description: String
}

// MARK: - Node Registry (预置节点模板目录)

struct NodeRegistry {
    static let templates: [NodeTemplate] = [
        // === Blue: App Control ===
        NodeTemplate(id: "app.open", title: "打开应用", category: .appControl,
                     iconSystemName: "app.badge",
                     defaultParameters: ["bundleId": "com.apple.mobileslideshow"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已启动"],
                     riskLevel: .none, description: "通过 bundleId 启动指定应用"),

        NodeTemplate(id: "app.tap", title: "点击坐标", category: .appControl,
                     iconSystemName: "hand.tap",
                     defaultParameters: ["x": "200", "y": "400", "delay": "0.5"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已完成"],
                     riskLevel: .none, description: "在屏幕指定坐标处模拟点击"),

        NodeTemplate(id: "app.swipe", title: "滑动", category: .appControl,
                     iconSystemName: "arrow.left.and.right",
                     defaultParameters: ["x1": "200", "y1": "600", "x2": "200", "y2": "200", "duration": "0.3"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已完成"],
                     riskLevel: .none, description: "模拟滑动手势"),

        NodeTemplate(id: "app.input", title: "输入文本", category: .appControl,
                     iconSystemName: "keyboard",
                     defaultParameters: ["text": "Hello World"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已完成"],
                     riskLevel: .none, description: "在当前焦点输入框输入文本"),

        NodeTemplate(id: "app.wait", title: "等待", category: .appControl,
                     iconSystemName: "clock",
                     defaultParameters: ["seconds": "2"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已完成"],
                     riskLevel: .none, description: "等待指定秒数"),

        NodeTemplate(id: "app.screenshot", title: "截图", category: .appControl,
                     iconSystemName: "camera.viewfinder",
                     defaultParameters: [:],
                     inputPortLabels: ["触发"], outputPortLabels: ["图片"],
                     riskLevel: .none, description: "截取当前屏幕"),

        NodeTemplate(id: "app.readDraft", title: "读取草稿", category: .appControl,
                     iconSystemName: "doc.text",
                     defaultParameters: ["app": "jianying", "draftPath": "auto"],
                     inputPortLabels: ["触发"], outputPortLabels: ["草稿数据"],
                     riskLevel: .low, description: "读取应用的草稿文件"),

        // === Purple: AI Logic ===
        NodeTemplate(id: "logic.if", title: "条件判断", category: .aiLogic,
                     iconSystemName: "arrow.triangle.branch",
                     defaultParameters: ["condition": "", "variable": ""],
                     inputPortLabels: ["输入"], outputPortLabels: ["真", "假"],
                     riskLevel: .none, description: "根据条件分支执行"),

        NodeTemplate(id: "logic.loop", title: "循环", category: .aiLogic,
                     iconSystemName: "arrow.2.circlepath",
                     defaultParameters: ["count": "10", "mode": "fixed"],
                     inputPortLabels: ["输入"], outputPortLabels: ["循环体", "完成"],
                     riskLevel: .none, description: "循环执行指定次数"),

        NodeTemplate(id: "logic.variable", title: "设置变量", category: .aiLogic,
                     iconSystemName: "square.text.square",
                     defaultParameters: ["name": "var1", "value": ""],
                     inputPortLabels: ["输入"], outputPortLabels: ["输出"],
                     riskLevel: .none, description: "设置或修改变量值"),

        NodeTemplate(id: "logic.aiAnalysis", title: "AI分析", category: .aiLogic,
                     iconSystemName: "brain.head.profile",
                     defaultParameters: ["prompt": "", "model": "gpt-4"],
                     inputPortLabels: ["数据"], outputPortLabels: ["分析结果"],
                     riskLevel: .none, description: "使用AI分析输入数据并输出结果"),

        NodeTemplate(id: "logic.counter", title: "计数器", category: .aiLogic,
                     iconSystemName: "number.circle",
                     defaultParameters: ["start": "0", "step": "1"],
                     inputPortLabels: ["输入"], outputPortLabels: ["当前值"],
                     riskLevel: .none, description: "计数器，每次触发+step"),

        NodeTemplate(id: "logic.retry", title: "失败重试", category: .aiLogic,
                     iconSystemName: "exclamationmark.arrow.triangle.2.circlepath",
                     defaultParameters: ["maxRetries": "3", "delay": "1"],
                     inputPortLabels: ["操作", "失败"], outputPortLabels: ["成功", "放弃"],
                     riskLevel: .none, description: "失败时自动重试，最多maxRetries次"),

        // === Green: File / Data ===
        NodeTemplate(id: "file.readPhotos", title: "读取相册", category: .fileData,
                     iconSystemName: "photo.on.rectangle",
                     defaultParameters: ["filter": "vertical", "limit": "100", "sort": "newest"],
                     inputPortLabels: ["触发"], outputPortLabels: ["文件列表"],
                     riskLevel: .low, description: "读取相册中的照片/视频，支持按比例筛选"),

        NodeTemplate(id: "file.writePhotos", title: "保存到相册", category: .fileData,
                     iconSystemName: "photo.badge.plus",
                     defaultParameters: ["album": "TrollReverseLab"],
                     inputPortLabels: ["文件"], outputPortLabels: ["已完成"],
                     riskLevel: .low, description: "将文件保存到指定相册"),

        NodeTemplate(id: "file.writeNote", title: "写入备忘录", category: .fileData,
                     iconSystemName: "note.text.badge.plus",
                     defaultParameters: ["title": "工作流记录", "folder": ""],
                     inputPortLabels: ["内容"], outputPortLabels: ["已完成"],
                     riskLevel: .low, description: "将内容写入备忘录应用"),

        NodeTemplate(id: "file.readFile", title: "读取文件", category: .fileData,
                     iconSystemName: "doc.on.doc",
                     defaultParameters: ["path": "", "encoding": "utf8"],
                     inputPortLabels: ["触发"], outputPortLabels: ["文件内容"],
                     riskLevel: .low, description: "读取指定路径的文件内容"),

        NodeTemplate(id: "file.writeFile", title: "写入文件", category: .fileData,
                     iconSystemName: "square.and.pencil",
                     defaultParameters: ["path": "", "mode": "overwrite"],
                     inputPortLabels: ["内容"], outputPortLabels: ["已完成"],
                     riskLevel: .low, description: "将内容写入指定文件"),

        NodeTemplate(id: "file.sandboxRead", title: "沙盒读取", category: .fileData,
                     iconSystemName: "shippingbox",
                     defaultParameters: ["bundleId": "", "path": "Documents/"],
                     inputPortLabels: ["触发"], outputPortLabels: ["文件列表"],
                     riskLevel: .medium, description: "读取指定App的沙盒数据"),

        NodeTemplate(id: "file.sandboxWrite", title: "沙盒写入", category: .fileData,
                     iconSystemName: "shippingbox.fill",
                     defaultParameters: ["bundleId": "", "path": "Documents/"],
                     inputPortLabels: ["数据"], outputPortLabels: ["已完成"],
                     riskLevel: .medium, description: "写入指定App的沙盒数据"),

        // === Orange: Network ===
        NodeTemplate(id: "net.http", title: "HTTP请求", category: .network,
                     iconSystemName: "network",
                     defaultParameters: ["method": "GET", "url": "", "headers": "", "body": ""],
                     inputPortLabels: ["触发"], outputPortLabels: ["响应"],
                     riskLevel: .medium, description: "发送HTTP请求并获取响应"),

        NodeTemplate(id: "net.captureFilter", title: "抓包过滤", category: .network,
                     iconSystemName: "line.3.horizontal.decrease.circle",
                     defaultParameters: ["host": "", "method": "ALL"],
                     inputPortLabels: ["触发"], outputPortLabels: ["匹配请求"],
                     riskLevel: .low, description: "从抓包数据中筛选匹配的请求"),

        NodeTemplate(id: "net.apiCall", title: "API调用", category: .network,
                     iconSystemName: "globe",
                     defaultParameters: ["endpoint": "", "method": "POST", "auth": ""],
                     inputPortLabels: ["参数"], outputPortLabels: ["响应"],
                     riskLevel: .medium, description: "调用REST API接口"),

        // === Red: High Risk ===
        NodeTemplate(id: "risk.memRead", title: "内存读取", category: .highRisk,
                     iconSystemName: "memorychip",
                     defaultParameters: ["address": "0x0", "size": "256", "pid": ""],
                     inputPortLabels: ["触发"], outputPortLabels: ["内存数据"],
                     riskLevel: .high, description: "读取目标进程的内存数据"),

        NodeTemplate(id: "risk.memWrite", title: "内存写入", category: .highRisk,
                     iconSystemName: "memorychip.fill",
                     defaultParameters: ["address": "0x0", "data": "", "pid": ""],
                     inputPortLabels: ["数据"], outputPortLabels: ["已完成"],
                     riskLevel: .critical, description: "向目标进程内存写入数据"),

        NodeTemplate(id: "risk.fridaInject", title: "Frida注入", category: .highRisk,
                     iconSystemName: "syringe",
                     defaultParameters: ["script": "", "pid": "", "spawn": "false"],
                     inputPortLabels: ["触发"], outputPortLabels: ["注入结果"],
                     riskLevel: .critical, description: "使用Frida注入脚本到目标进程"),

        NodeTemplate(id: "risk.processAttach", title: "进程附加", category: .highRisk,
                     iconSystemName: "scope",
                     defaultParameters: ["pid": "", "name": ""],
                     inputPortLabels: ["触发"], outputPortLabels: ["已附加"],
                     riskLevel: .high, description: "附加到目标进程进行调试"),

        // === New: Coordinate Picker Integration ===
        NodeTemplate(id: "coord.tap", title: "坐标点位点击", category: .appControl,
                     iconSystemName: "scope",
                     defaultParameters: ["bundleId": "", "label": "", "tolerance": "15"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已完成"],
                     riskLevel: .none, description: "使用坐标拾取器保存的点位执行点击，支持±N像素容错"),

        NodeTemplate(id: "coord.swipe", title: "坐标点位滑动", category: .appControl,
                     iconSystemName: "arrow.up.and.down",
                     defaultParameters: ["bundleId": "", "label": "", "tolerance": "15"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已完成"],
                     riskLevel: .none, description: "使用坐标拾取器保存的滑动点位执行滑动"),

        NodeTemplate(id: "coord.input", title: "坐标点位输入", category: .appControl,
                     iconSystemName: "keyboard",
                     defaultParameters: ["bundleId": "", "label": "", "text": ""],
                     inputPortLabels: ["触发"], outputPortLabels: ["已完成"],
                     riskLevel: .none, description: "在坐标拾取器保存的输入框位置输入文本"),

        NodeTemplate(id: "coord.wait", title: "坐标点位等待", category: .appControl,
                     iconSystemName: "clock.badge.checkmark",
                     defaultParameters: ["bundleId": "", "label": "", "timeout": "10"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已加载"],
                     riskLevel: .none, description: "等待坐标点位区域内容加载完成"),

        // === New: Timer & System ===
        NodeTemplate(id: "sys.timer", title: "定时触发", category: .aiLogic,
                     iconSystemName: "timer",
                     defaultParameters: ["delay": "5", "repeat": "false"],
                     inputPortLabels: ["启动"], outputPortLabels: ["触发"],
                     riskLevel: .none, description: "延迟指定秒数后触发，可循环"),

        NodeTemplate(id: "sys.notification", title: "发送通知", category: .aiLogic,
                     iconSystemName: "bell.badge",
                     defaultParameters: ["title": "工作流通知", "body": ""],
                     inputPortLabels: ["输入"], outputPortLabels: ["已完成"],
                     riskLevel: .none, description: "发送本地通知提醒用户"),

        NodeTemplate(id: "sys.clipboard", title: "读写剪贴板", category: .fileData,
                     iconSystemName: "doc.on.clipboard",
                     defaultParameters: ["mode": "read", "text": ""],
                     inputPortLabels: ["触发"], outputPortLabels: ["剪贴板内容"],
                     riskLevel: .none, description: "读取或写入系统剪贴板"),

        NodeTemplate(id: "sys.deviceInfo", title: "设备信息", category: .fileData,
                     iconSystemName: "iphone",
                     defaultParameters: [:],
                     inputPortLabels: ["触发"], outputPortLabels: ["设备信息"],
                     riskLevel: .none, description: "获取设备型号、系统版本、电池状态等信息"),

        NodeTemplate(id: "sys.alert", title: "弹窗拦截", category: .appControl,
                     iconSystemName: "xmark.octagon",
                     defaultParameters: ["buttonText": "确定", "delay": "1"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已拦截"],
                     riskLevel: .low, description: "检测并自动点击弹窗按钮，拦截系统弹窗"),

        NodeTemplate(id: "sys.appRestart", title: "重启应用", category: .appControl,
                     iconSystemName: "arrow.clockwise",
                     defaultParameters: ["bundleId": "", "delay": "2"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已重启"],
                     riskLevel: .low, description: "关闭并重新打开指定应用"),

        NodeTemplate(id: "sys.randomDelay", title: "随机延时", category: .aiLogic,
                     iconSystemName: "shuffle",
                     defaultParameters: ["min": "1", "max": "5"],
                     inputPortLabels: ["触发"], outputPortLabels: ["已完成"],
                     riskLevel: .none, description: "随机延时min~max秒，模拟人工操作节奏"),
    ]

    // Get templates by category
    static func templates(in category: NodeCategory) -> [NodeTemplate] {
        templates.filter { $0.category == category }
    }

    // Get template by id
    static func template(id: String) -> NodeTemplate? {
        templates.first { $0.id == id }
    }

    // Create a node from a template
    static func createNode(from template: NodeTemplate, position: CGPoint = .zero) -> WorkflowNode {
        let inputPorts = template.inputPortLabels.enumerated().map { index, label in
            NodePort(label: label, isInput: true)
        }
        let outputPorts = template.outputPortLabels.enumerated().map { index, label in
            NodePort(label: label, isInput: false)
        }

        return WorkflowNode(
            title: template.title,
            category: template.category,
            iconSystemName: template.iconSystemName,
            aiNote: template.description,
            position: position,
            parameters: template.defaultParameters,
            inputPorts: inputPorts,
            outputPorts: outputPorts,
            riskLevel: template.riskLevel,
            isRiskConfirmed: false,
            isEnabled: true,
            aiOptimized: false
        )
    }
}
