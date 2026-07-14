//
//  PacketCaptureEngine.swift
//  TrollReverseLab
//
//  ObservableObject that manages the proxy server lifecycle,
//  captured requests, filtering, and AI export.
//

import Foundation
import SwiftUI

/// Manages packet capture state and captured requests.
public final class PacketCaptureEngine: ObservableObject {

    @Published public var isCapturing = false
    @Published public var capturedRequests: [CapturedRequest] = []
    @Published public var connectLogs: [String] = []
    @Published public var logMessages: [String] = []
    @Published public var filterMethod = ""
    @Published public var filterHost = ""
    @Published public var searchText = ""

    public let proxyPort: UInt16 = 8888

    private var proxyServer: ProxyServer?
    private let capturesFile: String

    public init() {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        let captureDir = (docs as NSString).appendingPathComponent("Captures")
        try? FileManager.default.createDirectory(atPath: captureDir, withIntermediateDirectories: true)
        capturesFile = (captureDir as NSString).appendingPathComponent("captured_requests.json")
        loadCaptures()
    }

    // MARK: - Start / Stop

    public func startCapture() {
        guard !isCapturing else { return }

        let server = ProxyServer(port: proxyPort)
        server.onCapturedRequest = { [weak self] request in
            DispatchQueue.main.async {
                self?.capturedRequests.insert(request, at: 0)
                self?.saveCaptures()
            }
        }
        server.onConnect = { [weak self] host, port in
            DispatchQueue.main.async {
                let log = "[CONNECT] \(host):\(port)"
                self?.connectLogs.insert(log, at: 0)
            }
        }
        server.onLog = { [weak self] msg in
            DispatchQueue.main.async {
                self?.logMessages.insert(msg, at: 0)
            }
        }

        do {
            try server.start()
            proxyServer = server
            isCapturing = true
        } catch {
            DispatchQueue.main.async {
                self.logMessages.insert("Failed to start proxy: \(error.localizedDescription)", at: 0)
            }
        }
    }

    public func stopCapture() {
        proxyServer?.stop()
        proxyServer = nil
        isCapturing = false
    }

    // MARK: - Clear

    public func clearCaptures() {
        capturedRequests.removeAll()
        connectLogs.removeAll()
        saveCaptures()
    }

    // MARK: - Filtering

    public var filteredRequests: [CapturedRequest] {
        capturedRequests.filter { req in
            if !filterMethod.isEmpty && req.method.uppercased() != filterMethod.uppercased() {
                return false
            }
            if !filterHost.isEmpty && !req.host.localizedCaseInsensitiveContains(filterHost) {
                return false
            }
            if !searchText.isEmpty {
                let text = searchText.lowercased()
                if !req.url.lowercased().contains(text) &&
                   !req.host.lowercased().contains(text) &&
                   !req.method.lowercased().contains(text) {
                    return false
                }
            }
            return true
        }
    }

    // MARK: - AI Export

    /// Returns a formatted summary of captured traffic for AI context.
    public func exportForAI(maxRequests: Int = 20) -> String {
        let requests = Array(capturedRequests.prefix(maxRequests))

        if requests.isEmpty {
            return "No captured network traffic available."
        }

        var lines: [String] = []
        lines.append("=== Captured Network Traffic (\(requests.count) requests) ===")
        lines.append("")

        for (index, req) in requests.enumerated() {
            lines.append("[\(index + 1)] \(req.aiSummary)")
            lines.append("")
        }

        // Summary statistics
        let httpReqs = requests.filter { !$0.isHTTPS }
        let httpsReqs = requests.filter { $0.isHTTPS }
        let hosts = Set(requests.map { $0.host })
        let methods = Set(requests.map { $0.method })

        lines.append("=== Traffic Summary ===")
        lines.append("Total requests: \(requests.count)")
        lines.append("HTTP: \(httpReqs.count), HTTPS: \(httpsReqs.count)")
        lines.append("Unique hosts: \(hosts.count)")
        lines.append("Methods: \(methods.sorted().joined(separator: ", "))")
        lines.append("Hosts: \(hosts.sorted().joined(separator: ", "))")

        return lines.joined(separator: "\n")
    }

    /// Returns captured requests filtered by host for targeted AI analysis.
    public func exportForAI(hostFilter: String?, maxRequests: Int = 20) -> String {
        var requests = capturedRequests
        if let host = hostFilter, !host.isEmpty {
            requests = requests.filter { $0.host.localizedCaseInsensitiveContains(host) }
        }
        let limited = Array(requests.prefix(maxRequests))

        if limited.isEmpty {
            return "No captured traffic for host: \(hostFilter ?? "")"
        }

        var lines: [String] = []
        lines.append("=== Captured Traffic for \(hostFilter ?? "all hosts") (\(limited.count) requests) ===")
        lines.append("")
        for (index, req) in limited.enumerated() {
            lines.append("[\(index + 1)] \(req.aiSummary)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    public var hasCapturedData: Bool {
        !capturedRequests.isEmpty
    }

    public var captureCount: Int {
        capturedRequests.count
    }

    // MARK: - Persistence

    private func saveCaptures() {
        let limited = Array(capturedRequests.prefix(500)) // Keep last 500
        if let data = try? JSONEncoder().encode(limited) {
            try? data.write(to: URL(fileURLWithPath: capturesFile))
        }
    }

    private func loadCaptures() {
        guard let data = FileManager.default.contents(atPath: capturesFile),
              let decoded = try? JSONDecoder().decode([CapturedRequest].self, from: data) else {
            return
        }
        capturedRequests = decoded
    }
}
