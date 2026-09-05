// TrollReverseLab/SSHManager/SSHManager.swift
import Foundation
import Darwin

public class SSHManager: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public var port: Int = 2222
    @Published public private(set) var status: String = "未启动"
    @Published public private(set) var binaryPath: String = "未找到"

    private var sshdPid: pid_t = 0
    private var monitorTimer: DispatchSourceTimer?

    // 候选顺序：app 内捆绑 dropbear 优先，其次越狱 bootstrap，最后理论路径
    private var candidateBinaries: [String] {
        [
            Bundle.main.bundlePath + "/ssh/dropbear",
            Bundle.main.bundlePath + "/sshd",
            "/var/jb/usr/sbin/dropbear",
            "/usr/libexec/sshd"
        ]
    }

    public func start() {
        guard !isRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            // 找可用二进制
            guard let binary = self.candidateBinaries.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.binaryPath = "未找到"
                    self.status = "无可用 sshd/dropbear：需在 .app 内捆绑 ssh/dropbear"
                }
                return
            }

            // 配置写临时目录（iOS 没有 /tmp）
            let tmp = NSTemporaryDirectory()
            try? SSHServer.generateConfig(port: self.port).write(toFile: tmp + "sshd_config", atomically: true, encoding: .utf8)

            // posix_spawn（iOS SDK 无 Foundation.Process）
            var pid: pid_t = 0
            let argv: [UnsafeMutablePointer<CChar>?] = [
                strdup(binary),
                strdup("-F"),                                   // 前台运行
                strdup("-E"), strdup(strdup(tmp + "dropbear.log")),  // dropbear 日志
                strdup("-p"), strdup(String(self.port)),
                nil
            ]
            defer { for p in argv { free(p) } }

            let rc = posix_spawn(&pid, binary, nil, nil, argv, environ)

            DispatchQueue.main.async {
                if rc == 0 {
                    self.sshdPid = pid
                    self.isRunning = true
                    self.binaryPath = binary
                    self.status = "运行中 · 端口 \(self.port) · pid \(pid)"
                    self.startMonitor()
                } else {
                    self.isRunning = false
                    self.status = "posix_spawn 失败 errno=\(rc)"
                }
            }
        }
    }

    public func stop() {
        if sshdPid > 0 { kill(sshdPid, SIGTERM) }
        stopMonitor()
        sshdPid = 0
        isRunning = false
        status = "已停止"
    }

    // MARK: - 存活监控

    private func startMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.sshdPid > 0 else { return }
            // kill(pid, 0) 只探测存活
            if kill(self.sshdPid, 0) != 0 {
                let code = self.sshdPid
                self.stopMonitor()
                self.sshdPid = 0
                self.isRunning = false
                self.status = "进程已退出 (pid \(code))，详见 dropbear.log"
            }
        }
        timer.resume()
        monitorTimer = timer
    }

    private func stopMonitor() {
        monitorTimer?.cancel()
        monitorTimer = nil
    }
}
