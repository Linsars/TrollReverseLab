import Foundation

// MARK: - Workflow Prompt Builder

struct WorkflowPromptBuilder {

    static func systemPrompt() -> String {
        return """
        你是一个 iOS 自动化工作流设计专家。用户会用自然语言描述需求，你需要将其转化为一个可视化节点工作流的 JSON 结构。

        ## 可用节点模板

        每个节点有一个 templateId，以下是所有可用模板：

        ### 蓝色 - App操控 (appControl)
        - app.open: 打开应用 (参数: bundleId)
        - app.tap: 点击坐标 (参数: x, y, delay)
        - app.swipe: 滑动 (参数: x1, y1, x2, y2, duration)
        - app.input: 输入文本 (参数: text)
        - app.wait: 等待 (参数: seconds)
        - app.screenshot: 截图
        - app.readDraft: 读取草稿 (参数: app, draftPath)

        ### 紫色 - AI逻辑 (aiLogic)
        - logic.if: 条件判断 (参数: condition, variable) → 输出: 真/假
        - logic.loop: 循环 (参数: count, mode) → 输出: 循环体/完成
        - logic.variable: 设置变量 (参数: name, value)
        - logic.aiAnalysis: AI分析 (参数: prompt, model)
        - logic.counter: 计数器 (参数: start, step)
        - logic.retry: 失败重试 (参数: maxRetries, delay)

        ### 绿色 - 文件/数据 (fileData)
        - file.readPhotos: 读取相册 (参数: filter[vertical/horizontal/all], limit, sort)
        - file.writePhotos: 保存到相册 (参数: album)
        - file.writeNote: 写入备忘录 (参数: title, folder)
        - file.readFile: 读取文件 (参数: path, encoding)
        - file.writeFile: 写入文件 (参数: path, mode)
        - file.sandboxRead: 沙盒读取 (参数: bundleId, path)
        - file.sandboxWrite: 沙盒写入 (参数: bundleId, path)

        ### 橙色 - 网络 (network)
        - net.http: HTTP请求 (参数: method, url, headers, body)
        - net.captureFilter: 抓包过滤 (参数: host, method)
        - net.apiCall: API调用 (参数: endpoint, method, auth)

        ### 红色 - 高风险 (highRisk)
        - risk.memRead: 内存读取 (参数: address, size, pid)
        - risk.memWrite: 内存写入 (参数: address, data, pid)
        - risk.fridaInject: Frida注入 (参数: script, pid, spawn)
        - risk.processAttach: 进程附加 (参数: pid, name)

        ## 输出格式

        你必须输出以下 JSON 格式（不要输出其他内容）：

        ```json
        {
          "nodes": [
            {
              "nodeId": "node_1",
              "templateId": "file.readPhotos",
              "title": "读取相册竖屏视频",
              "category": "fileData",
              "icon": "photo.on.rectangle",
              "note": "筛选9:16比例的竖屏视频",
              "riskLevel": "low",
              "parameters": {
                "filter": "vertical",
                "limit": "100",
                "sort": "newest"
              }
            }
          ],
          "connections": [
            {"from": "node_1", "fromPort": 0, "to": "node_2", "toPort": 0}
          ]
        }
        ```

        ## 设计规则

        1. 根据用户需求，设计完整的工作流，包含所有必要步骤
        2. 自动补充弹窗拦截(app.wait + app.tap)、导出等待(app.wait)、失败重试(logic.retry)分支
        3. 每个节点的 note 字段用中文简短描述该步骤的目的
        4. 如果涉及高风险操作(内存/注入)，设置 riskLevel 为 "high" 或 "critical"
        5. 连接关系要合理：前一步的输出连到下一步的输入
        6. 条件判断节点有两个输出端口(真/假)，分别连接不同的后续节点
        7. 循环节点有两个输出端口(循环体/完成)
        8. 不得生成违反法律法规的节点，如破解支付、绕过验证等
        9. nodeId 从 "node_1" 开始递增
        10. 只输出 JSON，不要输出解释文字
        """
    }

    static func userPrompt(
        input: String,
        trafficContext: String? = nil,
        targetAppName: String? = nil,
        targetAppBundleId: String? = nil
    ) -> String {
        var prompt = "用户需求: \(input)\n\n"

        if let appName = targetAppName, let bundleId = targetAppBundleId {
            prompt += "目标应用: \(appName) (bundleId: \(bundleId))\n"
        }

        if let traffic = trafficContext, !traffic.isEmpty {
            prompt += """
            抓包数据上下文 (可用于分析API请求格式):
            \(traffic)

            """
        }

        prompt += """
        请根据以上需求设计完整的工作流节点链路。确保：
        1. 包含所有必要步骤
        2. 自动补充异常处理和重试逻辑
        3. 高风险操作需要明确标注
        4. 输出标准 JSON 格式
        """

        return prompt
    }
}
