// TrollReverseLab/SSHManager/SSHManager.swift
import Foundation
import Darwin

public class SSHManager: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public var port: Int = 2233   // 默认避开越狱 sshd 常用的 22/2222
    @Published public private(set) var status: String = "未启动"
    @Published public private(set) var binaryPath: String = "未找到"
    @Published public private(set) var lanIP: String = "获取中"
    @Published public private(set) var lastLogTail: String = ""

    private var serverPid: pid_t = 0
    private var monitorTimer: DispatchSourceTimer?

    // MARK: - 路径

    /// app 内捆绑的 ssh 二进制目录（CI 打包时注入）
    public static var bundledSSHDir: String {
        Bundle.main.bundlePath + "/ssh"
    }

    /// 主机密钥放应用沙盒（重启不丢）
    private var hostKeyPath: String {
        let dir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/ssh_host_key"
    }

    private var logPath: String {
        let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        return dir + "/ssh_server.log"
    }

    /// dropbear 从这里读登录用户的公钥（当前用户 = mobile）
    public static var authorizedKeysPath: String {
        "/var/mobile/.ssh/authorized_keys"
    }

    // MARK: - 二进制候选（按序尝试）

    private var candidateBinaries: [(path: String, kind: ServerKind)] {
        var list: [(String, ServerKind)] = []
        let bd = Self.bundledSSHDir
        list.append((bd + "/dropbear", .dropbear))
        list.append((bd + "/sshd", .openssh))
        list.append(("/var/jb/usr/sbin/dropbear", .dropbear))   // 越狱 bootstrap 存在时的捷径
        return list.filter { FileManager.default.isExecutableFile(atPath: $0.0) }
    }

    public enum ServerKind {
        case dropbear
        case openssh
    }

    // MARK: - 启动

    public func start() {
        guard !isRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            // 局域网 IP
            let ip = Self.primaryLanIP()
            DispatchQueue.main.async { self.lanIP = ip ?? "无 Wi-Fi 地址" }

            guard let (binary, kind) = self.candidateBinaries.first else {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.binaryPath = "未找到"
                    self.status = "无 ssh 服务二进制：需 CI 打包 .app/ssh/dropbear"
                }
                return
            }

            switch kind {
            case .dropbear:
                self.startDropbear(binary)
            case .openssh:
                self.startOpenSSH(binary)
            }
        }
    }

    /// dropbear：非 root 可跑（生态验证过的纯巨魔方案）
    private func startDropbear(_ binary: String) {
        // 1. 主机密钥（首次自动生成）
        if !FileManager.default.fileExists(atPath: hostKeyPath) {
            let keygen = Self.bundledSSHDir + "/dropbearkey"
            guard FileManager.default.isExecutableFile(atPath: keygen) else {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.status = "缺 dropbearkey，无法生成主机密钥"
                }
                return
            }
            var rc = Self.spawnSync(keygen, args: ["-t", "ed25519", "-f", hostKeyPath])
            if (rc >> 8) != 0 {
                rc = Self.spawnSync(keygen, args: ["-t", "rsa", "-s", "2048", "-f", hostKeyPath])
            }
            guard FileManager.default.fileExists(atPath: hostKeyPath) else {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.status = "主机密钥生成失败 (keygen status \(rc))"
                }
                return
            }
        }

        // 2. PATH 注入捆绑目录（scp 会话要用）
        let env = Self.environWithPrependedPATH(Self.bundledSSHDir)

        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [
            strdup(binary),
            strdup("-F"),                                   // 前台
            strdup("-p"), strdup(String(port)),
            strdup("-r"), strdup(hostKeyPath),
            strdup("-B"),                                   // 允许空密码（iOS mobile 无密码时兜底）
            strdup("-w"),                                   // 禁 root 登录
            nil
        ]
        defer { for p in argv { free(p) } }

        // 注：不用 -E（部分路径上 EINVAL 早退），改用 file_actions 把 stderr 重定向到日志文件
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        let logFD = open(logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if logFD >= 0 {
            posix_spawn_file_actions_adddup2(&actions, logFD, STDOUT_FILENO)
            posix_spawn_file_actions_adddup2(&actions, logFD, STDERR_FILENO)
        }

        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        let rc = posix_spawn(&pid, binary, &actions, &attrs, argv, env)
        posix_spawnattr_destroy(&attrs)
        posix_spawn_file_actions_destroy(&actions)
        if logFD >= 0 { close(logFD) }

        handleSpawnResult(rc: rc, pid: pid, binary: binary, name: "dropbear")
    }

    /// OpenSSH sshd：可能因 privilege separation 在非 root 下拒绝，失败时状态区给真实错误
    private func startOpenSSH(_ binary: String) {
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [
            strdup(binary),
            strdup("-D"),
            strdup("-E"), strdup(logPath),
            strdup("-p"), strdup(String(port)),
            strdup("-h"), strdup(hostKeyPath),
            strdup("-o"), strdup("UsePAM no"),
            strdup("-o"), strdup("Subsystem=sftp internal-sftp"),
            nil
        ]
        defer { for p in argv { free(p) } }

        let rc = posix_spawn(&pid, binary, nil, nil, argv, environ)
        handleSpawnResult(rc: rc, pid: pid, binary: binary, name: "sshd")
    }

    private func handleSpawnResult(rc: Int32, pid: pid_t, binary: String, name: String) {
        DispatchQueue.main.async {
            if rc == 0 {
                self.serverPid = pid
                self.isRunning = true
                self.binaryPath = binary
                self.status = "\(name) 运行中 · 端口 \(self.port) · pid \(pid)"
                self.startMonitor()
            } else {
                self.isRunning = false
                self.status = "\(name) posix_spawn 失败 errno=\(rc)"
                self.refreshLogTail()
            }
        }
    }

    public func stop() {
        let pid = serverPid
        serverPid = 0
        stopMonitor()
        isRunning = false
        status = "已停止"

        guard pid > 0 else { return }
        kill(pid, SIGTERM)
        // 1.5s 内没退就升级 SIGKILL，并确保 reap（不留僵尸）
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            var st: Int32 = 0
            if waitpid(pid, &st, WNOHANG) == 0 {
                kill(pid, SIGKILL)
                var st2: Int32 = 0
                waitpid(pid, &st2, 0)
            }
        }
    }

    // MARK: - 公钥管理

    /// 把用户粘贴的公钥追加/写入 authorized_keys（mobile 的 HOME）
    public func installAuthorizedKey(_ publicKey: String, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let sshDir = "/var/mobile/.ssh"
            let path = Self.authorizedKeysPath
            var msg = ""
            do {
                try FileManager.default.createDirectory(atPath: sshDir, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sshDir)
                let key = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if FileManager.default.fileExists(atPath: path) {
                    let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                    if !existing.contains(key) {
                        try (existing + "\n" + key + "\n").write(toFile: path, atomically: true, encoding: .utf8)
                    }
                } else {
                    try (key + "\n").write(toFile: path, atomically: true, encoding: .utf8)
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
                msg = "公钥已写入 \(path)"
            } catch {
                msg = "写入失败: \(error.localizedDescription)"
            }
            DispatchQueue.main.async { completion(msg) }
        }
    }

    public func readAuthorizedKeys() -> String {
        return (try? String(contentsOfFile: Self.authorizedKeysPath, encoding: .utf8)) ?? ""
    }

    // MARK: - 存活监控

    private func startMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.serverPid > 0 else { return }
            // WNOHANG 探测 + 顺手 reap（防止僵尸进程被 kill(pid,0) 误判存活）
            var st: Int32 = 0
            let r = waitpid(self.serverPid, &st, WNOHANG)
            if r == self.serverPid {
                self.refreshLogTail()
                self.stopMonitor()
                self.serverPid = 0
                self.isRunning = false
                self.status = "进程已退出 (code \(st >> 8))"
            }
        }
        timer.resume()
        monitorTimer = timer
    }

    private func stopMonitor() {
        monitorTimer?.cancel()
        monitorTimer = nil
    }

    public func refreshLogTail() {
        if let s = try? String(contentsOfFile: logPath, encoding: .utf8) {
            let lines = s.components(separatedBy: "\n").filter { !$0.isEmpty }
            lastLogTail = lines.suffix(5).joined(separator: "\n")
        } else {
            lastLogTail = ""
        }
    }

    // MARK: - 工具

    private static func spawnSync(_ path: String, args: [String]) -> Int32 {
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(path)]
        for a in args { argv.append(strdup(a)) }
        argv.append(nil)
        defer { for p in argv { free(p) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, path, nil, nil, argv, environ)
        guard rc == 0 else { return rc }
        var st: Int32 = 0
        waitpid(pid, &st, 0)
        return st
    }

    /// 环境变量：PATH 前插捆绑 ssh 目录（让 dropbear 找得到旁边捆绑的 scp）
    private static func environWithPrependedPATH(_ dir: String) -> [UnsafeMutablePointer<CChar>?] {
        var pairs: [String] = []
        for i in 0..<Int.max {
            guard let c = environ[i] else { break }
            let s = String(cString: c)
            if !s.hasPrefix("PATH=") { pairs.append(s) }
        }
        let old = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        pairs.append("PATH=\(dir):\(old)")
        var env: [UnsafeMutablePointer<CChar>?] = pairs.map { strdup($0) }
        env.append(nil)
        return env
    }

    private static func primaryLanIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var result: String?
        var ptr = ifaddr
        while let p = ptr {
            let ifa = p.pointee
            if let sa = ifa.ifa_addr, (sa.pointee.sa_family == UInt8(AF_INET)) {
                var addr = sockaddr_in()
                memcpy(&addr, sa, MemoryLayout<sockaddr_in>.size)
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
                let name = String(cString: ifa.ifa_name)
                if name == "en0" { result = String(cString: buf); break }
                if result == nil { result = String(cString: buf) }
            }
            ptr = p.pointee.ifa_next
        }
        return result
    }
}
