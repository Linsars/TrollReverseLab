//
//  MoreView.swift
//  TrollReverseLab
//
//  Aggregated "More" tab: groups secondary tools, settings, and utilities
//  into a single, visually organized launchpad. Avoids placing every module
//  directly in the TabBar, keeping the main navigation clean.
//

import SwiftUI

struct MoreView: View {
    // Two-column adaptive grid for tool cards.
    private let columns: [GridItem] = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerBanner

                    reverseSection
                    creationSection
                    systemSection
                    aboutFooter
                }
                .padding(.vertical)
            }
            .navigationTitle("更多")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Header

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("TrollAIBio 逆向")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }

            Text("本地 iOS 逆向学习工作台")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("所有工具仅用于个人技术研究与学习，严禁商业破解或批量营销用途。")
                .font(.caption)
                .foregroundColor(.red)
                .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal)
    }

    // MARK: - Reverse Tools

    private var reverseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "逆向工具", subtitle: "坐标、状态、编译、备份")

            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink(destination: CoordinatePickerView()) {
                    ToolCard(icon: "scope", title: "坐标拾取", subtitle: "拾取屏幕坐标", color: .blue)
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: StatusDashboardView()) {
                    ToolCard(icon: "gauge.high", title: "状态面板", subtitle: "温控与性能", color: .orange)
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: IPABuilderView()) {
                    ToolCard(icon: "hammer", title: "IPA 编译", subtitle: "本地源码编译", color: .purple)
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: AppBackupView()) {
                    ToolCard(icon: "doc.on.doc.fill", title: "备份管理", subtitle: "应用数据备份", color: .green)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Creation & Learning

    private var creationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "创作与学习", subtitle: "素材、排期、脚本、沙盒")

            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink(destination: MaterialEditorView()) {
                    ToolCard(icon: "doc.richtext", title: "素材编辑", subtitle: "多平台排版润色", color: .pink)
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: ContentSchedulerView()) {
                    ToolCard(icon: "calendar.badge.clock", title: "排期提醒", subtitle: "创作日程提醒", color: .red)
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: ScriptRecorderView()) {
                    ToolCard(icon: "record.circle", title: "脚本录制", subtitle: "交互动作学习", color: Color(red: 0.35, green: 0.34, blue: 0.84))
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: SandboxLabView()) {
                    ToolCard(icon: "shield.lefthalf.filled", title: "沙盒教学", subtitle: "iOS 隔离机制", color: Color(red: 0.0, green: 0.59, blue: 0.53))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
        }
    }

    // MARK: - System

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "系统", subtitle: "工作流、日志与设置")

            VStack(spacing: 12) {
                NavigationLink(destination: WorkflowEditorView()) {
                    SystemCardRow(icon: "square.grid.2x2.fill", title: "工作流", subtitle: "可视化节点编辑器", color: Color(red: 0.0, green: 0.68, blue: 0.94))
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: OperationLogView()) {
                    SystemCardRow(icon: "list.bullet.rectangle", title: "操作日志", subtitle: "操作历史与审计", color: Color(red: 0.50, green: 0.40, blue: 0.80))
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: PermissionCheckerView()) {
                    SystemCardRow(icon: "gearshape.fill", title: "设置", subtitle: "权限检测与模型配置", color: .gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Footer

    private var aboutFooter: some View {
        VStack(spacing: 4) {
            Text("TrollAIBio 逆向 v6.1.1")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("适用于 TrollStore 环境 · iOS 14+")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("仅用于个人技术研究与学习")
                .font(.caption2)
                .foregroundColor(.red)
                .padding(.top, 2)
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}

// MARK: - Tool Card

private struct ToolCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(color)
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - System Card Row (independent background for reliable iOS 14 tap)

private struct SystemCardRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(color)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

struct MoreView_Previews: PreviewProvider {
    static var previews: some View {
        MoreView()
    }
}
