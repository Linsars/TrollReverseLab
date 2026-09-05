// TrollReverseLab/SSHManager/SSHManager.swift
import Foundation
import Darwin

public class SSHManager: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public var port: Int = 2233   // 默认避开越狱 sshd 常用的 22/2222
    @Published public private(set) var status: String = "未启动"
    @Published public private(set) var binaryPath: String = "未找到"
    @Published public private(set) var lanIP: String = "获取中"
    @Published public private(set) var runningPids: [pid_t] = []
    @Published public private(set) var lastLogTail: String = ""

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

    /// dropbear 从这里读登录用户的公钥（当前用户 = mobile）
    public static var authorizedKeysPath: String {
        "/var/mobile/.ssh/authorized_keys"
    }

    private var serverPid: pid_t = 0
    private var monitorTimer: DispatchSourceTimer?

    /// sysctl 扫进程表找 dropbear（p_comm 16 字节足够区分，设备上没有第二个 dropbear）
    public static func findDropbearPids() -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }   // mib 长度必须是 3
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 3, &procs, &size, nil, 0) == 0 else { return [] }
        return procs.compactMap { entry -> pid_t? in
            guard entry.kp_proc.p_stat != 0 else { return nil }
            let comm = withUnsafeBytes(of: entry.kp_proc.p_comm) { buf -> String in
                String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            return comm == "dropbear" ? entry.kp_proc.p_pid : nil
        }
    }

    // MARK: - 启动

    public func start() {
        DispatchQueue.global(qos: .userInitiated).async {
            let ip = Self.primaryLanIP()
            DispatchQueue.main.async { self.lanIP = ip ?? "无 Wi-Fi 地址" }

            // 事实查询：已有实例就直接接管显示
            let existing = Self.findDropbearPids()
            if !existing.isEmpty {
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.runningPids = existing
                    self.binaryPath = Self.bundledSSHDir + "/dropbear"
                    self.status = "运行中（已有实例）· 端口 \(self.port) · pid \(existing.map(String.init).joined(separator: ","))"
                }
                self.startMonitor()
                return
            }

            guard let binary = [
                Self.bundledSSHDir + "/dropbear",
                "/var/jb/usr/sbin/dropbear"
            ].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.binaryPath = "未找到"
                    self.status = "无 ssh 服务二进制：需 CI 打包 .app/ssh/dropbear"
                }
                return
            }
            DispatchQueue.main.async { self.binaryPath = binary }

            // 主机密钥（首次自动生成）
            if !FileManager.default.fileExists(atPath: self.hostKeyPath) {
                let keygen = Self.bundledSSHDir + "/dropbearkey"
                guard FileManager.default.isExecutableFile(atPath: keygen) else {
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.status = "缺 dropbearkey，无法生成主机密钥"
                    }
                    return
                }
                var rc = Self.spawnSync(keygen, args: ["-t", "ed25519", "-f", self.hostKeyPath])
                if (rc >> 8) != 0 {
                    rc = Self.spawnSync(keygen, args: ["-t", "rsa", "-s", "2048", "-f", self.hostKeyPath])
                }
                guard FileManager.default.fileExists(atPath: self.hostKeyPath) else {
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.status = "主机密钥生成失败 (keygen status \(rc))"
                    }
                    return
                }
            }

            // PATH 注入捆绑目录（scp 会话用）
            let env = Self.environWithPrependedPATH(Self.bundledSSHDir)

            // daemonize 等效方案：-F 前台（实测可靠，避开 daemon() 的不确定性）
            // + POSIX_SPAWN_SETSID 让进程自立会话 —— app 被杀后变孤儿被 launchd 收养，服务照跑
            var pid: pid_t = 0
            let argv: [UnsafeMutablePointer<CChar>?] = [
                strdup(binary),
                strdup("-F"),
                strdup("-p"), strdup(String(self.port)),
                strdup("-r"), strdup(self.hostKeyPath),
                strdup("-B"),                                   // 允许空密码（iOS mobile 无密码时兜底）
                strdup("-w"),                                   // 禁 root 登录
                nil
            ]
            defer { for p in argv { free(p) } }

            var attrs: posix_spawnattr_t?
            posix_spawnattr_init(&attrs)
            posix_spawnattr_setflags(&attrs, Int16(0x0400))     // POSIX_SPAWN_SETSID
            let rc = posix_spawn(&pid, binary, nil, &attrs, argv, env)
            posix_spawnattr_destroy(&attrs)
            guard rc == 0 else {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.status = "posix_spawn 失败 errno=\(rc)"
                }
                return
            }

            // 短暂等待后扫进程表确认新实例真的起来了（bind 失败等会在这里现形）
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                let pids = Self.findDropbearPids()
                DispatchQueue.main.async {
                    if pids.isEmpty {
                        self.isRunning = false
                        self.runningPids = []
                        self.status = "启动失败：进程未存活（端口被占或密钥无效）"
                    } else {
                        self.isRunning = true
                        self.runningPids = pids
                        self.binaryPath = binary
                        self.status = "运行中 · 端口 \(self.port) · pid \(pids.map(String.init).joined(separator: ","))"
                    }
                }
            }
            DispatchQueue.main.async {
                self.status = "正在启动…"
            }
        }
    }

    public func stop() {
        DispatchQueue.global(qos: .userInitiated).async {
            let pids = Self.findDropbearPids()
            for p in pids { kill(p, SIGTERM) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                let survivors = Self.findDropbearPids()
                for p in survivors { kill(p, SIGKILL) }
            }
            DispatchQueue.main.async {
                self.isRunning = false
                self.runningPids = []
                self.status = pids.isEmpty ? "已停止（本无实例）" : "已停止（终止 pid \(pids.map(String.init).joined(separator: ","))）"
            }
        }
    }

    // MARK: - 状态轮询（纯事实刷新，永不误报）

    private var monitorTimer: DispatchSourceTimer?

    private func startMonitor() {
        stopMonitor()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // 顺手收尸（若子进程已退出，防僵尸）
            if self.serverPid > 0 {
                var st: Int32 = 0
                _ = waitpid(self.serverPid, &st, WNOHANG)
            }
            let pids = Self.findDropbearPids()
            self.runningPids = pids
            self.isRunning = !pids.isEmpty
            if pids.isEmpty && self.status.hasPrefix("运行中") {
                self.status = "进程已消失"
            }
        }
        timer.resume()
        monitorTimer = timer
    }

    private func stopMonitor() {
        monitorTimer?.cancel()
        monitorTimer = nil
    }

    // MARK: - 日志（daemonize 模式无文件日志，保留接口读旧路径）

    public func refreshLogTail() {
        let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        if let s = try? String(contentsOfFile: dir + "/ssh_server.log", encoding: .utf8) {
            let lines = s.components(separatedBy: "\n").filter { !$0.isEmpty }
            lastLogTail = lines.suffix(5).joined(separator: "\n")
        } else {
            lastLogTail = ""
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

    /// 解析已保存的公钥（逐行，去注释空行）
    public func savedKeys() -> [String] {
        readAuthorizedKeys()
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// 整体覆写 authorized_keys（供删除/编辑后回写）
    public func overwriteAuthorizedKeys(_ text: String, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let path = Self.authorizedKeysPath
            var msg = ""
            do {
                try FileManager.default.createDirectory(atPath: "/var/mobile/.ssh", withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: "/var/mobile/.ssh")
                let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if body.isEmpty {
                    try "".write(toFile: path, atomically: true, encoding: .utf8)
                } else {
                    try (body + "\n").write(toFile: path, atomically: true, encoding: .utf8)
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
                msg = body.isEmpty ? "公钥已清空" : "已更新 \(path)"
            } catch {
                msg = "写入失败: \(error.localizedDescription)"
            }
            DispatchQueue.main.async { completion(msg) }
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

    // MARK: - 初始化即拉取真实状态

    public init() {
        // 构造后延迟一拍查一次（避免阻塞主线程）
        DispatchQueue.global().async { [weak self] in
            let pids = Self.findDropbearPids()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.runningPids = pids
                self.isRunning = !pids.isEmpty
                self.status = pids.isEmpty ? "未启动" : "运行中（已有实例）· pid \(pids.map(String.init).joined(separator: ","))"
                if !pids.isEmpty { self.startMonitor() }
            }
        }
    }
}
