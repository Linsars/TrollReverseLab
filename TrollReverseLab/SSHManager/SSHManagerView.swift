// TrollReverseLab/SSHManager/SSHManagerView.swift
import SwiftUI

/// SSH 管理主界面：服务开关 / 状态 / 公钥管理 / 连接说明 / 日志。
struct SSHManagerView: View {
    @ObservedObject var ssh: SSHManager
    @State private var publicKeyInput = ""
    @State private var installMessage = ""

    var body: some View {
        Form {
            // MARK: 服务状态
            Section(header: Text("服务状态")) {
                HStack {
                    Image(systemName: ssh.isRunning ? "checkmark.circle.fill" : "stop.circle")
                        .foregroundColor(ssh.isRunning ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ssh.isRunning ? "运行中" : "未运行").fontWeight(.medium)
                        Text(ssh.status).font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        if ssh.isRunning { ssh.stop() } else { ssh.start() }
                    }) {
                        Text(ssh.isRunning ? "停止" : "启动")
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(ssh.isRunning ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                HStack {
                    Text("端口").foregroundColor(.secondary)
                    Spacer()
                    TextField("端口", value: $ssh.port, formatter: NumberFormatter())
                        .font(.system(.caption, design: .monospaced))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
                HStack {
                    Text("连接地址").foregroundColor(.secondary)
                    Spacer()
                    Text("mobile@\(ssh.lanIP) -p \(ssh.port)")
                        .font(.system(.caption, design: .monospaced))
                }
                HStack {
                    Text("二进制").foregroundColor(.secondary)
                    Spacer()
                    Text(ssh.binaryPath)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // MARK: 公钥
            Section(header: Text("登录公钥（authorized_keys）"),
                    footer: Text("粘贴你电脑上 ~/.ssh/id_ed25519.pub 或 id_rsa.pub 的内容，用对应私钥登录。密码登录在非越狱下不可用。")) {
                TextEditor(text: $publicKeyInput)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 80)
                Button("写入公钥") {
                    ssh.installAuthorizedKey(publicKeyInput) { msg in
                        installMessage = msg
                    }
                }
                if !installMessage.isEmpty {
                    Text(installMessage).font(.caption).foregroundColor(.secondary)
                }
                if !ssh.readAuthorizedKeys().isEmpty {
                    Button("清空输入查看已有公钥") {
                        publicKeyInput = ssh.readAuthorizedKeys()
                    }
                    .font(.caption)
                }
            }

            // MARK: 使用说明
            Section(header: Text("连接方法")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. 电脑/手机生成密钥对：ssh-keygen -t ed25519").font(.system(.caption, design: .monospaced))
                    Text("2. 把 .pub 内容贴到上面，点「写入公钥」").font(.system(.caption, design: .monospaced))
                    Text("3. ssh mobile@\(ssh.lanIP) -p 2222").font(.system(.caption, design: .monospaced))
                    Text("4. 登录后即 mobile 身份 shell，工具已注入 no-sandbox 权限链").font(.caption).foregroundColor(.secondary)
                }
            }

            // MARK: 日志
            Section(header: Text("服务日志（尾部）")) {
                Text(ssh.lastLogTail.isEmpty ? "（暂无日志）" : ssh.lastLogTail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                Button("刷新日志") { ssh.refreshLogTail() }
            }
        }
        .navigationTitle("SSH 管理")
        .onAppear { ssh.refreshLogTail() }
    }
}
