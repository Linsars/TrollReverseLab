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

    // MARK: - HAR Export

    /// Export captured requests as HAR (HTTP Archive) format JSON
    public func exportAsHAR() -> String? {
        let entries = capturedRequests.map { req -> [String: Any] in
            var entry: [String: Any] = [:]

            // Request
            var request: [String: Any] = [:]
            request["method"] = req.method
            request["url"] = req.url
            request["httpVersion"] = "HTTP/1.1"

            var headers = [[String: String]]()
            for (key, value) in req.requestHeaders {
                headers.append(["name": key, "value": value])
            }
            request["headers"] = headers

            if let body = req.requestBody {
                request["bodySize"] = body.count
                var postData: [String: Any] = [:]
                postData["mimeType"] = req.requestHeaders["Content-Type"] ?? "application/octet-stream"
                postData["text"] = req.requestBodyString
                request["postData"] = postData
            } else {
                request["bodySize"] = 0
            }

            entry["request"] = request

            // Response
            var response: [String: Any] = [:]
            response["status"] = req.responseStatus
            response["statusText"] = ""
            response["httpVersion"] = "HTTP/1.1"

            var respHeaders = [[String: String]]()
            for (key, value) in req.responseHeaders {
                respHeaders.append(["name": key, "value": value])
            }
            response["headers"] = respHeaders

            if let body = req.responseBody {
                response["bodySize"] = body.count
                response["content"] = [
                    "size": body.count,
                    "mimeType": req.contentType,
                    "text": req.responseBodyString
                ]
            } else {
                response["bodySize"] = 0
                response["content"] = ["size": 0, "mimeType": ""]
            }

            entry["response"] = response

            // Timing
            entry["startedDateTime"] = iso8601String(req.timestamp)
            entry["time"] = req.duration * 1000  // milliseconds

            return entry
        }

        let har: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": [
                    "name": "TrollReverseLab",
                    "version": "5.0.0"
                ],
                "entries": entries
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: har, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return nil
    }

    /// Save HAR to Documents and return the file path
    public func saveHARFile() -> String? {
        guard let har = exportAsHAR() else { return nil }
        let fileName = "capture_\(Int(Date().timeIntervalSince1970)).har"
        let fileURL = URL(fileURLWithPath: capturesFile)
            .deletingLastPathComponent()
            .appendingPathComponent(fileName)
        do {
            try har.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL.path
        } catch {
            return nil
        }
    }

    // MARK: - Request Replay

    /// Replay a captured request and return the response
    public func replayRequest(_ request: CapturedRequest, completion: @escaping (Result<(Int, [String: String], Data?), Error>) -> Void) {
        guard let url = URL(string: request.url) else {
            completion(.failure(NSError(domain: "PacketCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method

        // Copy headers
        for (key, value) in request.requestHeaders {
            // Skip proxy-related headers
            let lowerKey = key.lowercased()
            if lowerKey == "host" || lowerKey == "proxy-connection" || lowerKey == "connection" {
                continue
            }
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // Copy body
        urlRequest.httpBody = request.requestBody
        urlRequest.timeoutInterval = 30

        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "PacketCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            var headers: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                headers["\(key)"] = "\(value)"
            }
            completion(.success((httpResponse.statusCode, headers, data)))
        }.resume()
    }

    // MARK: - JSON Body Formatting

    /// Pretty-print JSON body if applicable
    public static func prettyFormatJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let result = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return result
    }

    /// Check if content type is JSON
    public static func isJSON(_ contentType: String) -> Bool {
        return contentType.lowercased().contains("json")
    }

    // MARK: - Helpers

    private func iso8601String(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
