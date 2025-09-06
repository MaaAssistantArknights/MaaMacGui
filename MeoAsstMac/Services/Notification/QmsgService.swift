//
//  QmsgService.swift
//  MAA
//
//  Created by RainYang on 2025/8/31.
//


import Foundation

@MainActor
class QmsgService: NotificationService {
    private var consecutiveFailureCount = 0
    private let failureThreshold = 3

    func send(logs: [MAALog], using config: NotificationConfig, viewModel: MAAViewModel) async -> [MAALog]? {
        let settings = config.qmsg
        // Qmsg API: server/send/{key}
        guard let url = URL(string: "\(settings.server)send/\(settings.key)") else {
            viewModel.logError("Qmsg URL 无效。请检查 Server 和 Key。")
            return nil
        }
        
        // 如果没有指定 QQ，则不发送
        guard !settings.userQQ.isEmpty else {
            viewModel.logError("Qmsg 发送失败：未指定用户 QQ。")
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            // Qmsg API 需要 'application/x-www-form-urlencoded' 格式
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            // 1. 格式化日志摘要作为消息内容
            let title = "MAA 日志摘要 (\(logs.count)条)"
            let contentItems = logs.map { log -> String in
                let timeString = log.date.formatted(date: .omitted, time: .standard)
                return "[\(timeString)] \(log.content)"
            }
            let content = "\(title)\n--------------------\n\(contentItems.joined(separator: "\n"))"
            
            // 2. 构建 x-www-form-urlencoded 请求体
            var components = URLComponents()
            components.queryItems = [
                URLQueryItem(name: "msg", value: content),
                URLQueryItem(name: "qq", value: settings.userQQ)
            ]
            // botQQ 是可选的
            if !settings.botQQ.isEmpty {
                components.queryItems?.append(URLQueryItem(name: "bot", value: settings.botQQ))
            }
            
            request.httpBody = components.query?.data(using: .utf8)
            
            // 3. 发送请求
            viewModel.logInfo("准备发送 Qmsg 通知...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                 let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw URLError(.badServerResponse, userInfo: ["statusCode": statusCode])
            }
            
            // 检查 Qmsg 的特定响应
            if let responseString = String(data: data, encoding: .utf8), responseString.contains("\"code\":0") {
                viewModel.logInfo("Qmsg 通知发送成功。")
                consecutiveFailureCount = 0
                return nil
            } else {
                let reason = String(data: data, encoding: .utf8) ?? "未知响应"
                throw URLError(.cannotParseResponse, userInfo: [NSLocalizedDescriptionKey: "Qmsg API 错误: \(reason)"])
            }
            
        } catch {
            consecutiveFailureCount += 1
            viewModel.logError("发送 Qmsg 通知失败: \(error.localizedDescription)")
            
            if consecutiveFailureCount >= failureThreshold {
                viewModel.qmsg.isEnabled = false
                viewModel.logError("Qmsg 通知连续失败 \(consecutiveFailureCount) 次，已自动关闭。")
                return nil
            } else {
                viewModel.logWarn("Qmsg 通知发送失败（第 \(consecutiveFailureCount) 次尝试），将在下一周期重试。")
                return logs
            }
        }
    }
}
