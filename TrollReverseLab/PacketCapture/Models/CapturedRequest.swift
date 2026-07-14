//
//  CapturedRequest.swift
//  TrollReverseLab
//
//  Packet capture data model for HTTP/HTTPS requests.
//  Stores method, URL, headers, body, response, and timing info.
//

import Foundation

/// Represents a captured HTTP/HTTPS request-response pair.
public struct CapturedRequest: Identifiable, Codable, Hashable {
    public let id: UUID
    public let method: String
    public let url: String
    public let host: String
    public let path: String
    public let requestHeaders: [String: String]
    public let requestBody: Data?
    public let responseStatus: Int
    public let responseHeaders: [String: String]
    public let responseBody: Data?
    public let timestamp: Date
    public let duration: TimeInterval
    public let isHTTPS: Bool
    public let contentType: String

    public init(
        id: UUID = UUID(),
        method: String,
        url: String,
        host: String,
        path: String,
        requestHeaders: [String: String] = [:],
        requestBody: Data? = nil,
        responseStatus: Int = 0,
        responseHeaders: [String: String] = [:],
        responseBody: Data? = nil,
        timestamp: Date = Date(),
        duration: TimeInterval = 0,
        isHTTPS: Bool = false,
        contentType: String = ""
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.host = host
        self.path = path
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseStatus = responseStatus
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.timestamp = timestamp
        self.duration = duration
        self.isHTTPS = isHTTPS
        self.contentType = contentType
    }

    // MARK: - Convenience

    public var statusText: String {
        switch responseStatus {
        case 0: return "Tunnel"
        case 200..<300: return "OK"
        case 300..<400: return "Redirect"
        case 400..<500: return "Client Error"
        case 500..<600: return "Server Error"
        default: return "Unknown"
        }
    }

    public var requestSize: Int {
        let headerSize = requestHeaders.reduce(0) { $0 + $1.key.count + $1.value.count + 4 }
        return headerSize + (requestBody?.count ?? 0)
    }

    public var responseSize: Int {
        let headerSize = responseHeaders.reduce(0) { $0 + $1.key.count + $1.value.count + 4 }
        return headerSize + (responseBody?.count ?? 0)
    }

    public var requestBodyString: String {
        guard let body = requestBody, !body.isEmpty else { return "" }
        return String(data: body, encoding: .utf8) ?? "(binary \(body.count) bytes)"
    }

    public var responseBodyString: String {
        guard let body = responseBody, !body.isEmpty else { return "" }
        return String(data: body, encoding: .utf8) ?? "(binary \(body.count) bytes)"
    }

    public var formattedHeaders: String {
        var lines: [String] = []
        for (key, value) in requestHeaders.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }
        return lines.joined(separator: "\n")
    }

    public var formattedResponseHeaders: String {
        var lines: [String] = []
        for (key, value) in responseHeaders.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }
        return lines.joined(separator: "\n")
    }

    /// Summarises this request as a compact string suitable for AI context.
    public var aiSummary: String {
        var summary = "[\(method)] \(isHTTPS ? "HTTPS" : "HTTP") \(host)\(path) -> \(responseStatus)"
        if !contentType.isEmpty {
            summary += " (\(contentType))"
        }
        if let body = requestBody, !body.isEmpty {
            let preview = String(data: body, encoding: .utf8)?
                .prefix(200)
                .replacingOccurrences(of: "\n", with: " ")
            if let preview = preview {
                summary += "\n  Request body: \(preview)"
            }
        }
        if let body = responseBody, !body.isEmpty {
            let preview = String(data: body, encoding: .utf8)?
                .prefix(200)
                .replacingOccurrences(of: "\n", with: " ")
            if let preview = preview {
                summary += "\n  Response body: \(preview)"
            }
        }
        return summary
    }
}
