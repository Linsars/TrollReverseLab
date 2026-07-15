//
//  PacketCaptureView.swift
//  TrollReverseLab
//
//  Packet capture UI — local HTTP/HTTPS proxy for traffic analysis.
//  Captures GET/POST requests with full headers and bodies for AI analysis.
//

import SwiftUI

/// Main packet capture view with start/stop, filtering, and request list.
struct PacketCaptureView: View {
    @EnvironmentObject var captureEngine: PacketCaptureEngine
    @EnvironmentObject var aiClient: AIScriptClient
    @State private var showAIAnalysis = false
    @State private var aiAnalysisResult = ""
    @State private var isAnalyzing = false
    @State private var analysisError: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Proxy control bar
                ProxyControlBar(
                    isCapturing: captureEngine.isCapturing,
                    port: captureEngine.proxyPort,
                    onToggle: {
                        if captureEngine.isCapturing {
                            captureEngine.stopCapture()
                            OperationLogger.shared.logInfo(module: "抓包", action: "停止抓包")
                        } else {
                            captureEngine.startCapture()
                            OperationLogger.shared.logInfo(module: "抓包", action: "启动抓包", detail: "端口 \(captureEngine.proxyPort)")
                        }
                    }
                )

                Divider()

                // Filter bar
                if !captureEngine.capturedRequests.isEmpty {
                    FilterBarView(
                        filterMethod: $captureEngine.filterMethod,
                        filterHost: $captureEngine.filterHost,
                        searchText: $captureEngine.searchText,
                        onClear: {
                            captureEngine.filterMethod = ""
                            captureEngine.filterHost = ""
                            captureEngine.searchText = ""
                        }
                    )
                    Divider()
                }

