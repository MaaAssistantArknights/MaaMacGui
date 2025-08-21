//
//  DingTalkNotificationManager.swift
//  MAA
//
//  Created by RainYang on 2025/8/21.
//

import Combine
import Foundation


// MARK: - Notification Manager
/// 钉钉通知管理器，监听日志变化并发送通知
class DingTalkNotificationManager {
    private let viewModel: MAAViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: MAAViewModel) {
        self.viewModel = viewModel
    }
    /// 开始监听日志变化
    @MainActor func startObserving() {
        // 确保在开始新的监听前，清除旧的监听，防止重复
        stopObserving()
        
        viewModel.$logs
            .dropFirst() // 忽略初始值，只在新日志产生时响应
            .sink { [weak self] newLogs in
                // print(newLogs.last?.content)
                // 获取最新的一条日志
                guard let self = self, let latestLog = newLogs.last else { return }
                self.sendNotification(for: latestLog)
            }
            .store(in: &cancellables)
        print("DingTalkNotificationManager: Started observing logs.")
    }
    
    /// 停止监听日志变化
    func stopObserving() {
        cancellables.removeAll()
        print("DingTalkNotificationManager: Stopped observing logs.")
    }

    @MainActor private func sendNotification(for log: MAALog) {
        // 检查总开关是否都已启用，并且已配置URL
        guard viewModel.DingTalkBot,
              !viewModel.DKwebhookURL.isEmpty else {
            return
        }

        // 使用 ViewModel 中的当前设置初始化客户端
        let botClient = DingTalkBotClient(
            webhookURL: viewModel.DKwebhookURL,
            secret: viewModel.DKsecret
        )

        // 格式化日志消息
        let content = log.content

        // 在后台任务中发送，避免阻塞UI
        Task {
            do {
                print("准备发送钉钉通知...")
                _ = try await botClient.sendTextMessage(content: content)
                print("钉钉通知发送成功。")
            } catch {
                print("发送钉钉通知失败: \(error.localizedDescription)")
                viewModel.logError("发送钉钉通知失败: \(error.localizedDescription)")
                stopObserving()
                viewModel.DingTalkBot = false
            }
        }
    }
}
