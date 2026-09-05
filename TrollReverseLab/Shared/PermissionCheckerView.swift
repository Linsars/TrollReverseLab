//
//  PermissionCheckerView.swift
//  TrollReverseLab
//
//  Module 4: Permission Self-Check & Settings
//  Tests whether the app's entitlements are properly applied and
//  verifies actual filesystem access to key sandbox directories.
//  Also hosts AI model and Frida configuration.
//
//  NOTE: Tool entry points (coordinate picker, status dashboard, IPA builder,
//  backup, material editor, content scheduler, script recorder, sandbox lab)
//  have been moved to MoreView to avoid duplication.
//

import SwiftUI

/// Permission self-check view — Module 4.
struct PermissionCheckerView: View {
    @State private var checkResults: [PermissionCheckResult] = []
    @State private var isChecking = false
    @State private var hasSandboxEscape = false

    private let scanner = TrollStoreAppScanner()

    // Settings
    @AppStorage("llm_api_base_url") private var apiBaseURL = "https://api.openai.com/v1"
    @AppStorage("llm_api_key") private var apiKey = ""
    @AppStorage("llm_model") private var model = "gpt-4o"
    @AppStorage("llm_temperature") private var temperature = 0.3
    @AppStorage("frida_gadget_mode") private var gadgetMode = "interactive"

