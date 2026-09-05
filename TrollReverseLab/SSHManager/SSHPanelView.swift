// TrollReverseLab/SSHManager/SSHPanelView.swift
import SwiftUI

/// SSH 服务控制面板：开关 + 状态 + 端口 + 二进制路径回显。
struct SSHPanelView: View {
    @ObservedObject var sshManager: SSHManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sshManager.isRunning ? "terminal.fill" : "terminal")
                .foregroundColor(sshManager.isRunning ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("SSH 服务")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(sshManager.status)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                sshManager.isRunning ? sshManager.stop() : sshManager.start()
            } label: {
                Text(sshManager.isRunning ? "停止" : "启动")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(sshManager.isRunning ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
