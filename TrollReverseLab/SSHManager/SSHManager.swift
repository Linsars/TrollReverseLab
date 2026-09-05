// TrollReverseLab/SSHManager/SSHManager.swift
import Foundation
import SwiftUI

public class SSHManager: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public var port: Int = 2222
    @Published public private(set) var status: String = "未启动"
    @Published public private(set) var binaryPath: String = "未找到"

    private var sshdProcess: Process?

    // 候选顺序：app 内捆绑 dropbear 优先，其次系统 sshd（越狱/特殊环境才有）
    private var candidateBinaries: [String] {
        [
            Bundle.main.bundlePath + "/ssh/dropbear",
            Bundle.main.bundlePath + "/sshd",
            "/var/jb/usr/sbin/dropbear",   // rootless 越狱 bootstrap（如果有）
            "/usr/libexec/sshd"            // 理论路径，纯巨魔不存在
        ]
    }

    public func start() {
        guard !isRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            // 找可用二进制
            let binary = self.candidateBinaries.first { FileManager.default.isExecutableFile(atPath: $0) }

            DispatchQueue.main.async {
                guard let binary = binary else {
                    self.isRunning = false
                    self.binaryPath = "未找到"
                    self.status = "无可用 sshd/dropbear 二进制：需在 app 内捆绑 ssh/dropbear"
                    return
                }
                self.binaryPath = binary
            }

            guard let binary = binary else { return }

            // 配置写临时目录（iOS 没有 /tmp）
            let configPath = NSTemporaryDirectory() + "sshd_config"
            let sshDir = NSTemporaryDirectory() + "ssh"
            try? FileManager.default.createDirectory(atPath: sshDir, withIntermediateDirectories: true)
            try? SSHServer.generateConfig(port: self.port).write(toFile: configPath, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["-F", "-E", NSTemporaryDirectory() + "dropbear.log", "-p", String(self.port)]
            process.standardOutput = Pipe()
            process.standardError = process.standardOutput

            do {
                try process.run()
                DispatchQueue.main.async {
                    self.sshdProcess = process
                    self.isRunning = true
                    self.status = "运行中 · 端口 \(self.port) · \(binary)"
                }
                // 异步等退出（崩了/被杀 → 状态复位）
                process.terminationHandler = { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self, self.sshdProcess === process else { return }
                        self.sshdProcess = nil
                        self.isRunning = false
                        self.status = "进程已退出（code \(process.terminationStatus)）"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.status = "启动失败: \(error.localizedDescription)"
                }
            }
        }
    }

    public func stop() {
        sshdProcess?.terminate()
        sshdProcess = nil
        isRunning = false
        status = "已停止"
    }
}
