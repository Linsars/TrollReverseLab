//
//  FridaBridge.swift
//  TrollReverseLab
//
//  Module 2: Swift bridge to the embedded frida-core engine.
//  The C layer (FridaCoreBridge.c) owns GLib/frida types; this file maps
//  them to Swift with explicit error handling. C-level state is global —
//  instances are thin handles and delegate routing goes through the
//  static activeDelegate so re-created bridge instances keep working.
//

import Foundation

/// Protocol for receiving messages from the Frida bridge.
public protocol FridaBridgeDelegate: AnyObject {
    func bridge(_ bridge: FridaBridge, didReceiveMessage message: BridgeMessage)
    /// Session detached from the target (target died / frida dropped it).
    func bridgeDidDetach(_ bridge: FridaBridge, reason: Int32)
}

extension FridaBridgeDelegate {
    /// Optional: engines that don't care can skip it.
    public func bridgeDidDetach(_ bridge: FridaBridge, reason: Int32) {}
}

/// Types of messages received from the Frida runtime.
public struct BridgeMessage {
    public enum MessageType {
        case trace
        case output
        case error
    }

    public let type: MessageType
    public let data: [String: Any]
}

/// Bridge to the embedded frida-core runtime for local process debugging.
public final class FridaBridge {

    public weak var delegate: FridaBridgeDelegate? {
        didSet {
            // C 回调只认识全局单例；新引擎实例设置 delegate 时提升为活跃路由
            if let d = delegate { FridaBridge.activeDelegate = d }
        }
    }

    /// Connection state (mirrors fcb_is_connected, cached for sync access)
    private(set) var isConnected = false

    /// Active delegate — C callbacks dispatch here. Weak: engine lifetime rules.
    private static weak var activeDelegate: FridaBridgeDelegate?

    /// Global singleton: registers the C callbacks exactly once.
    private static let shared: FridaBridge = {
        let b = FridaBridge(registering: false)
        let ctx = Unmanaged.passUnretained(b).toOpaque()
        fcb_set_message_callback({ json, cctx in
            guard let cctx = cctx else { return }
            let target = Unmanaged<FridaBridge>.fromOpaque(cctx).takeUnretainedValue()
            target.dispatchCMessage(json)
        }, ctx)
        fcb_set_state_callback({ reason, cctx in
            guard let cctx = cctx else { return }
            let target = Unmanaged<FridaBridge>.fromOpaque(cctx).takeUnretainedValue()
            target.dispatchCDetach(reason)
        }, ctx)
        return b
    }()

    public init() {
        _ = FridaBridge.shared   // 首次 init 触发回调注册
    }

    private init(registering: Bool) {}

    // MARK: - Process Enumeration

    /// Enumerates local processes via sysctl (same proven pattern as
    /// SSHManager.findDropbearPids). Zombies and kernel threads excluded.
    public func enumerateProcesses() -> [LocalProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 3, &procs, &size, nil, 0) == 0 else { return [] }

        var result: [LocalProcess] = []
        for entry in procs {
            let pid = entry.kp_proc.p_pid
            guard pid > 1, entry.kp_proc.p_stat != 0, entry.kp_proc.p_stat != 6 else { continue }  // SZOMB=6
            let comm = withUnsafeBytes(of: entry.kp_proc.p_comm) { buf -> String in
                String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            guard !comm.isEmpty else { continue }
            result.append(LocalProcess(id: pid, name: comm, bundleIdentifier: nil, pid: pid))
        }
        return result.sorted { $0.pid < $1.pid }
    }

    // MARK: - Process Attachment

