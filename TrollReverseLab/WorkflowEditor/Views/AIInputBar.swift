import SwiftUI

// MARK: - AI Input Bar

struct AIInputBar: View {
    @ObservedObject var engine: WorkflowEngine
    @State private var inputText: String = ""
    @State private var showSuggestions: Bool = false

    private let suggestions: [String] = [
        "读取相册全部竖屏视频，自动打开剪映新建草稿，统一加字幕，导出到新相册，记录清单到备忘录",
        "抓包分析微信网络请求，提取API接口，生成Frida hook脚本",
        "读取备忘录所有笔记，AI分类整理后写入文件",
        "监控目标App内存变化，检测异常数据写入",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Suggestions
            if showSuggestions {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(action: {
                                inputText = suggestion
                                showSuggestions = false
                            }) {
                                Text(suggestion)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.white.opacity(0.1)))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // AI Messages (compact)
            if !engine.aiMessages.isEmpty {
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(engine.aiMessages.suffix(5), id: \.self) { msg in
                                Text(msg)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white.opacity(0.05)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            // Input row
            HStack(spacing: 12) {
                // Suggestions toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSuggestions.toggle()
                    }
                }) {
                    Image(systemName: showSuggestions ? "lightbulb.fill" : "lightbulb")
                        .font(.system(size: 18))
                        .foregroundColor(showSuggestions ? .yellow : .white.opacity(0.5))
                }

                // Text field
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)

                    TextField("描述你想要的自动化流程...", text: $inputText)
                        .font(.system(size: 14))
                        .foregroundColor(.white)

                    if !inputText.isEmpty {
                        Button(action: { inputText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1)))
                )

                // Generate button
                Button(action: generateWorkflow) {
                    Image(systemName: engine.isGenerating ? "" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                        .scaleEffect(engine.isGenerating ? 1.0 : 1.0)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || engine.isGenerating)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.95),
                        Color.black.opacity(0.85)
                    ]),
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    private func generateWorkflow() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        engine.generateWorkflow(from: text)
        inputText = ""
        showSuggestions = false
    }
}
