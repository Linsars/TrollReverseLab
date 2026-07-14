//
//  FridaBridge.swift
//  TrollReverseLab
//
//  Module 2: Bridge layer for communication with frida-gadget.
//  Provides the interface between Swift and the Frida JavaScript runtime.
//

import Foundation

/// Protocol for receiving messages from the Frida bridge.
public protocol FridaBridgeDelegate: AnyObject {
    func bridge(_ bridge: FridaBridge, didReceiveMessage message: BridgeMessage)
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

/// Bridge to frida-gadget runtime for local process debugging.
/// Communicates via a local RPC channel (Unix domain socket or named pipe).
public final class FridaBridge {

    public weak var delegate: FridaBridgeDelegate?

    /// Connection state
    private(set) var isConnected = false

    /// The Frida gadget configuration for local-only operation.
    /// Restricts to interactive mode with no network listener exposure.
    public static let gadgetConfig: [String: Any] = [
        "interaction": [
            "type": "script",
            "path": "/data/local/tmp/frida-script.js",
            "on_change": "reload"
        ],
        "teardown": "full"
    ]

    public init() {}

    // MARK: - Process Enumeration

    /// Enumerates local processes visible to the Frida runtime.
    /// Filters to only return user-installed applications.
    public func enumerateProcesses() -> [LocalProcess] {
        // In production, this calls frida-core's device.enumerateProcesses()
        // via the C bridge. For the scaffold, we return an empty list.
        //
        // The actual implementation links against FridaCore.framework and calls:
        //   let device = Device.local()
        //   let processes = try device.enumerateProcesses()
        //   return processes.filter { isUserApp($0) }
        return []
    }

    // MARK: - Process Attachment

    /// Attaches to a local process by PID.
    /// - Parameter pid: Process ID of the user-selected app
    /// - Parameter completion: Called with success/failure on the main thread
    public func attach(to pid: Int32, completion: @escaping (Bool, String?) -> Void) {
        // In production:
        //   let session = try device.attach(pid)
        //   self.session = session
        //   self.isConnected = true

        // Security: Verify PID corresponds to a user-selected TrollStore app
        // before allowing attachment.
        guard validateProcessForAttachment(pid) else {
            completion(false, "Process validation failed: only user-selected TrollStore apps can be attached.")
            return
        }

        isConnected = true
        completion(true, nil)
    }

    /// Detaches from the current process session.
    public func detach() {
        // In production: session?.detach()
        isConnected = false
    }

    // MARK: - Script Execution

    /// Executes a JavaScript script in the attached process.
    /// - Parameter script: Frida JS script source code
    /// - Parameter completion: Result with output string or error
    public func executeScript(_ script: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard isConnected else {
            completion(.failure(FridaBridgeError.notConnected))
            return
        }

        // In production:
        //   let script = try session.createScript(script)
        //   script.setMessageHandler { message, data in ... }
        //   try script.load()
        //   The script's send() calls are routed to the message handler.

        // For the scaffold, we simulate script execution feedback
        DispatchQueue.global(qos: .userInitiated).async {
            // Parse send() calls from the script to simulate output
            let outputs = self.extractSendCalls(from: script)
            DispatchQueue.main.async {
                completion(.success(outputs))
            }
        }
    }

    // MARK: - Security Validation

    /// Validates that a PID corresponds to an allowed process for attachment.
    private func validateProcessForAttachment(_ pid: Int32) -> Bool {
        // In production, this checks:
        // 1. The process is a user-installed app (not a system daemon)
        // 2. The app was installed via TrollStore (has .appInfo.plist)
        // 3. The user explicitly selected this app in the UI
        // 4. The app is not an App Store application
        return true // Placeholder — actual validation in production
    }

    /// Extracts send() call arguments from a Frida script for simulation.
    private func extractSendCalls(from script: String) -> String {
        var outputs: [String] = []
        let pattern = #"send\(\s*['"]?(.+?)['"]?\s*\)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(script.startIndex..., in: script)
            regex.enumerateMatches(in: script, range: range) { match, _, _ in
                if let match = match, let r = Range(match.range(at: 1), in: script) {
                    outputs.append(String(script[r]))
                }
            }
        }
        return outputs.isEmpty ? "[Script loaded — no output]" : outputs.joined(separator: "\n")
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
