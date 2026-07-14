//
//  ProxyServer.swift
//  TrollReverseLab
//
//  Local HTTP/HTTPS proxy server using Network.framework.
//  Captures HTTP requests (GET/POST/PUT/DELETE) with full headers and bodies.
//  For HTTPS, logs CONNECT metadata and tunnels encrypted traffic.
//
//  Usage:
//    1. Start the proxy (default port 8888)
//    2. Set iOS WiFi proxy to 127.0.0.1:8888
//    3. Use target app — traffic is captured automatically
//    4. Stop proxy when done
//

import Foundation
import Network

/// Local HTTP proxy server that captures traffic for AI analysis.
public final class ProxyServer {

    // MARK: - Properties

    private var listener: NWListener?
    private var connections: [ProxyConnection] = []
    private let connectionsLock = NSLock()
    private(set) var isRunning = false
    public let port: UInt16

    /// Called when a full HTTP request/response is captured.
    public var onCapturedRequest: ((CapturedRequest) -> Void)?
    /// Called for HTTPS CONNECT events (metadata only).
    public var onConnect: ((String, UInt16) -> Void)?
    /// Called for log messages.
    public var onLog: ((String) -> Void)?

    // MARK: - Init

    public init(port: UInt16 = 8888) {
        self.port = port
    }

    // MARK: - Start / Stop

    public func start() throws {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let portValue = NWEndpoint.Port(rawValue: port)
            ?? NWEndpoint.Port(rawValue: 8888)!

        listener = try NWListener(
            using: params,
            on: portValue
        )

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
                self?.onLog?("Proxy server started on port \(self?.port ?? 8888)")
            case .failed(let error):
                self?.isRunning = false
                self?.onLog?("Proxy server failed: \(error.localizedDescription)")
            case .cancelled:
                self?.isRunning = false
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    public func stop() {
        listener?.cancel()
        listener = nil

        connectionsLock.lock()
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        connectionsLock.unlock()

        isRunning = false
        onLog?("Proxy server stopped")
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        let handler = ProxyConnection(
            clientConnection: connection,
            onCapture: { [weak self] captured in
                self?.onCapturedRequest?(captured)
            },
            onConnect: { [weak self] host, port in
                self?.onConnect?(host, port)
            },
            onLog: { [weak self] msg in
                self?.onLog?(msg)
            },
            onComplete: { [weak self] handler in
                self?.removeConnection(handler)
            }
        )

        connectionsLock.lock()
        connections.append(handler)
        connectionsLock.unlock()

        handler.start()
    }

    private func removeConnection(_ connection: ProxyConnection) {
        connectionsLock.lock()
        connections.removeAll { $0 === connection }
        connectionsLock.unlock()
    }
}

// MARK: - Proxy Connection Handler

/// Handles a single client-proxy connection lifecycle.
private final class ProxyConnection {

    let clientConnection: NWConnection
    var serverConnection: NWConnection?

    private let onCapture: (CapturedRequest) -> Void
    private let onConnect: (String, UInt16) -> Void
    private let onLog: (String) -> Void
    private let onComplete: (ProxyConnection) -> Void

    // Request parsing state
    private var receiveBuffer = Data()
    private var method = ""
    private var rawUrl = ""
    private var host = ""
    private var port: UInt16 = 80
    private var path = "/"
    private var requestHeaders: [String: String] = [:]
    private var requestBody = Data()
    private var contentLength = 0
    private var isHTTPS = false
    private var isConnect = false
    private var startTime = Date()
    private var responseStatus = 0
    private var responseHeaders: [String: String] = [:]
    private var responseBody = Data()
    private var responseContentLength = -1
    private var headerEndIndex: Range<Data.Index>?

    private let maxBufferSize = 10 * 1024 * 1024 // 10 MB safety limit

    init(
        clientConnection: NWConnection,
        onCapture: @escaping (CapturedRequest) -> Void,
        onConnect: @escaping (String, UInt16) -> Void,
        onLog: @escaping (String) -> Void,
        onComplete: @escaping (ProxyConnection) -> Void
    ) {
        self.clientConnection = clientConnection
        self.onCapture = onCapture
        self.onConnect = onConnect
        self.onLog = onLog
        self.onComplete = onComplete
    }

