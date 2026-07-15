import SwiftUI

// MARK: - Sandbox Lab View

struct SandboxLabView: View {
    @EnvironmentObject var manager: SandboxLabManager

    var body: some View {
        NavigationView {
            List {
                // Sandbox escape status
                Section(header: Text("沙盒逃逸状态")) {
                    HStack {
                        Image(systemName: manager.hasSandboxEscape ? "checkmark.shield.fill" : "xmark.shield.fill")
                            .foregroundColor(manager.hasSandboxEscape ? .green : .red)
                        Text(manager.hasSandboxEscape ? "沙盒逃逸已生效" : "沙盒限制中")
                            .fontWeight(.medium)
                    }
                    HStack {
                        Text("可访问路径")
                        Spacer()
                        Text("\(manager.accessiblePathCount) / \(manager.totalPathCount)")
                            .foregroundColor(.secondary)
                    }
                    Button {
                        manager.scanSandboxPaths()
                    } label: {
                        Label("扫描路径", systemImage: "magnifyingglass")
                    }
                }

                // Sandbox paths
                if !manager.pathInfos.isEmpty {
                    Section(header: Text("路径可访问性")) {
                        ForEach(manager.pathInfos) { info in
                            SandboxPathRow(info: info)
                        }
                    }
                }

                // Process info
                Section(header: Text("进程信息")) {
                    if manager.processInfos.isEmpty {
                        Button {
                            manager.collectProcessInfo()
                        } label: {
                            Label("采集进程信息", systemImage: "cpu")
                        }
                    } else {
                        ForEach(manager.processInfos) { info in
                            HStack {
                                Image(systemName: info.icon)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(info.label)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(info.value)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                }
                            }
                        }
                        Button("重新采集") {
                            manager.collectProcessInfo()
                        }
                    }
                }

                // Containers
                Section(header: Text("应用容器")) {
                    if manager.containerInfos.isEmpty {
                        Button {
                            manager.scanContainers()
                        } label: {
                            Label("扫描容器", systemImage: "shippingbox")
                        }
                    } else {
                        ForEach(manager.containerInfos) { container in
                            ContainerRow(container: container)
                        }
                    }
                }

                // Educational sections
                Section(header: Text("教学知识库")) {
                    ForEach(manager.educationalSections) { section in
                        NavigationLink(destination: EducationalDetailView(section: section)) {
                            HStack {
                                Image(systemName: section.iconName)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(section.title)
                                        .font(.subheadline)
                                    Text(section.summary)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }

                // Disclaimer
                Section(footer: Text("本模块仅用于 iOS 沙盒机制教学和本地技术研究，不用于商业多账号运营或规避平台风控体系。所有操作均为只读检测。")) {
                    EmptyView()
                }
            }
            .navigationTitle("沙盒教学")
            .onAppear {
                if manager.pathInfos.isEmpty {
                    manager.scanSandboxPaths()
                }
                if manager.processInfos.isEmpty {
                    manager.collectProcessInfo()
                }
            }
        }
    }
}

// MARK: - Sandbox Path Row

struct SandboxPathRow: View {
    let info: SandboxPathInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: info.isAccessible ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(info.isAccessible ? .green : .red)
                    .font(.caption)
                Text(info.path)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }
            HStack {
                Image(systemName: info.category.iconName)
                    .font(.caption2)
                Text(info.category.displayName)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)

            if info.isAccessible && info.itemCount > 0 {
                Text("可访问 — \(info.itemCount) 个条目")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else if let error = info.error {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            Text(info.educationalNote)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }
}

// MARK: - Container Row

struct ContainerRow: View {
    let container: ContainerInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: container.isAccessible ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(container.isAccessible ? .green : .red)
                    .font(.caption)
                Text(container.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Text(container.bundleId)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(container.bundlePath)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Educational Detail View

struct EducationalDetailView: View {
    let section: EducationalSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: section.iconName)
                        .font(.title)
                        .foregroundColor(.accentColor)
                    Text(section.title)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                // Summary
                Text(section.summary)
                    .font(.body)
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)

                // Details
                VStack(alignment: .leading, spacing: 8) {
                    Text("详细说明")
                        .font(.headline)
                    ForEach(section.details, id: \.self) { detail in
                        HStack(alignment: .top) {
                            Image(systemName: "arrowtriangle.right.fill")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text(detail)
                                .font(.subheadline)
                        }
                    }
                }

                // Key concepts
                VStack(alignment: .leading, spacing: 8) {
                    Text("关键概念")
                        .font(.headline)
                    ForEach(section.keyConcepts, id: \.0) { concept in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "tag.fill")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                Text(concept.0)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            Text(concept.1)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 24)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Disclaimer
                Text("以上内容仅用于技术学习和研究目的，不应用于规避平台安全机制或进行违规操作。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
            .padding()
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
