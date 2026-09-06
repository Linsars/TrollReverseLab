//
//  FridaEngine.swift
//  TrollReverseLab
//
//  Module 2: Local Frida memory debugging engine.
//  Attaches ONLY to user-selected TrollStore app processes for local
//  reverse code analysis, parameter reading, and runtime logic research.
//
//  INTEGRATED FROM: Material 3 — H5GG process enumeration & script management
//  - listTrollProcesses(): enumerates TrollStore app processes only
//  - LocalScriptModel: local Lua/Frida JS script storage
//  - Script save/load for offline script library management
//
//  CONSTRAINT: No global process injection. No payment hooks. No online
//  verification logic tampering. Only user-selected local app research.
//

import Foundation
import SwiftUI

// MARK: - Local Script Model (from Material 3)

/// Local script model for Lua/Frida JS script storage.
/// Bound to a specific TrollStore app container via targetAppUUID.
public struct LocalScriptModel: Codable, Identifiable {
    public var id: String
    public var scriptName: String
    public var scriptType: String // "lua" or "frida_js"
    public var scriptContent: String
    public var targetAppUUID: String // bound TrollStore app container
    public var createdDate: Date

    public init(id: String = UUID().uuidString, scriptName: String, scriptType: String, scriptContent: String, targetAppUUID: String, createdDate: Date = Date()) {
        self.id = id
        self.scriptName = scriptName
        self.scriptType = scriptType
        self.scriptContent = scriptContent
        self.targetAppUUID = targetAppUUID
        self.createdDate = createdDate
    }
}

/// Represents a local process that can be attached for debugging.
public struct LocalProcess: Identifiable, Hashable {
    public let id: Int32
    public let name: String
    public let bundleIdentifier: String?
    public let pid: Int32
}

/// State of the Frida debugging session.
public enum FridaSessionState: Equatable {
    case disconnected
    case connecting
    case attached(processName: String)
    case scriptLoaded(scriptName: String)
    case error(message: String)
}

/// Manages Frida gadget communication for local process debugging.
/// Communicates with frida-gadget via a local bridge interface.
public final class FridaEngine: ObservableObject {

    @Published public private(set) var state: FridaSessionState = .disconnected
    @Published public private(set) var consoleOutput: [ConsoleMessage] = []
    @Published public private(set) var loadedScripts: [DebugScript] = []
    @Published public private(set) var tracedFunctions: [FunctionTrace] = []
    @Published public private(set) var localScripts: [LocalScriptModel] = []

    @Published public var sshManager = SSHManager()

    @Published public var selectedTargetApp: TrollStoreApp?

    private var currentProcess: LocalProcess?
    private var bridge: FridaBridge?

    public init() {}

    // MARK: - Process Management (from Material 3)

    /// Lists local processes that can be attached.
    /// Returns the full live process list via sysctl (kernel threads and
    /// zombies excluded). Works without any Frida connection.
    public func listAttachableProcesses() -> [LocalProcess] {
        return listTrollProcesses()
    }

