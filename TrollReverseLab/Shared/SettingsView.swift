//
//  SettingsView.swift
//  TrollReverseLab
//
//  Settings screen for LLM API configuration, script management,
//  and tool information.
//

import Foundation
import SwiftUI

struct SettingsView: View {
    @AppStorage("llm_api_base_url") private var apiBaseURL = "https://api.openai.com/v1"
    @AppStorage("llm_api_key") private var apiKey = ""
    @AppStorage("llm_model") private var model = "gpt-4o"
    @AppStorage("llm_temperature") private var temperature = 0.3
    @AppStorage("frida_gadget_mode") private var gadgetMode = "interactive"
    @AppStorage("show_hex_offsets") private var showHexOffsets = true
    @AppStorage("max_hex_bytes") private var maxHexBytes = 65536

    var body: some View {
        NavigationView {
            Form {
                // MARK: - LLM API Configuration
                Section(header: Text("AI 模型配置"), footer: Text("配置 OpenAI 兼容 API 用于生成逆向学习脚本")) {
                    TextField("API Base URL", text: $apiBaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)

                    SecureField("API Key", text: $apiKey)
                        .autocapitalization(.none)

                    TextField("Model", text: $model)
                        .autocapitalization(.none)

                    HStack {
                        Text("Temperature")
                        Spacer()
                        Slider(value: $temperature, in: 0...1, step: 0.1)
                            .frame(width: 120)
                        Text(String(format: "%.1f", temperature))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }

                // MARK: - Frida Configuration
                Section(header: Text("Frida 调试配置")) {
                    Picker("Gadget 模式", selection: $gadgetMode) {
                        Text("交互模式").tag("interactive")
                        Text("脚本模式").tag("script")
                    }
                }

                // MARK: - File Viewer Configuration
                Section(header: Text("文件查看器配置")) {
                    Toggle("显示 Hex 偏移量", isOn: $showHexOffsets)

                    HStack {
                        Text("Hex 最大显示字节")
                        Spacer()
                        TextField("", text: Binding(
                            get: { String(maxHexBytes) },
                            set: { maxHexBytes = Int($0) ?? 65536 }
                        ))
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // MARK: - About
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }

                    HStack {
                        Text("适用系统")
                        Spacer()
                        Text("iOS 14 ~ 16.6.1, 17.0").foregroundColor(.secondary)
                    }

                    HStack {
                        Text("安装方式")
                        Spacer()
                        Text("TrollStore").foregroundColor(.secondary)
                    }

                    Text("TrollAIBio 逆向 是一款 iOS 本地逆向学习工具，仅用于个人技术研究与学习。严禁用于内购绕过、支付欺诈、联机作弊及商业破解用途。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}
