//
//  NotificationManager.swift
//  MAA
//
//  Created by RainYang on 2025/8/30.
//

import Combine
import Foundation

/// 通用通知管理器，负责调度所有启用的通知服务。
///
/// 这个管理器实现了核心的“缓冲”与“节流”逻辑：
/// 1. 监听全局日志流。
/// 2. 将符合条件的日志存入一个共享的缓冲区 (`logBuffer`)。
/// 3. 一个后台定时任务 (`processingTask`) 会周期性地唤醒。
/// 4. 唤醒后，它会调用所有已启用的通知服务（如钉钉、Bark），并将当前缓冲区的日志交给它们发送。
/// 5. 它还会处理具体服务返回的“重试请求”，将发送失败的日志重新放回缓冲区。
@MainActor
class NotificationManager {

    // MARK: - 属性 (Properties)

    private let viewModel: MAAViewModel

    /// 所有新日志的共享缓冲区。
    private var logBuffer: [MAALog] = []

    /// 用于定时处理缓冲区的后台任务。
    private var processingTask: Task<Void, Never>?

    /// 用于存储 Combine 订阅。
    private var cancellables = Set<AnyCancellable>()

    // 持有所有可用通知服务的实例。
    // 将它们作为属性持有，可以让他们各自维护自己的状态（例如失败计数）。
    private let dingTalkService = DingTalkService()
    private let barkService = BarkService()
    private let qmsgService = QmsgService()
    private let customWebhookService = CustomWebhookService()

    init(viewModel: MAAViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - 公开方法 (Public Methods)

    /// 开始监听日志流并启动定时发送任务。
    func startObserving() {
        stopObserving()

        viewModel.$logs
            .dropFirst()
            .sink { [weak self] newLogs in
                guard let self = self, let latestLog = newLogs.last else { return }

                if viewModel.notificationTriggers.sendAllLogs {
                    // 过滤掉管理器自身产生的日志，防止无限反馈循环。
                    if !latestLog.content.contains("钉钉") && !latestLog.content.contains("DingTalk")
                        && !latestLog.content.contains("Bark") && !latestLog.content.contains("Webhook")
                        && !latestLog.content.contains("Qmsg")
                    {
                        self.logBuffer.append(latestLog)
                    }
                }
                else {
                    if viewModel.notificationTriggers.onTaskCompletion && (latestLog.content.contains("完成任务") || latestLog.content.contains("작업 완료") || latestLog.content.contains("任务已全部完成！") || latestLog.content.contains("모든 작업이 완료되었습니다!")) {
                        self.logBuffer.append(latestLog)
                    }
                    else if viewModel.notificationTriggers.onTaskError && (latestLog.content.contains("任务出错") || latestLog.content.contains("작업 오류")) {
                        self.logBuffer.append(latestLog)
                    }
                }
            }
            .store(in: &cancellables)

        processingTask = Task {
            while !Task.isCancelled {
                // 从 ViewModel 动态获取用户设置的发送间隔（分钟）
                let intervalInMinutes = viewModel.notificationSendingInterval
                // 确保间隔至少为 0.1 分钟（6秒），防止设置过小导致问题
                let safeInterval = max(intervalInMinutes, 0.1)

                try? await Task.sleep(nanoseconds: UInt64(safeInterval * 60 * 1_000_000_000))
                await processAndSendBuffer()
            }
        }
    }

    /// 停止监听并取消后台任务，释放资源。
    func stopObserving() {
        cancellables.removeAll()
        processingTask?.cancel()
        processingTask = nil
    }

    // MARK: - 私有方法 (Private Methods)

    /// 处理并发送缓冲区中的日志。
    /// 这个方法由后台任务定时调用。
    private func processAndSendBuffer() async {
        // 如果缓冲区为空，则无需执行任何操作。
        guard !logBuffer.isEmpty else { return }

        // 创建一个日志副本用于发送，并立即清空主缓冲区，以接收新的日志。
        let logsToSend = logBuffer
        logBuffer.removeAll()

        // 从 ViewModel 创建一个包含所有当前配置的快照。
        let currentConfig = NotificationConfig(
            dingTalkWebhook: viewModel.DKwebhookURL,
            dingTalkSecret: viewModel.DKsecret,
            barkKey: viewModel.BarkKey,
            barkServer: viewModel.BarkServer,
            qmsg: viewModel.qmsg,
            customWebhook: viewModel.customWebhook,
        )

        // --- 冲突解决方案 ---
        // 使用一个标志位确保即使多个服务都失败，日志也只会被重新入队一次。
        var logsHaveBeenRequeued = false

        // --- 调度钉钉服务 ---
        if viewModel.DingTalkBot && !currentConfig.dingTalkWebhook.isEmpty {
            // 使用 `if let` 捕获返回值，解决 "Result unused" 警告。
            if let logsToRequeue = await dingTalkService.send(
                logs: logsToSend, using: currentConfig, viewModel: viewModel)
            {
                // 如果需要重试，并且日志尚未被重新入队...
                if !logsHaveBeenRequeued {
                    // ...则将日志重新插入缓冲区的最前端。
                    self.logBuffer.insert(contentsOf: logsToRequeue, at: 0)
                    // 并设置标志位，防止其他服务重复操作。
                    logsHaveBeenRequeued = true
                }
            }
        }

        // --- 调度 Bark 服务 ---
        if viewModel.BarkBot && !currentConfig.barkKey.isEmpty {
            // 对 Bark 服务也使用同样的模式捕获返回值。
            if let logsToRequeue = await barkService.send(logs: logsToSend, using: currentConfig, viewModel: viewModel)
            {
                // 同样，检查标志位以避免重复入队。
                if !logsHaveBeenRequeued {
                    self.logBuffer.insert(contentsOf: logsToRequeue, at: 0)
                    logsHaveBeenRequeued = true
                }
            }
        }

        // --- 调度自定义 Webhook 服务 ---
        if viewModel.customWebhook.isEnabled && !currentConfig.customWebhook.url.isEmpty {
            if let logsToRequeue = await customWebhookService.send(
                logs: logsToSend, using: currentConfig, viewModel: viewModel)
            {
                if !logsHaveBeenRequeued {
                    self.logBuffer.insert(contentsOf: logsToRequeue, at: 0)
                    logsHaveBeenRequeued = true
                }
            }
        }

        // --- 调度 Qmsg 服务 ---
        if viewModel.qmsg.isEnabled && !currentConfig.qmsg.key.isEmpty {
            if let logsToRequeue = await qmsgService.send(logs: logsToSend, using: currentConfig, viewModel: viewModel)
            {
                if !logsHaveBeenRequeued {
                    self.logBuffer.insert(contentsOf: logsToRequeue, at: 0)
                    logsHaveBeenRequeued = true
                }
            }
        }
    }
}
