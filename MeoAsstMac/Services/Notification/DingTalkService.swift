//
//  DingTalkService.swift
//  MAA
//
//  Created by RainYang on 2025/8/30.
//

import Foundation

@MainActor
class DingTalkService: NotificationService {

    // 1. 将状态管理属性从旧的 Manager 移入此处
    /// 用于记录连续发送失败的次数。
    private var consecutiveFailureCount = 0
    /// 连续失败多少次后自动禁用功能。
    private let failureThreshold = 3

    func send(logs: [MAALog], using config: NotificationConfig, viewModel: MAAViewModel) async -> [MAALog]? {
        let botClient = DingTalkBotClient(
            webhookURL: config.dingTalkWebhook,
            secret: config.dingTalkSecret
        )

        let title = "MAA 日志摘要 (\(logs.count)条)"
        let contentItems = logs.map { log in
            let timeString = log.date.formatted(date: .omitted, time: .standard)
            let escapedContent = log.content.replacingOccurrences(of: "\"", with: "\\\"")
            return "- **[\(timeString)]** \(escapedContent)"
        }
        let fullContent = """
            ### MAA 日志摘要 (\(logs.count)条新消息)
            ---
            \(contentItems.joined(separator: "\n\n"))
            """

        do {
            if viewModel.showSendLogsInGUI {
                viewModel.logInfo("准备发送 DingTalk 日志摘要 (\(logs.count)条)...")
            }
            _ = try await botClient.sendMarkdownMessage(title: title, text: fullContent)
            if viewModel.showSendLogsInGUI {
                viewModel.logInfo("钉钉通知发送成功。")
            }

            // 2. 发送成功，重置失败计数器，并返回 nil 表示无需重试
            consecutiveFailureCount = 0
            return nil
        } catch {
            // 3. 发送失败，执行完整的重试或禁用逻辑
            consecutiveFailureCount += 1
            if viewModel.showSendLogsInGUI {
                viewModel.logError("发送钉钉通知摘要失败: \(error.localizedDescription)")
            }

            if consecutiveFailureCount >= failureThreshold {
                // 如果连续失败次数达到阈值
                viewModel.DingTalkBot = false  // 禁用功能
                if viewModel.showSendLogsInGUI {
                    viewModel.logError("钉钉通知连续失败 \(consecutiveFailureCount) 次，已自动关闭此功能。请检查网络和配置。")
                }
                // 返回 nil，表示任务结束，不要再重试了
                return nil
            } else {
                // 如果失败次数未达到阈值
                if viewModel.showSendLogsInGUI {
                    viewModel.logWarn("钉钉通知发送失败（第 \(consecutiveFailureCount) 次尝试），将在10s后重试。")
                }
                // 返回原始的日志数组，通知上层管理器需要将这些日志加回缓冲区
                return logs
            }
        }
    }
}
