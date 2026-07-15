import SwiftUI
import UIKit

// MARK: - Status Dashboard View

struct StatusDashboardView: View {

    @EnvironmentObject var statusManager: DeviceStatusManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Thermal warning banner
                if statusManager.isTasksPaused {
                    ThermalWarningBanner(
                        reason: statusManager.pauseReason,
                        isPaused: statusManager.isTasksPaused,
                        onToggle: {
                            if statusManager.isTasksPaused {
                                statusManager.resumeAllTasks()
                            } else {
                                statusManager.pauseAllTasks()
                            }
                        }
                    )
                }

                // Task progress card
                TaskProgressCard(manager: statusManager)

                // Device metrics grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    MetricCard(
                        title: "电池",
                        value: statusManager.batteryPercentage,
                        icon: statusManager.batteryIcon,
                        color: batteryColor,
                        subtitle: statusManager.isCharging ? "充电中" : "使用中"
                    )

                    MetricCard(
                        title: "设备温度",
                        value: String(format: "%.1f°C", statusManager.estimatedTemperature),
                        icon: "thermometer",
                        color: Color(statusManager.thermalStateColor),
                        subtitle: statusManager.thermalStateText
                    )

                    MetricCard(
                        title: "内存占用",
                        value: statusManager.memoryUsageText,
                        icon: "memorychip",
                        color: Color(red: 0.4, green: 0.6, blue: 0.9),
                        subtitle: "当前进程"
                    )

                    MetricCard(
                        title: "磁盘空间",
                        value: statusManager.diskFreeText,
                        icon: "internaldrive",
                        color: Color(red: 0.5, green: 0.5, blue: 0.5),
                        subtitle: "剩余 / \(statusManager.diskTotalText)"
                    )
                }

                // Thermal protection settings
                ThermalProtectionCard(manager: statusManager)

                // Quick actions
                QuickActionsCard(manager: statusManager)

                // System info
                SystemInfoCard()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("状态面板")
        .navigationBarTitleDisplayMode(.large)
    }

    private var batteryColor: Color {
        let pct = statusManager.batteryLevel
        if pct > 0.5 { return Color(red: 0.2, green: 0.7, blue: 0.3) }
        if pct > 0.2 { return Color(red: 0.9, green: 0.7, blue: 0.1) }
        return Color(red: 0.9, green: 0.3, blue: 0.1)
    }
}

// MARK: - Thermal Warning Banner

struct ThermalWarningBanner: View {
    let reason: String
    let isPaused: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isPaused ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                .font(.system(size: 24))
                .foregroundColor(isPaused ? .red : .green)

            VStack(alignment: .leading, spacing: 4) {
                Text(isPaused ? "任务已暂停" : "任务运行中")
                    .font(.system(size: 14, weight: .semibold))
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onToggle) {
                Text(isPaused ? "恢复" : "暂停")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(isPaused ? Color.green : Color.red))
                    .foregroundColor(.white)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(isPaused ? .systemRed : .systemGreen).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(isPaused ? .systemRed : .systemGreen).opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Task Progress Card

struct TaskProgressCard: View {
    @ObservedObject var manager: DeviceStatusManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundColor(.accentColor)
                Text("任务进度")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(manager.activeTaskCount) 个活跃任务")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            if manager.activeTaskCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(manager.currentTaskName.isEmpty ? "执行中..." : manager.currentTaskName)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    ProgressView(value: manager.taskProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .accentColor(.blue)

                    Text("\(Int(manager.taskProgress * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("暂无活跃任务")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            // Pause/resume all
            Button(action: {
                if manager.isTasksPaused {
                    manager.resumeAllTasks()
                } else {
                    manager.pauseAllTasks()
                }
            }) {
                HStack {
                    Image(systemName: manager.isTasksPaused ? "play.fill" : "pause.fill")
                    Text(manager.isTasksPaused ? "恢复所有任务" : "暂停所有任务")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(manager.isTasksPaused ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                )
                .foregroundColor(manager.isTasksPaused ? .green : .red)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Thermal Protection Card

struct ThermalProtectionCard: View {
    @ObservedObject var manager: DeviceStatusManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "thermometer.sun")
                    .foregroundColor(.orange)
                Text("智能温控保护")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Toggle("", isOn: $manager.isThermalProtectionEnabled)
                    .labelsHidden()
            }

            if manager.isThermalProtectionEnabled {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("温度阈值")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\(String(format: "%.0f", manager.thermalThreshold))°C")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.orange)
                    }

                    Slider(value: $manager.thermalThreshold, in: 35...45, step: 1)
                        .accentColor(.orange)

                    Text("超过阈值 +3°C 自动暂停任务，降至阈值 -3°C 自动恢复")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Current thermal state indicator
            HStack {
                Circle()
                    .fill(Color(manager.thermalStateColor))
                    .frame(width: 8, height: 8)
                Text("当前热状态: \(manager.thermalStateText)")
                    .font(.system(size: 12))
                Spacer()
                Text(String(format: "%.1f°C", manager.estimatedTemperature))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(manager.thermalStateColor))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Quick Actions Card

struct QuickActionsCard: View {
    @ObservedObject var manager: DeviceStatusManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.horizontal.circle")
                    .foregroundColor(.accentColor)
                Text("快捷操作")
                    .font(.system(size: 16, weight: .semibold))
            }

            HStack(spacing: 12) {
                QuickActionButton(
                    icon: "pause.circle.fill",
                    title: "暂停全部",
                    color: .red,
                    action: { manager.pauseAllTasks() }
                )

                QuickActionButton(
                    icon: "play.circle.fill",
                    title: "恢复全部",
                    color: .green,
                    action: { manager.resumeAllTasks() }
                )

                QuickActionButton(
                    icon: "snowflake.circle.fill",
                    title: "降温模式",
                    color: .blue,
                    action: {
                        manager.isThermalProtectionEnabled = true
                        manager.thermalThreshold = 36.0
                        manager.pauseAllTasks()
                    }
                )
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
            .foregroundColor(color)
        }
    }
}

// MARK: - System Info Card

struct SystemInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("系统信息")
                    .font(.system(size: 16, weight: .semibold))
            }

            Divider()

            InfoRow(label: "设备型号", value: deviceModel)
            InfoRow(label: "系统版本", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            InfoRow(label: "设备名称", value: UIDevice.current.name)
            InfoRow(label: "屏幕尺寸", value: screenSize)
            InfoRow(label: "CPU核心数", value: "\(ProcessInfo.processInfo.processorCount) 核")
            InfoRow(label: "物理内存", value: physicalMemory)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) { ptr in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }
        return machine
    }

    private var screenSize: String {
        let screen = UIScreen.main.bounds
        return String(format: "%.0f × %.0f", screen.width, screen.height)
    }

    private var physicalMemory: String {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB", gb)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
        }
    }
}
