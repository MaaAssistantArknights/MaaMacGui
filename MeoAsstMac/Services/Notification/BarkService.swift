//
//  BarkService.swift
//  MAA
//
//  Created by RainYang on 2025/8/30.
//

import Foundation

/// Bark 通知服务，实现了 NotificationService 协议。
///
/// 这个类包含了发送 Bark 通知的具体逻辑，并内置了独立的失败重试和自动禁用机制。
@MainActor
class BarkService: NotificationService {

    /// 用于记录连续发送失败的次数。
    private var consecutiveFailureCount = 0
    /// 连续失败多少次后自动禁用功能。
    private let failureThreshold = 3
    /// 所有发送失败日志的缓冲区。
    private var faillogBuffer: [MAALog] = []

    /// 发送 Bark 通知。
    /// - Returns: 如果发送失败且需要重试，则返回原始的日志数组；否则返回 `nil`。
    func send(logs: [MAALog], using config: NotificationConfig, viewModel: MAAViewModel) async -> [MAALog]? {
        // 1. 构建 Bark 请求 URLRequest (使用 JSON POST)
        guard let request = buildRequest(for: logs, config: config, viewModel: viewModel) else {
            if viewModel.showSendLogsInGUI {
                viewModel.logError("构建 Bark POST 请求失败。")
            }
            viewModel.BarkBot = false
            // 这是配置错误或 JSON 编码错误，不进行重试。
            return nil
        }

        do {
            // 2. 发送网络请求
            if viewModel.showSendLogsInGUI {
                viewModel.logInfo("准备发送 Bark 日志摘要 (\(logs.count)条)...")
            }
            // 改为使用 URLSession.shared.upload(for:from:) 来发送 POST 请求体
            let (_, response) = try await URLSession.shared.data(for: request)

            // 3. 检查服务器响应
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw URLError(.badServerResponse, userInfo: ["statusCode": statusCode])
            }
            if viewModel.showSendLogsInGUI {
                viewModel.logInfo("Bark 通知发送成功。")
            }
            // 发送成功，重置失败计数器并返回 nil (表示无需重试)。
            consecutiveFailureCount = 0
            return nil

        } catch {
            // 4. 捕获错误，执行失败重试或自动禁用逻辑
            consecutiveFailureCount += 1
            if viewModel.showSendLogsInGUI {
                viewModel.logError("发送 Bark 通知失败: \(error.localizedDescription)")
            }

            if consecutiveFailureCount >= failureThreshold {
                // 如果连续失败次数达到阈值，则禁用功能。
                viewModel.BarkBot = false
                if viewModel.showSendLogsInGUI {
                    viewModel.logError("Bark 通知连续失败 \(consecutiveFailureCount) 次，已自动关闭此功能。请检查网络和 Bark Key/服务器配置。")
                }
                // 返回 nil，停止重试。
                return nil
            } else {
                // 如果失败次数未达到阈值，则请求重试。
                if viewModel.showSendLogsInGUI {
                    viewModel.logWarn("Bark 通知发送失败（第 \(consecutiveFailureCount) 次尝试），将在10s后重试。")
                }
                // 返回原始日志数组，通知上层管理器将它们加回缓冲区。
                return logs
            }
        }
    }

    /// 根据配置和日志内容构建最终的 Bark URLRequest 和 JSON Body。
    /// 移除原 buildURL 方法，改为此 POST 请求构建方法。
    private func buildRequest(for logs: [MAALog], config: NotificationConfig, viewModel: MAAViewModel) -> URLRequest? {
        // 1. 准备通知内容
        let title = (viewModel.notificationTriggers.sendAllLogsAfterFinish) ? "MAA 任务已全部完成" : "MAA 日志摘要 (\(logs.count)条)"
        let bodyItems = logs.map { log in
            let timeString = log.date.formatted(date: .omitted, time: .standard)
            return "[\(timeString)] \(log.content)"
        }
        let body = bodyItems.joined(separator: "\n")

        // 2. 准备 Bark 服务器 URL
        // 注意：POST 请求的 URL 路径与 GET 不同，只需要到 /push 即可。
        // 为了兼容旧的配置，我们从 config.barkServer 和 config.barkKey 构造基础 URL。
        let barkBaseURL = config.barkServer.hasSuffix("/") ? config.barkServer : "\(config.barkServer)/"
        guard let url = URL(string: "\(barkBaseURL)push") else {
            return nil
        }
        
        // 3. 构建 JSON Payload
        let jsonPayload: [String: Any] = [
            "title": title,
            "body": body,
            "device_key": config.barkKey, // 使用 device_key 字段传递 Bark Key
            "group": "MAA",
            "icon": "https://maa.plus/docs/images/maa-logo_512x512.png"
        ]

        // 4. JSON 编码
        guard let httpBody = try? JSONSerialization.data(withJSONObject: jsonPayload, options: []) else {
            return nil
        }

        // 5. 构建 URLRequest
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        return request
    }
}