    /// Real process enumeration via sysctl KERN_PROC_ALL.
    /// Same proven pattern as SSHManager.findDropbearPids (mib len 3, SZOMB=6 filter).
    public func listTrollProcesses() -> [LocalProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }   // mib 长度必须是 3
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 3, &procs, &size, nil, 0) == 0 else { return [] }

        var result: [LocalProcess] = []
        for entry in procs {
            let pid = entry.kp_proc.p_pid
            guard pid > 1, entry.kp_proc.p_stat != 0, entry.kp_proc.p_stat != 6 else { continue }  // 僵尸不上报
            let comm = withUnsafeBytes(of: entry.kp_proc.p_comm) { buf -> String in
                String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            guard !comm.isEmpty else { continue }
            result.append(LocalProcess(id: pid, name: comm, bundleIdentifier: nil, pid: pid))
        }
        return result.sorted { $0.pid < $1.pid }
    }

    /// Attaches to a user-selected local app process for debugging.
    public func attach(to process: LocalProcess) {
        state = .connecting
        currentProcess = process
        diskLog("[ATTACH] request: \(process.name) pid=\(process.pid)")

        // Initialize bridge connection to frida-core (local device)
        bridge = FridaBridge()
        bridge?.delegate = self
        bridge?.attach(to: process.pid) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    self.state = .attached(processName: process.name)
                    self.logInfo("Attached to \(process.name) (PID: \(process.pid))")
                    self.sshManager.start()
                    self.startInboxWatcher()
                } else {
                    self.state = .error(message: error ?? "Unknown error")
                    self.logError(error ?? "Attachment failed")
                }
            }
        }
    }

    /// Detaches from the current process.
    public func detach() {
        bridge?.detach()
        currentProcess = nil
        state = .disconnected
        logInfo("Detached from process")
    }

    // MARK: - Script Inbox（SSH 自动驾驶总线）

    /// 收件箱：Documents/frida_inbox/ 下出现 .js 即执行到已 attach 目标，执行后改名 .done
    /// SSH 写脚本 = 驾驶，trl_frida.log = 观察，全程用户不碰屏幕
    private var inboxTimer: DispatchSourceTimer?

    private var inboxDirectory: String {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        return (docs as NSString).appendingPathComponent("frida_inbox")
    }

    /// attach 成功后启动轮询；目录常驻创建，SSH 端可提前投递
    private func startInboxWatcher() {
        try? FileManager.default.createDirectory(atPath: inboxDirectory, withIntermediateDirectories: true)
        diskLog("[INBOX] ready: \(inboxDirectory)")

        guard inboxTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.drainInbox()
        }
        timer.resume()
        inboxTimer = timer
    }

    private func drainInbox() {
        guard case .attached = state else { return }   // 未 attach 不消费，脚本留在箱里
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: inboxDirectory) else { return }
        for file in files.sorted() where file.hasSuffix(".js") {
            let path = (inboxDirectory as NSString).appendingPathComponent(file)
            guard let data = FileManager.default.contents(atPath: path),
                  let script = String(data: data, encoding: .utf8), !script.isEmpty else { continue }

            let donePath = path + ".done"
            try? FileManager.default.removeItem(atPath: donePath)
            try? FileManager.default.moveItem(atPath: path, toPath: donePath)   // 先消费防重放
            let name = (file as NSString).deletingPathExtension
            diskLog("[INBOX] executing \(file)")
            DispatchQueue.main.async {
                self.executeScript(script, name: "inbox:\(name)")
            }
        }
    }

    // MARK: - Script Execution

    /// Loads and executes a Frida JS script in the attached process.
    public func executeScript(_ script: String, name: String) {
        // .attached 与 .scriptLoaded 都算"会话活着"——否则第二个脚本永远被拒
        var sessionAlive = false
        if case .attached = state { sessionAlive = true }
        if case .scriptLoaded = state { sessionAlive = true }
        guard sessionAlive else {
            logError("No process attached. Attach to a process first.")
            return
        }

        bridge?.executeScript(script) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let output):
                    self?.logInfo("Script executed: \(name)")
                    self?.logOutput(output)
                    self?.loadedScripts.append(DebugScript(name: name, content: script, executionCount: 1))
                    self?.state = .scriptLoaded(scriptName: name)
                    self?.archiveScript(script, name: name)
                case .failure(let error):
                    self?.logError("Script error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Function Tracing

    /// Traces function calls for the attached process.
    public func traceFunction(module: String, function: String) {
        let traceScript = """
        var addr = Module.findExportByName('\(module)', '\(function)');
        if (addr) {
            Interceptor.attach(addr, {
                onEnter: function(args) {
                    send({type: 'trace_enter', function: '\(function)', args: [args[0], args[1], args[2]]});
                },
                onLeave: function(retval) {
                    send({type: 'trace_leave', function: '\(function)', retval: retval.toString()});
                }
            });
            send({type: 'trace_success', function: '\(function)'});
        } else {
            send({type: 'error', message: 'Function not found: \(function)'});
        }
        """

        executeScript(traceScript, name: "trace_\(function)")
    }

    // MARK: - Local Script Library (from Material 3)

    /// Saves a script to the local script library.
    public func saveScriptToLocal(name: String, content: String, type: String) {
        let targetUUID = currentProcess?.bundleIdentifier ?? "general"
        let script = LocalScriptModel(
            scriptName: name,
            scriptType: type,
            scriptContent: content,
            targetAppUUID: targetUUID
        )
        localScripts.append(script)
        persistScript(script)
        logInfo("Script saved: \(name)")
    }

    /// Loads all saved local scripts from disk.
    public func loadLocalScripts() -> [LocalScriptModel] {
        let scriptsDir = getScriptsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: scriptsDir) else {
            return localScripts
        }

        var loaded: [LocalScriptModel] = []
        for file in files where file.hasSuffix(".json") {
            let path = (scriptsDir as NSString).appendingPathComponent(file)
            if let data = FileManager.default.contents(atPath: path),
               let script = try? JSONDecoder().decode(LocalScriptModel.self, from: data) {
                loaded.append(script)
            }
        }

        localScripts = loaded
        return loaded
    }

    private func persistScript(_ script: LocalScriptModel) {
        let scriptsDir = getScriptsDirectory()
        let path = (scriptsDir as NSString).appendingPathComponent("\(script.id).json")
        if let data = try? JSONEncoder().encode(script) {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    private func getScriptsDirectory() -> String {
        let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        let scriptsDir = (docsDir as NSString).appendingPathComponent("LocalScripts")
        try? FileManager.default.createDirectory(atPath: scriptsDir, withIntermediateDirectories: true)
        return scriptsDir
    }

    // MARK: - Console Output

    /// 磁盘日志：Documents/trl_frida.log —— SSH 远程旁观 Frida 调试全过程的落盘面
    private func diskLog(_ text: String) {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let path = docs + "/trl_frida.log"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm:ss.SSS"
        let line = "[\(fmt.string(from: Date()))] \(text)\n"
        if let fh = FileHandle(forWritingAtPath: path) {
            _ = try? fh.seekToEnd()
            fh.write(line.data(using: .utf8)!)
            try? fh.close()
        }
    }

    /// 最新执行的脚本存档：Documents/trl_last_script.js（覆盖式，SSH 可直接 cat）
    private func archiveScript(_ script: String, name: String) {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let header = "// name: \(name)\n// archived: \(Date())\n"
        try? (header + script + "\n").write(toFile: docs + "/trl_last_script.js", atomically: true, encoding: .utf8)
    }

    private func logInfo(_ message: String) {
        consoleOutput.append(ConsoleMessage(type: .info, text: message, timestamp: Date()))
        diskLog("[INFO] \(message)")
    }

    private func logError(_ message: String) {
        consoleOutput.append(ConsoleMessage(type: .error, text: message, timestamp: Date()))
        diskLog("[ERR ] \(message)")
    }

    private func logOutput(_ output: String) {
        consoleOutput.append(ConsoleMessage(type: .output, text: output, timestamp: Date()))
        diskLog("[OUT ] \(output)")
    }

    public func clearConsole() {
        consoleOutput.removeAll()
    }
}

// MARK: - FridaBridge Delegate

extension FridaEngine: FridaBridgeDelegate {
    public func bridge(_ bridge: FridaBridge, didReceiveMessage message: BridgeMessage) {
        DispatchQueue.main.async {
            switch message.type {
            case .trace:
                let trace = FunctionTrace(
                    function: message.data["function"] as? String ?? "",
                    arguments: message.data["args"] as? [String] ?? [],
                    returnValue: message.data["retval"] as? String
                )
                self.tracedFunctions.append(trace)
                self.logOutput("Trace: \(trace.function) -> \(trace.returnValue ?? "?")")
            case .output:
                self.logOutput(message.data["text"] as? String ?? "")
            case .error:
                self.logError(message.data["message"] as? String ?? "Unknown error")
            }
        }
    }

    public func bridgeDidDetach(_ bridge: FridaBridge, reason: Int32) {
        DispatchQueue.main.async {
            self.diskLog("[DETACH] session detached: \(FridaBridge.detachReasonName(reason))")
            self.state = .disconnected
            self.logInfo("Session detached: \(FridaBridge.detachReasonName(reason))")
        }
    }
}

// MARK: - Data Models

public struct ConsoleMessage: Identifiable {
    public let id = UUID()
    public let type: ConsoleMessageType
    public let text: String
    public let timestamp: Date
}

public enum ConsoleMessageType {
    case info
    case error
    case output
}

public struct DebugScript: Identifiable {
    public let id = UUID()
    public let name: String
    public let content: String
    public var executionCount: Int
}

public struct FunctionTrace: Identifiable {
    public let id = UUID()
    public let function: String
    public let arguments: [String]
    public let returnValue: String?
}