    func start() {
        startTime = Date()
        clientConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                self?.onLog("Client connection failed: \(error.localizedDescription)")
                self?.finish()
            case .cancelled:
                self?.finish()
            default:
                break
            }
        }
        readInitialData()
    }

    func cancel() {
        clientConnection.cancel()
        serverConnection?.cancel()
    }

    // MARK: - Read Initial Request

    private func readInitialData() {
        clientConnection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.onLog("Receive error: \(error.localizedDescription)")
                self.finish()
                return
            }

            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }

            if isComplete {
                self.finish()
                return
            }

            // Continue reading if we haven't finished parsing
            if !self.isConnect && self.method.isEmpty {
                self.readInitialData()
            }
        }
    }

    // MARK: - Process Received Buffer

    private func processBuffer() {
        if isConnect {
            // Already tunneling, ignore
            return
        }

        // Try to find end of headers (\r\n\r\n)
        guard let headerEnd = findHeaderEnd() else {
            // Headers not complete yet, keep reading
            if receiveBuffer.count < maxBufferSize {
                readInitialData()
            } else {
                onLog("Buffer overflow, closing connection")
                finish()
            }
            return
        }

        // Parse headers
        let headerData = receiveBuffer.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            finish()
            return
        }

        if !parseRequestLine(from: headerString) {
            finish()
            return
        }

        parseHeaders(from: headerString)

        // Body starts after \r\n\r\n
        let bodyStart = receiveBuffer.index(headerEnd.upperBound, offsetBy: 0)
        if bodyStart < receiveBuffer.count {
            requestBody = receiveBuffer.subdata(in: bodyStart..<receiveBuffer.count)
        }

        if isConnect {
            handleConnect()
        } else {
            // Check if we have the full body
            contentLength = Int(requestHeaders["Content-Length"] ?? requestHeaders["content-length"] ?? "0") ?? 0
            if requestBody.count >= contentLength {
                // Full request received, forward it
                forwardRequest()
            } else {
                // Need more body data
                readRequestBody()
            }
        }
    }

    // MARK: - HTTP Request Parsing

    private func findHeaderEnd() -> Range<Data.Index>? {
        let pattern: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
        if receiveBuffer.count < 4 { return nil }

        for i in 0..<(receiveBuffer.count - 3) {
            if receiveBuffer[i] == pattern[0] &&
               receiveBuffer[i+1] == pattern[1] &&
               receiveBuffer[i+2] == pattern[2] &&
               receiveBuffer[i+3] == pattern[3] {
                return i..<(i + 4)
            }
        }
        return nil
    }

    private func parseRequestLine(from headerString: String) -> Bool {
        guard let firstLine = headerString.components(separatedBy: "\r\n").first else {
            return false
        }

        let parts = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return false }

        method = String(parts[0])
        rawUrl = String(parts[1])

        if method.uppercased() == "CONNECT" {
            isConnect = true
            isHTTPS = true
            // Parse host:port from CONNECT url
            if let colonIndex = rawUrl.lastIndex(of: ":") {
                host = String(rawUrl[rawUrl.startIndex..<colonIndex])
                port = UInt16(rawUrl[rawUrl.index(after: colonIndex)...]) ?? 443
            } else {
                host = rawUrl
                port = 443
            }
            path = ""
        } else {
            // Parse absolute URL (http://host:port/path) or origin-form (/path)
            if rawUrl.hasPrefix("http://") || rawUrl.hasPrefix("https://") {
                isHTTPS = rawUrl.hasPrefix("https://")
                if let url = URL(string: rawUrl) {
                    host = url.host ?? ""
                    port = UInt16(url.port ?? (isHTTPS ? 443 : 80)) ?? (isHTTPS ? 443 : 80)
                    path = url.path.isEmpty ? "/" : url.path
                    if let query = url.query, !query.isEmpty {
                        path += "?\(query)"
                    }
                }
            } else {
                // Origin form: /path — get host from Host header (parsed later)
                path = rawUrl
            }
        }

        return true
    }

    private func parseHeaders(from headerString: String) {
        let lines = headerString.components(separatedBy: "\r\n")
        // Skip first line (request line)
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                requestHeaders[key] = value
            }
        }

        // If host wasn't set from URL, get it from Host header
        if host.isEmpty {
            host = requestHeaders["Host"] ?? requestHeaders["host"] ?? ""
            if !host.isEmpty {
                // Parse port from host header if present
                if let colonIndex = host.lastIndex(of: ":") {
                    let hostPart = String(host[host.startIndex..<colonIndex])
                    let portPart = String(host[host.index(after: colonIndex)...])
                    if let p = UInt16(portPart) {
                        port = p
                        host = hostPart
                    }
                }
            }
        }
    }

    // MARK: - Read Request Body

    private func readRequestBody() {
        clientConnection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.requestBody.append(data)
            }

            if self.requestBody.count >= self.contentLength || isComplete || error != nil {
                self.forwardRequest()
            } else {
                self.readRequestBody()
            }
        }
    }

    // MARK: - Forward HTTP Request

    private func forwardRequest() {
        guard !host.isEmpty else {
            onLog("No host to forward to")
            finish()
            return
        }

        let serverHost = NWEndpoint.Host(host)
        let serverPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 80)!

        serverConnection = NWConnection(host: serverHost, port: serverPort, using: .tcp)

        serverConnection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendRequestToServer()
            case .failed(let error):
                self?.onLog("Server connection failed: \(error.localizedDescription)")
                self?.finish()
            case .cancelled:
                self?.finish()
            default:
                break
            }
        }

        serverConnection?.start(queue: .global(qos: .userInitiated))
    }

    private func sendRequestToServer() {
        // Rebuild the request in origin form for the destination server
        var requestString = "\(method) \(path) HTTP/1.1\r\n"
        for (key, value) in requestHeaders {
            requestString += "\(key): \(value)\r\n"
        }
        requestString += "\r\n"

        var requestData = Data(requestString.utf8)
        requestData.append(requestBody)

        serverConnection?.send(
            content: requestData,
            completion: .contentProcessed { [weak self] error in
                if let error = error {
                    self?.onLog("Send to server failed: \(error.localizedDescription)")
                    self?.finish()
                } else {
                    self?.readResponseHeaders()
                }
            }
        )
    }

    // MARK: - Read Response

    private var responseBuffer = Data()

    private func readResponseHeaders() {
        serverConnection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.responseBuffer.append(data)
            }

            // Try to parse response headers
            if let headerEnd = self.findResponseHeaderEnd() {
                let headerData = self.responseBuffer.subdata(in: 0..<headerEnd.lowerBound)
                self.parseResponseHeaders(from: headerData)

                let bodyStart = headerEnd.upperBound
                if bodyStart < self.responseBuffer.count {
                    self.responseBody = self.responseBuffer.subdata(in: bodyStart..<self.responseBuffer.count)
                }

                // Forward all received data to client
                self.clientConnection.send(
                    content: self.responseBuffer,
                    completion: .contentProcessed { _ in }
                )

                // Check if we have the full response body
                self.responseContentLength = Int(
                    self.responseHeaders["Content-Length"] ??
                    self.responseHeaders["content-length"] ?? "-1"
                ) ?? -1

                if self.responseContentLength >= 0 && self.responseBody.count >= self.responseContentLength {
                    // Full response received
                    self.captureAndFinish()
                } else if isComplete || error != nil {
                    self.captureAndFinish()
                } else {
                    self.readResponseBody()
                }
            } else if isComplete || error != nil {
                self.finish()
            } else {
                self.readResponseHeaders()
            }
        }
    }

    private func readResponseBody() {
        serverConnection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.responseBody.append(data)
                // Forward to client
                self.clientConnection.send(content: data, completion: .contentProcessed { _ in })
            }

            if self.responseContentLength >= 0 && self.responseBody.count >= self.responseContentLength {
                self.captureAndFinish()
            } else if isComplete || error != nil {
                self.captureAndFinish()
            } else {
                self.readResponseBody()
            }
        }
    }

    private func findResponseHeaderEnd() -> Range<Data.Index>? {
        let pattern: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        if responseBuffer.count < 4 { return nil }

        for i in 0..<(responseBuffer.count - 3) {
            if responseBuffer[i] == pattern[0] &&
               responseBuffer[i+1] == pattern[1] &&
               responseBuffer[i+2] == pattern[2] &&
               responseBuffer[i+3] == pattern[3] {
                return i..<(i + 4)
            }
        }
        return nil
    }

    private func parseResponseHeaders(from data: Data) {
        guard let headerString = String(data: data, encoding: .utf8) else { return }
        let lines = headerString.components(separatedBy: "\r\n")

        // Parse status line: HTTP/1.1 200 OK
        if let firstLine = lines.first {
            let parts = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 2 {
                responseStatus = Int(parts[1]) ?? 0
            }
        }

        // Parse headers
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                responseHeaders[key] = value
            }
        }
    }

    // MARK: - HTTPS CONNECT Handling

    private func handleConnect() {
        // Log the CONNECT
        onConnect(host, port)

        // Respond to client with 200
        let response = "HTTP/1.1 200 Connection Established\r\n\r\n"
        clientConnection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { [weak self] error in
                if let error = error {
                    self?.onLog("CONNECT response send failed: \(error.localizedDescription)")
                    self?.finish()
                    return
                }

                // Record metadata capture
                let captured = CapturedRequest(
                    method: "CONNECT",
                    url: "\(self.host):\(self.port)",
                    host: self.host,
                    path: "",
                    requestHeaders: self.requestHeaders,
                    requestBody: nil,
                    responseStatus: 0,
                    responseHeaders: [:],
                    responseBody: nil,
                    timestamp: self.startTime,
                    duration: Date().timeIntervalSince(self.startTime),
                    isHTTPS: true,
                    contentType: ""
                )
                self.onCapture(captured)

                // Start tunneling
                self?.startTunnel()
            }
        )
    }

    private func startTunnel() {
        guard !host.isEmpty else {
            finish()
            return
        }

        let serverHost = NWEndpoint.Host(host)
        let serverPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 443)!

        serverConnection = NWConnection(host: serverHost, port: serverPort, using: .tcp)

        serverConnection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.tunnelData()
            case .failed:
                self?.finish()
            case .cancelled:
                self?.finish()
            default:
                break
            }
        }

        serverConnection?.start(queue: .global(qos: .userInitiated))
    }

    private func tunnelData() {
        // Forward client -> server
        clientConnection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.serverConnection?.send(content: data, completion: .contentProcessed { _ in })
            }

            if isComplete || error != nil {
                self.finish()
                return
            }

            self.tunnelData()
        }

        // Forward server -> client
        serverConnection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.clientConnection.send(content: data, completion: .contentProcessed { _ in })
            }

            if isComplete || error != nil {
                self.finish()
                return
            }

            self.tunnelData()
        }
    }

    // MARK: - Capture & Finish

    private func captureAndFinish() {
        let contentType = responseHeaders["Content-Type"]
            ?? responseHeaders["content-type"] ?? ""

        // Truncate large response bodies for storage
        let maxBodySize = 512 * 1024 // 512 KB
        var storedBody = responseBody
        if storedBody.count > maxBodySize {
            storedBody = storedBody.subdata(in: 0..<maxBodySize)
        }

        let captured = CapturedRequest(
            method: method,
            url: isHTTPS ? "https://\(host)\(path)" : "http://\(host)\(path)",
            host: host,
            path: path,
            requestHeaders: requestHeaders,
            requestBody: requestBody.isEmpty ? nil : requestBody,
            responseStatus: responseStatus,
            responseHeaders: responseHeaders,
            responseBody: storedBody.isEmpty ? nil : storedBody,
            timestamp: startTime,
            duration: Date().timeIntervalSince(startTime),
            isHTTPS: isHTTPS,
            contentType: contentType
        )

        onCapture(captured)
        finish()
    }

    private func finish() {
        clientConnection.cancel()
        serverConnection?.cancel()
        onComplete(self)
    }
}
