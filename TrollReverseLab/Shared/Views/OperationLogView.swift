import SwiftUI
import UIKit

struct OperationLogView: View {
    @ObservedObject var logger = OperationLogger.shared
    @State private var selectedModule: String? = nil
    @State private var searchText = ""
    @State private var showExportSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Statistics bar
            HStack(spacing: 12) {
                StatChip(title: "总计", value: logger.totalActions, color: .accentColor)
                StatChip(title: "成功", value: logger.successCount, color: .green)
                StatChip(title: "失败", value: logger.failureCount, color: .red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Filter bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("搜索操作...", text: $searchText)
                    .font(.caption)
                    .autocapitalization(.none)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))

            // Module filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ModuleFilterChip(title: "全部", isSelected: selectedModule == nil) {
                        selectedModule = nil
                    }
                    ForEach(logger.moduleNames, id: \.self) { name in
                        ModuleFilterChip(title: name, isSelected: selectedModule == name) {
                            selectedModule = (selectedModule == name) ? nil : name
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 6)

            // Log list
            if filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("暂无操作记录")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredEntries) { entry in
                    LogRowView(entry: entry)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("操作日志")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(
            trailing: Menu {
                Button {
                    showExportSheet = true
                } label: {
                    Label("导出日志", systemImage: "square.and.arrow.up")
                }
                Button {
                    logger.clearLogs()
                } label: {
                    Label("清除全部", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        )
        .sheet(isPresented: $showExportSheet) {
            ExportLogSheet(logText: logger.exportAsText())
        }
    }

    private var filteredEntries: [OperationLogEntry] {
        logger.filtered(module: selectedModule, searchText: searchText)
    }
}

// MARK: - Stat Chip

private struct StatChip: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Module Filter Chip

private struct ModuleFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .medium : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Log Row

private struct LogRowView: View {
    let entry: OperationLogEntry

    private var resultColor: Color {
        switch entry.resultColor {
        case "green": return .green
        case "red": return .red
        case "blue": return .accentColor
        case "gray": return .secondary
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Color indicator
            Circle()
                .fill(resultColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.module)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                    Text(entry.action)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(entry.result)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(resultColor)
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Text(entry.timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Export Sheet

private struct ExportLogSheet: View {
    let logText: String
    @Environment(\.presentationMode) var presentationMode
    @State private var copied = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    Text(logText)
                        .font(.system(.caption, design: .monospaced))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    UIPasteboard.general.string = logText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "已复制到剪贴板" : "复制全部日志")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(Color.accentColor)
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(16)
            }
            .navigationTitle("导出日志")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("完成")
                }
            )
        }
    }
}