                // Content
                if captureEngine.isCapturing && captureEngine.capturedRequests.isEmpty {
                    CaptureEmptyState(isCapturing: true)
                } else if captureEngine.capturedRequests.isEmpty {
                    CaptureEmptyState(isCapturing: false)
                } else {
                    CaptureListView(captureEngine: captureEngine)
                }
            }
            .navigationTitle("抓包")
            .navigationBarItems(
                trailing: HStack {
                    if captureEngine.isCapturing {
                        Button {
                            captureEngine.stopCapture()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    if captureEngine.hasCapturedData {
                        Button {
                            analyzeTraffic()
                        } label: {
                            Image(systemName: isAnalyzing ? "sparkles" : "wand.and.stars")
                                .foregroundColor(.accentColor)
                        }
                        .disabled(isAnalyzing)
                    }
                    if !captureEngine.capturedRequests.isEmpty {
                        Menu {
                            Button {
                                captureEngine.clearCaptures()
                                OperationLogger.shared.logInfo(module: "抓包", action: "清除抓包数据")
                            } label: {
                                Label("清除所有", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            )
            .sheet(isPresented: $showAIAnalysis) {
                AIAnalysisSheet(
                    result: aiAnalysisResult,
                    error: analysisError,
                    isPresented: $showAIAnalysis
                )
            }
        }
    }

    private func analyzeTraffic() {
        guard !aiClient.config.apiKey.isEmpty else {
            analysisError = "请先在设置中配置 AI API Key"
            showAIAnalysis = true
            return
        }

        isAnalyzing = true
        analysisError = nil
        aiAnalysisResult = ""

        let trafficData = captureEngine.exportForAI(maxRequests: 30)

        Task {
            do {
                let result = try await aiClient.analyzeTraffic(trafficData: trafficData)
                await MainActor.run {
                    self.aiAnalysisResult = result
                    self.isAnalyzing = false
                    self.showAIAnalysis = true
                    OperationLogger.shared.logSuccess(module: "抓包", action: "AI流量分析", detail: "\(captureEngine.captureCount) 条请求")
                }
            } catch {
                await MainActor.run {
                    self.analysisError = error.localizedDescription
                    self.isAnalyzing = false
                    self.showAIAnalysis = true
                    OperationLogger.shared.logFailure(module: "抓包", action: "AI流量分析", detail: error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - AI Analysis Sheet

struct AIAnalysisSheet: View {
    let result: String
    let error: String?
    @Binding var isPresented: Bool
    @State private var copied = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let error = error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.red)
                        Text("分析失败")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if result.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("AI 正在分析流量数据...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(result)
                            .font(.system(.subheadline))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .modifier(SelectableTextModifier())
                    }

                    Button {
                        UIPasteboard.general.string = result
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "已复制" : "复制分析结果")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(16)
                }
            }
            .navigationTitle("AI 流量分析")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button {
                    isPresented = false
                } label: {
                    Text("完成")
                }
            )
        }
    }
}

// MARK: - Control Bar

struct ProxyControlBar: View {
    let isCapturing: Bool
    let port: UInt16
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCapturing ? "正在抓包" : "未启动")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isCapturing ? .green : .secondary)

                    Text("代理地址: 127.0.0.1:\(port)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: isCapturing ? "stop.fill" : "play.fill")
                        Text(isCapturing ? "停止" : "开始")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isCapturing ? Color.red : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }

            // Setup instructions
            if !isCapturing {
                Text("设置: 设置 → Wi-Fi → 当前网络 → 配置代理 → 手动 → 服务器 127.0.0.1 端口 \(port)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Filter Bar

struct FilterBarView: View {
    @Binding var filterMethod: String
    @Binding var filterHost: String
    @Binding var searchText: String
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Picker("", selection: $filterMethod) {
                    Text("全部").tag("")
                    Text("GET").tag("GET")
                    Text("POST").tag("POST")
                    Text("PUT").tag("PUT")
                    Text("DELETE").tag("DELETE")
                    Text("CONNECT").tag("CONNECT")
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)

                TextField("搜索 URL / 主机...", text: $searchText)
                    .font(.caption)

                if !filterMethod.isEmpty || !filterHost.isEmpty || !searchText.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Empty State

struct CaptureEmptyState: View {
    let isCapturing: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isCapturing ? "antenna.radiowaves.left.and.right" : "network")
                .font(.system(size: 48))
                .foregroundColor(isCapturing ? .green : .secondary)

            Text(isCapturing ? "等待流量..." : "未开始抓包")
                .font(.headline)

            Text(isCapturing
                 ? "代理已启动，请在目标应用中操作以产生网络请求"
                 : "点击「开始」启动本地代理，然后在 iOS 设置中配置 Wi-Fi 代理为 127.0.0.1:8888")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Capture List

struct CaptureListView: View {
    @ObservedObject var captureEngine: PacketCaptureEngine

    var body: some View {
        List(captureEngine.filteredRequests) { request in
            NavigationLink(destination: CapturedRequestDetailView(request: request)) {
                CaptureRowView(request: request)
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct CaptureRowView: View {
    let request: CapturedRequest

    var body: some View {
        HStack(spacing: 10) {
            // Method badge
            Text(request.method)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(methodColor)
                .cornerRadius(4)
                .frame(width: 56, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(request.host)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(request.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if request.responseStatus > 0 {
                        Text("\(request.responseStatus)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(statusColor)
                    }

                    if !request.contentType.isEmpty {
                        Text(request.contentType.prefix(30))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Text(String(format: "%.0fms", request.duration * 1000))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if request.isHTTPS {
                        Text("HTTPS")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTime(request.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if request.responseSize > 0 {
                    Text(formatSize(request.responseSize))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var methodColor: Color {
        switch request.method.uppercased() {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "CONNECT": return .purple
        default: return .gray
        }
    }

    private var statusColor: Color {
        switch request.responseStatus {
        case 0: return .secondary
        case 200..<300: return .green
        case 300..<400: return .orange
        case 400..<600: return .red
        default: return .secondary
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
        return String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Request Detail View

struct CapturedRequestDetailView: View {
    let request: CapturedRequest
    @State private var selectedSection = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // URL section
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(request.url)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                }

                // Summary
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(request.method, systemImage: "arrow.right.circle")
                            .font(.caption)
                        if request.responseStatus > 0 {
                            Text("→ \(request.responseStatus) \(request.statusText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.0fms", request.duration * 1000))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Request headers
                DetailSection(title: "请求头", content: request.formattedHeaders)

                // Request body
                if !request.requestBodyString.isEmpty {
                    DetailSection(title: "请求体", content: request.requestBodyString)
                }

                // Response headers
                if !request.responseHeaders.isEmpty {
                    DetailSection(title: "响应头", content: request.formattedResponseHeaders)
                }

                // Response body
                if !request.responseBodyString.isEmpty {
                    DetailSection(title: "响应体", content: request.responseBodyString)
                }
            }
            .padding(16)
        }
        .navigationTitle("请求详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DetailSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(content)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(6)
                .modifier(SelectableTextModifier())
        }
    }
}