    var body: some View {
        Form {
            // MARK: - Permission Status
            Section(header: Text("沙盒逃逸权限"), footer: Text("no-sandbox 权限是访问 /var/mobile/Containers/ 的前提")) {
                HStack {
                    Image(systemName: hasSandboxEscape ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(hasSandboxEscape ? .green : .red)
                    Text(hasSandboxEscape ? "已生效" : "未生效")
                        .fontWeight(.medium)
                }

                if isChecking {
                    HStack {
                        ProgressView()
                        Text("正在检测...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    runCheck()
                } label: {
                    Label("运行权限检测", systemImage: "shield.checkered")
                }
            }

            // MARK: - Path Access Results
            if !checkResults.isEmpty {
                Section(header: Text("路径访问测试")) {
                    ForEach(checkResults.indices, id: \.self) { index in
                        let result = checkResults[index]
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: result.isAccessible ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.isAccessible ? .green : .red)
                                    .font(.caption)
                                Text(result.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                            }
                            if result.isAccessible {
                                Text("可访问 — \(result.itemCount) 个条目")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else if let error = result.error {
                                Text("失败: \(error)")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                // Summary
                Section(header: Text("检测结果汇总")) {
                    let accessible = checkResults.filter { $0.isAccessible }.count
                    let total = checkResults.count
                    DiagnosticRow(label: "可访问路径", value: "\(accessible) / \(total)")
                    DiagnosticRow(label: "失败路径", value: "\(total - accessible)")

                    if accessible == 0 {
                        Text("所有路径均无法访问。IPA 缺失 no-sandbox 沙盒逃逸权限。请重新打包 IPA 并确保 entitlements 包含 com.apple.private.security.no-sandbox。")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if accessible < total {
                        Text("部分路径可访问。可能需要额外权限（如 container-manager、storage.AppDataContainers）。")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("所有路径均可访问。权限配置正常。")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            // MARK: - Expected Entitlements
            Section(header: Text("预期权限清单"), footer: Text("这些权限应在打包时通过 ldid 注入到 IPA 中")) {
                ForEach(expectedEntitlements, id: \.key) { ent in
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.accentColor)
                            .font(.caption)
                        VStack(alignment: .leading) {
                            Text(ent.key)
                                .font(.system(.caption2, design: .monospaced))
                            Text(ent.desc)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // MARK: - LLM API Configuration
            Section(header: Text("AI 模型配置"), footer: Text("配置 OpenAI 兼容 API 用于生成逆向学习脚本")) {
                TextField("API Base URL", text: $apiBaseURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)

                SecureField("API Key", text: $apiKey)
                    .autocapitalization(.none)

                TextField("Model", text: $model)
                    .autocapitalization(.none)

                HStack {
                    Text("Temperature")
                    Spacer()
                    Slider(value: $temperature, in: 0...1, step: 0.1)
                        .frame(width: 120)
                    Text(String(format: "%.1f", temperature))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }

            // MARK: - Frida Configuration
            Section(header: Text("Frida 调试配置")) {
                Picker("Gadget 模式", selection: $gadgetMode) {
                    Text("交互模式").tag("interactive")
                    Text("脚本模式").tag("script")
                }
            }

            // MARK: - About
            Section(header: Text("关于")) {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("6.3.1").foregroundColor(.secondary)
                }
                HStack {
                    Text("适用环境")
                    Spacer()
                    Text("纯 TrollStore（无越狱）").foregroundColor(.secondary)
                }
                HStack {
                    Text("功能模块")
                    Spacer()
                    Text("沙盒浏览 · 抓包 · Frida · AI脚本 · 工作流 · 坐标拾取 · 状态面板 · IPA编译 · 备份 · 素材编辑 · 内容排期 · 脚本录制 · 沙盒教学").foregroundColor(.secondary).font(.caption)
                }
                HStack {
                    Text("扫描路径")
                    Spacer()
                    Text("/var/containers/Bundle/Application/").foregroundColor(.secondary).font(.caption)
                }
                Text("TrollAIBio 逆向 是一款 iOS 本地逆向学习工具，仅用于个人技术研究与学习。严禁用于内购绕过、支付欺诈、联机作弊及商业破解用途。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("设置")
        .onAppear {
            if checkResults.isEmpty {
                runCheck()
            }
        }
    }

    // MARK: - Actions

    private func runCheck() {
        isChecking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let results = self.scanner.runPermissionCheck()
            let escape = self.scanner.hasSandboxEscape()
            DispatchQueue.main.async {
                self.checkResults = results
                self.hasSandboxEscape = escape
                self.isChecking = false
            }
        }
    }

    // MARK: - Expected Entitlements

    private struct EntitlementInfo {
        let key: String
        let desc: String
    }

    private var expectedEntitlements: [EntitlementInfo] {
        [
            EntitlementInfo(key: "application-identifier", desc: "应用标识符"),
            EntitlementInfo(key: "platform-application", desc: "平台应用标识（TrollStore 必须）"),
            EntitlementInfo(key: "com.apple.private.security.no-sandbox", desc: "沙盒逃逸（核心权限）"),
            EntitlementInfo(key: "com.apple.private.security.no-container", desc: "无容器限制（核心权限）"),
            EntitlementInfo(key: "com.apple.private.security.container-required", desc: "不需要容器（必须 false）"),
            EntitlementInfo(key: "com.apple.private.security.storage.AppDataContainers", desc: "应用数据容器访问"),
            EntitlementInfo(key: "com.apple.private.security.storage.file-read-write", desc: "文件系统读写"),
            EntitlementInfo(key: "com.apple.private.security.container-manager", desc: "容器管理"),
            EntitlementInfo(key: "com.apple.private.MobileContainerManager.allowed", desc: "MCM 容器管理"),
            EntitlementInfo(key: "com.apple.security.exception.files.absolute-path.read-write", desc: "绝对路径读写(/)"),
            EntitlementInfo(key: "com.apple.security.files.all", desc: "所有文件访问"),
            EntitlementInfo(key: "com.apple.security.files.root.read-write", desc: "根目录读写"),
            EntitlementInfo(key: "com.apple.security.application-groups", desc: "App Groups 通配"),
            EntitlementInfo(key: "com.apple.private.persona-mgmt", desc: "persona 管理"),
            EntitlementInfo(key: "task_for_pid-allow", desc: "task_for_pid 权限"),
            EntitlementInfo(key: "get-task-allow", desc: "调试附加"),
            EntitlementInfo(key: "com.apple.coremedia.jit", desc: "JIT 编译权限"),
            EntitlementInfo(key: "run-unsigned-code", desc: "运行未签名代码"),
            EntitlementInfo(key: "com.apple.springboard.debugapplications", desc: "SpringBoard 调试"),
            EntitlementInfo(key: "com.apple.security.network.client", desc: "网络访问（AI API）"),
            EntitlementInfo(key: "com.apple.private.tcc.allow", desc: "TCC 全文件访问"),
            EntitlementInfo(key: "com.apple.private.coreservices.canmaplsdatabase", desc: "LS 数据库映射"),
            EntitlementInfo(key: "com.apple.system-task-ports", desc: "系统任务端口"),
            EntitlementInfo(key: "com.apple.developer.kernel.increased-memory-limit", desc: "扩展内存限制"),
            EntitlementInfo(key: "com.apple.security.cs.disable-library-validation", desc: "禁用库验证"),
        ]
    }
}