    /// Attaches to a local process by PID via frida-core local device.
    public func attach(to pid: Int32, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var err = [CChar](repeating: 0, count: 512)
            if fcb_init(&err, 512) != 0 {
                let msg = String(cString: err)
                DispatchQueue.main.async {
                    self.isConnected = false
                    completion(false, "frida-core 初始化失败: \(msg)")
                }
                return
            }
            var err2 = [CChar](repeating: 0, count: 512)
            if fcb_attach(UInt32(bitPattern: pid), &err2, 512) != 0 {
                let msg = String(cString: err2)
                DispatchQueue.main.async {
                    self.isConnected = false
                    completion(false, "attach 失败: \(msg)")
                }
                return
            }
            DispatchQueue.main.async {
                self.isConnected = true
                completion(true, nil)
            }
        }
    }

    /// Detaches from the current process session.
    public func detach() {
        DispatchQueue.global(qos: .userInitiated).async {
            var err = [CChar](repeating: 0, count: 512)
            _ = fcb_detach(&err, 512)
            DispatchQueue.main.async { self.isConnected = false }
        }
    }

    // MARK: - Script Execution

    /// Loads a Frida JS script into the attached process (QJS runtime).
    /// send()/console.log() output arrives via the delegate message channel.
    public func executeScript(_ script: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard isConnected else {
            completion(.failure(FridaBridgeError.notConnected))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var err = [CChar](repeating: 0, count: 512)
            if fcb_load_script(script, &err, 512) != 0 {
                let msg = String(cString: err)
                DispatchQueue.main.async {
                    completion(.failure(FridaBridgeError.scriptLoadFailed(msg)))
                }
                return
            }
            DispatchQueue.main.async {
                let ver = String(cString: fcb_version_string())
                completion(.success("script loaded (frida-core \(ver))"))
            }
        }
    }

    // MARK: - C Callback Routing

    /// Entry point for script messages from the GLib loop thread.
    func dispatchCMessage(_ json: UnsafePointer<CChar>?) {
        guard let json = json else { return }
        let raw = String(cString: json)
        guard let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            Self.deliver(BridgeMessage(type: .output, data: ["text": raw]))
            return
        }
        switch obj["type"] as? String ?? "" {
        case "log":
            // console.log / console.warn / console.error from the script
            let payload = obj["payload"] as? String ?? raw
            Self.deliver(BridgeMessage(type: .output, data: ["text": payload]))
        case "send":
            // script send() calls
            if let payload = obj["payload"] {
                var text: String
                if let s = payload as? String {
                    text = s
                } else if let jd = try? JSONSerialization.data(withJSONObject: payload),
                          let s = String(data: jd, encoding: .utf8) {
                    text = s
                } else {
                    text = String(describing: payload)
                }
                Self.deliver(BridgeMessage(type: .output, data: ["text": text]))
            } else {
                Self.deliver(BridgeMessage(type: .output, data: ["text": raw]))
            }
        case "error":
            var d: [String: Any] = ["message": obj["description"] as? String ?? raw]
            if let stack = obj["stack"] as? String { d["stack"] = stack }
            Self.deliver(BridgeMessage(type: .error, data: d))
        default:
            Self.deliver(BridgeMessage(type: .output, data: ["text": raw]))
        }
    }

    /// Entry point for session-detach events from the GLib loop thread.
    func dispatchCDetach(_ reason: Int32) {
        DispatchQueue.main.async {
            self.isConnected = false
            FridaBridge.activeDelegate?.bridgeDidDetach(self, reason: reason)
        }
    }

    /// Fan a message out to the active delegate (main thread).
    private static func deliver(_ message: BridgeMessage) {
        guard let delegate = activeDelegate else { return }
        DispatchQueue.main.async {
            delegate.bridge(FridaBridge.shared, didReceiveMessage: message)
        }
    }

    /// Human-readable detach reason (logging helper).
    public static func detachReasonName(_ reason: Int32) -> String {
        switch reason {
        case 1: return "application_requested"
        case 2: return "process_replaced"
        case 3: return "process_terminated"
        case 4: return "connection_terminated"
        case 5: return "device_lost"
        default: return "reason_\(reason)"
        }
    }
}

// MARK: - Errors

public enum FridaBridgeError: Error, LocalizedError {
    case notConnected
    case scriptLoadFailed(String)
    case attachmentFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Frida bridge is not connected to any process."
        case .scriptLoadFailed(let detail):
            return "Failed to load script: \(detail)"
        case .attachmentFailed(let detail):
            return "Failed to attach to process: \(detail)"
        }
    }
}
