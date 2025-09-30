//
//  CustomWebhookService.swift
//  MAA
//
//  Created by RainYang on 2025/8/30.
//

import Foundation

@MainActor
class CustomWebhookService: NotificationService {
    /// 用于记录连续发送失败的次数。
    private var consecutiveFailureCount = 0
    /// 连续失败多少次后自动禁用功能。
    private let failureThreshold = 3

    /// 异步发送格式化后的日志。
    /// - Returns: 如果发送失败且需要重试，则返回原始的日志数组；如果发送成功或无需重试，则返回 `nil`。
    func send(logs: [MAALog], using config: NotificationConfig, viewModel: MAAViewModel) async -> [MAALog]? {
        let settings = config.customWebhook
        guard let url = URL(string: settings.url) else {
            viewModel.logError("自定义 Webhook URL 无效。")
            return nil // 配置错误，不重试
        }

        do {
            var request = URLRequest(url: url)
            // 默认使用 POST 和 application/json，因为这是 Webhook 最常见的配置
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // 1. 准备所有可用的模板变量
            let title = (viewModel.notificationTriggers.sendAllLogsAfterFinish) ? "MAA 任务已全部完成" : "MAA 日志摘要 (\(logs.count)条)"
            let contentItems = logs.map { log -> String in
                let timeString = log.date.formatted(date: .omitted, time: .standard)
                // 为 JSON 字符串中的内容转义特殊字符
                let escapedContent = log.content
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                return "[\(timeString)] \(escapedContent)"
            }
            let content = contentItems.joined(separator: "\\n") // 在 JSON 中使用 \\n 表示换行
            
            let time = Date().formatted(date: .omitted, time: .standard)

            // 2. 使用用户在 UI 中提供的完整 bodyTemplate 替换所有变量
            var processedBody = settings.bodyTemplate
            processedBody = processedBody.replacingOccurrences(of: "{title}", with: title)
            processedBody = processedBody.replacingOccurrences(of: "{content}", with: content)
            processedBody = processedBody.replacingOccurrences(of: "{time}", with: time)
            
            request.httpBody = processedBody.data(using: .utf8)
            
            // 3. 发送网络请求
            viewModel.logInfo("准备发送自定义 Webhook...")
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                 let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw URLError(.badServerResponse, userInfo: ["statusCode": statusCode])
            }

            // 4. 处理成功响应
            viewModel.logInfo("自定义 Webhook 发送成功。")
            consecutiveFailureCount = 0
            return nil
            
        } catch {
            // 5. 处理失败响应，执行重试或禁用逻辑
            consecutiveFailureCount += 1
            viewModel.logError("发送自定义 Webhook 失败: \(error.localizedDescription)")
            
            if consecutiveFailureCount >= failureThreshold {
                viewModel.customWebhook.isEnabled = false
                viewModel.logError("自定义 Webhook 连续失败 \(consecutiveFailureCount) 次，已自动关闭。")
                return nil
            } else {
                viewModel.logWarn("自定义 Webhook 发送失败（第 \(consecutiveFailureCount) 次尝试），将在10s后重试。")
                return logs
            }
        }
    }
}
