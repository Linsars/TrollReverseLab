//
//  FridaEngine.swift
//  TrollReverseLab
//
//  Module 2: Local Frida memory debugging engine.
//  Attaches ONLY to user-selected TrollStore app processes for local
//  reverse code analysis, parameter reading, and runtime logic research.
//
//  CONSTRAINT: No global process injection. No payment hooks. No online
//  verification logic tampering. Only user-selected local app research.
//

import Foundation
import SwiftUI

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

    private let securityFilter = AppSecurityFilter.shared
    private var currentProcess: LocalProcess?
    private var bridge: FridaBridge?

    public init() {}

    // MARK: - Process Management

    /// Lists local processes that can be attached.
    /// Filters to only show TrollStore-installed applications.
    public func listAttachableProcesses() -> [LocalProcess] {
        // In production, this calls Frida's device.enumerateProcesses()
        // For now, we use a bridge to the frida-gadget runtime
        guard let bridge = bridge else {
            return []
        }
        return bridge.enumerateProcesses()
    }

    /// Attaches to a user-selected local app process for debugging.
    /// Validates security constraints before attaching.
    public func attach(to process: LocalProcess, isUserSelected: Bool) {
        // Security check: must be explicitly user-selected
        let validation = securityFilter.validateTarget(
            bundleIdentifier: process.bundleIdentifier ?? "",
            containerPath: "", // Filled by the caller
            isUserSelected: isUserSelected
        )

        switch validation {
        case .denied(let reason):
            state = .error(message: reason)
            logError(reason)
            return
        case .allowed:
            break
        }

        state = .connecting
        currentProcess = process

        // Initialize bridge connection to frida-gadget
        bridge = FridaBridge()
        bridge?.delegate = self
        bridge?.attach(to: process.pid) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.state = .attached(processName: process.name)
                    self?.logInfo("Attached to \(process.name) (PID: \(process.pid))")
                } else {
                    self?.state = .error(message: error ?? "Unknown error")
                    self?.logError(error ?? "Attachment failed")
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

    // MARK: - Script Execution

    /// Loads and executes a Frida JS script in the attached process.
    /// Validates the script against security constraints before execution.
    public func executeScript(_ script: String, name: String) {
        // Security validation
        let scriptValidation = securityFilter.validateScript(script)
        switch scriptValidation {
        case .rejected(let reason):
            state = .error(message: reason)
            logError(reason)
            return
        case .approved:
            break
        }

        guard case .attached = state else {
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
                case .failure(let error):
                    self?.logError("Script error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Function Tracing

    /// Traces function calls for the attached process.
    /// Only traces locally selected functions for reverse code analysis.
    public func traceFunction(module: String, function: String) {
        let traceScript = """
        // Local function trace for reverse code analysis
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

    // MARK: - Console Output

    private func logInfo(_ message: String) {
        consoleOutput.append(ConsoleMessage(type: .info, text: message, timestamp: Date()))
    }

    private func logError(_ message: String) {
        consoleOutput.append(ConsoleMessage(type: .error, text: message, timestamp: Date()))
    }

    private func logOutput(_ output: String) {
        consoleOutput.append(ConsoleMessage(type: .output, text: output, timestamp: Date()))
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
