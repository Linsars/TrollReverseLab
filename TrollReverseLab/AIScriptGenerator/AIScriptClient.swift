//
//  AIScriptClient.swift
//  TrollReverseLab
//
//  Module 3: AI-assisted reverse engineering script generation.
//  Connects to OpenAI-compatible LLM APIs to generate Frida/Lua debug
//  scripts from natural language descriptions.
//
//  CONSTRAINT: System prompt enforces local-only research scripts.
//  No payment bypass, no global tampering, no online cheating code generation.
//

import Foundation
import SwiftUI

/// Represents a chat message for the LLM API.
public struct ChatMessage: Codable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Configuration for the LLM API client.
public struct LLMConfig: Codable {
    public var apiBaseURL: String
    public var apiKey: String
    public var model: String
    public var temperature: Double
    public var maxTokens: Int

    public init(
        apiBaseURL: String = "https://api.openai.com/v1",
        apiKey: String = "",
        model: String = "gpt-4o",
        temperature: Double = 0.3,
        maxTokens: Int = 4096
    ) {
        self.apiBaseURL = apiBaseURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

/// Client for OpenAI-compatible LLM API to generate reverse engineering scripts.
public final class AIScriptClient: ObservableObject {

    @Published public var config: LLMConfig
    @Published public var conversationHistory: [ChatMessage] = []
    @Published public var isGenerating = false
    @Published public var generatedScripts: [GeneratedScript] = []
    @Published public var lastError: String?

    private let session = URLSession.shared

    public init(config: LLMConfig = LLMConfig()) {
        self.config = config
        // Initialize conversation with system prompt
        conversationHistory.append(ChatMessage(role: "system", content: SystemPrompt.constraints))
    }

    // MARK: - Script Generation

    /// Generates a Frida/Lua debug script from a natural language description.
    /// - Parameter description: Natural language description of what to analyze
    /// - Parameter scriptType: Type of script to generate (Frida JS or Lua)
    /// - Parameter appContext: Context about the target app for better generation
    /// - Parameter targetApp: Optional selected TrollStore app for app-specific scripts
    /// - Parameter trafficContext: Optional captured network traffic data for AI analysis
    public func generateScript(
        description: String,
        scriptType: ScriptType,
        appContext: String? = nil,
        targetApp: TrollStoreApp? = nil,
        trafficContext: String? = nil
    ) async throws -> GeneratedScript {

        guard !config.apiKey.isEmpty else {
            throw AIScriptError.missingAPIKey
        }

        isGenerating = true
        defer { isGenerating = false }

        let userPrompt = buildUserPrompt(
            description: description,
            scriptType: scriptType,
            appContext: appContext,
            targetApp: targetApp,
            trafficContext: trafficContext
        )

        let userMessage = ChatMessage(role: "user", content: userPrompt)
        conversationHistory.append(userMessage)

        let response = try await callChatAPI(messages: conversationHistory)

        let assistantMessage = ChatMessage(role: "assistant", content: response)
        conversationHistory.append(assistantMessage)

        // Extract code block from response
        let script = extractCodeBlock(from: response) ?? response

        let generated = GeneratedScript(
            description: description,
            scriptType: scriptType,
            code: script,
            fullResponse: response,
            timestamp: Date()
        )

        await MainActor.run {
            generatedScripts.append(generated)
        }

        return generated
    }

    // MARK: - API Communication

    /// Calls the OpenAI-compatible chat completions API.
    private func callChatAPI(messages: [ChatMessage]) async throws -> String {
        guard let url = URL(string: "\(config.apiBaseURL)/chat/completions") else {
            throw AIScriptError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIScriptError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIScriptError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse OpenAI response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIScriptError.invalidResponse
        }

        return content
    }

    // MARK: - Prompt Building

    private func buildUserPrompt(description: String, scriptType: ScriptType, appContext: String?, targetApp: TrollStoreApp?, trafficContext: String?) -> String {
        var prompt = """
        Please generate a \(scriptType.displayName) script for the following local reverse engineering research task:

        Task: \(description)

        """
        if let context = appContext {
            prompt += "Additional context: \(context)\n\n"
        }
        if let app = targetApp {
            prompt += """
            Target TrollStore app:
            - Display name: \(app.displayName)
            - Bundle ID: \(app.bundleIdentifier)
            - Version: \(app.version)
            - Bundle path: \(app.bundlePath)
            - Data container: \(app.dataContainerPath)

            """
        }
        if let traffic = trafficContext {
            prompt += """
            Captured network traffic (from local proxy capture):
            \(traffic)

            Use this traffic data to understand the app's API patterns, request formats, and data structures.
            Focus on how the app stores and retrieves data locally based on the observed network behavior.

            """
        }
        prompt += """
        Requirements:
        1. The script must be for LOCAL research only — reading local data, tracing local functions, analyzing local data structures.
        2. Include clear comments explaining each section.
        3. Use send() to output results for analysis.
        4. Handle errors gracefully with try-catch or null checks.
        5. Do NOT include any code that modifies online verification, payment systems, or network-validated logic.

        Script type: \(scriptType.rawValue)
        """
        return prompt
    }

    // MARK: - Workflow Generation

    /// Generates a visual workflow (node graph) from natural language.
    /// Uses a dedicated system prompt that instructs the LLM to output JSON.
    public func generateWorkflow(
        userInput: String,
        trafficContext: String? = nil,
        targetAppName: String? = nil,
        targetAppBundleId: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard !config.apiKey.isEmpty else {
            completion(.failure(AIScriptError.missingAPIKey))
            return
        }

        let systemPrompt = WorkflowPromptBuilder.systemPrompt()
        let userPrompt = WorkflowPromptBuilder.userPrompt(
            input: userInput,
            trafficContext: trafficContext,
            targetAppName: targetAppName,
            targetAppBundleId: targetAppBundleId
        )

        let messages: [ChatMessage] = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userPrompt)
        ]

        // Use a background task for the API call
        Task {
            do {
                let response = try await callChatAPI(messages: messages)
                await MainActor.run {
                    completion(.success(response))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Utilities

    /// Extracts code block from markdown-formatted LLM response.
    private func extractCodeBlock(from text: String) -> String? {
        // Match ```javascript or ```lua or ``` code blocks
        let pattern = #"```(?:javascript|lua|js)?\n([\s\S]+?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           let codeRange = Range(match.range(at: 1), in: text) {
            return String(text[codeRange])
        }
        return nil
    }

    /// Resets the conversation history while keeping the system prompt.
    public func resetConversation() {
        conversationHistory = [ChatMessage(role: "system", content: SystemPrompt.constraints)]
    }

    /// Saves a generated script to the local scripts directory.
    public func saveScript(_ script: GeneratedScript) -> Bool {
        let scriptsDir = getScriptsDirectory()
        let filePath = (scriptsDir as NSString).appendingPathComponent(script.filename)

        do {
            try script.code.write(toFile: filePath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private func getScriptsDirectory() -> String {
        let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        let scriptsDir = (docsDir as NSString).appendingPathComponent("GeneratedScripts")
        try? FileManager.default.createDirectory(atPath: scriptsDir, withIntermediateDirectories: true)
        return scriptsDir
    }
}

// MARK: - Supporting Types

public enum ScriptType: String, CaseIterable {
    case fridaJS = "frida-js"
    case lua = "lua"

    public var displayName: String {
        switch self {
        case .fridaJS: return "Frida JavaScript"
        case .lua: return "Lua"
        }
    }

    public var fileExtension: String {
        switch self {
        case .fridaJS: return "js"
        case .lua: return "lua"
        }
    }
}

public struct GeneratedScript: Identifiable {
    public let id = UUID()
    public let description: String
    public let scriptType: ScriptType
    public let code: String
    public let fullResponse: String
    public let timestamp: Date

    public var filename: String {
        let safeName = description
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-zA-Z0-9_]", with: "", options: .regularExpression)
            .prefix(40)
        return "\(safeName).\(scriptType.fileExtension)"
    }
}

public enum AIScriptError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is not configured. Set it in Settings."
        case .invalidURL:
            return "Invalid API URL configuration."
        case .invalidResponse:
            return "Received invalid response from the API."
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        }
    }
}
