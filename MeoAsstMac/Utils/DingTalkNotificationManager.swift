//
//  DingTalkNotificationManager.swift
//  MAA
//
//  Created by RainYang on 2025/8/21.
//

import Combine
import Foundation

/// 钉钉通知管理器，实现了“缓冲”与“节流”机制以限制发送速率。
///
/// 工作流程:
/// 1. 监听 `MAAViewModel` 中的日志 (`viewModel.$logs`)。
/// 2. 当新日志产生时，不立即发送，而是将其添加到一个临时的 `logBuffer` 缓冲区中。
/// 3. 一个独立的后台任务 (`processingTask`) 会以固定的时间间隔（例如每30秒）被唤醒。
/// 4. 唤醒后，它会检查缓冲区，如果缓冲区内有日志，则将所有日志合并成一条 Markdown 消息并发送。
/// 5. 发送后清空缓冲区，等待下一个时间周期。
@MainActor
class DingTalkNotificationManager {
    
    // MARK: - 属性 (Properties)
    
    /// 对 ViewModel 的引用，用于获取日志数据和钉钉配置。
    private let viewModel: MAAViewModel
    
    /// 发送的时间间隔（单位：秒）。
    /// 这是实现“节流”的核心配置。例如，设置为 30.0 意味着最多每30秒向钉钉发送一次请求。
    /// 钉钉的官方限制是每分钟20次，即每3秒一次。设置为30秒非常安全。
    private let sendingInterval: TimeInterval = 30.0
    
    /// 日志缓冲区。所有新产生的、待发送的日志都会先被暂存到这里。
    private var logBuffer: [MAALog] = []
    
    /// 用于定时处理和发送缓冲区的后台任务的句柄。
    /// 我们需要持有它，以便在停止监听时可以安全地取消这个任务。
    private var processingTask: Task<Void, Never>?
    
    /// 用于存储 Combine 订阅的集合，以便在不再需要时取消订阅，防止内存泄漏。
    private var cancellables = Set<AnyCancellable>()
    
    /// 用于记录连续发送失败的次数。
    private var consecutiveFailureCount = 0
    /// 连续失败多少次后自动禁用功能。
    private let failureThreshold = 3

    /// 初始化方法
    /// - Parameter viewModel: 传入 App 的主 ViewModel 实例。
    init(viewModel: MAAViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - 公开方法 (Public Methods)

    /// 开始监听日志变化并启动处理任务。
    /// 这个方法应该在应用启动时（例如在 AppDelegate 中）被调用。
    func startObserving() {
        print("DingTalkNotificationManager: Starting...")
        stopObserving()
        
        // 步骤 1: 订阅 viewModel 的日志发布者。
        viewModel.$logs
            .dropFirst() // `dropFirst()` 忽略订阅时的初始空数组，只响应后续的变更。
            .sink { [weak self] newLogs in
                // 当日志数组更新时，这个闭包会被调用。
                guard let self = self, let latestLog = newLogs.last else { return }
                // 将最新的一条日志添加到我们的缓冲区，而不是立即发送。
                let filterKeyword = "钉钉"
                
                // 检查最新的日志内容是否包含这个关键词。
                if latestLog.content.contains(filterKeyword) {
                    // 如果包含，则直接返回，不进行任何操作。
                    // 这条关于“钉钉”的日志就会被成功忽略。
                    return
                }
                self.logBuffer.append(latestLog)
            }
            .store(in: &cancellables) // 保存订阅，以便后续可以取消。
            
        // 步骤 2: 启动一个独立的、循环的后台任务，作为我们的“定时器”。
        processingTask = Task {
            // `while !Task.isCancelled` 创建一个循环，只要任务没被外部取消，就会一直运行。
            while !Task.isCancelled {
                // 使用现代的并发 API 等待指定的时间间隔。
                // 这比使用旧的 Timer 更精准，且更容易与 async/await 配合。
                try? await Task.sleep(nanoseconds: UInt64(sendingInterval * 1_000_000_000))
                
                // 等待时间结束后，调用方法来处理并发送缓冲区中的内容。
                await processAndSendBuffer()
            }
        }
        print("DingTalkNotificationManager: Started observing logs and processing task.")
    }
    
    /// 停止监听并取消后台的处理任务。
    /// 在应用退出或不需要通知时调用，以释放资源。
    func stopObserving() {
        // 取消对 viewModel.$logs 的订阅。
        cancellables.removeAll()
        // 取消正在运行的后台任务。这会让 processingTask 中的 `while` 循环停止。
        processingTask?.cancel()
        processingTask = nil
        print("DingTalkNotificationManager: Stopped observing and cancelled processing task.")
    }
    
    // MARK: - 私有方法 (Private Methods)
    
    /// 处理并发送缓冲区中的所有日志。
    /// 这个方法由后台的 `processingTask` 定时调用。
    private func processAndSendBuffer() async {
        // 如果缓冲区是空的，说明这段时间内没有新日志，直接返回，不进行任何操作。
        guard !logBuffer.isEmpty else {
            return
        }

        // 关键步骤：创建一个缓冲区的副本用于发送，然后立刻清空原缓冲区。
        // 这样做的好处是，如果在接下来发送网络请求的漫长过程中（可能是几百毫秒或几秒），
        // 又有新的日志产生并被加入到 `logBuffer`，它们不会被这次发送影响，会留到下一个周期发送。
        // 这避免了数据丢失和竞态条件。
        let logsToSend = logBuffer
        logBuffer.removeAll()
        
        // 调用实际的发送方法，传入需要发送的日志副本。
        await sendNotification(for: logsToSend)
    }

    /// 格式化日志并调用 `DingTalkBotClient` 发送最终的 Markdown 消息。
    /// - Parameter logs: 一个包含了多条日志的数组。
    private func sendNotification(for logs: [MAALog]) async {
        // 前置检查：确保钉钉通知功能已在 App 内启用，并且 Webhook URL 已配置。
        guard viewModel.DingTalkBot, !viewModel.DKwebhookURL.isEmpty else {
            return
        }

        // 初始化您项目中的 DingTalkBotClient。
        let botClient = DingTalkBotClient(
            webhookURL: viewModel.DKwebhookURL,
            secret: viewModel.DKsecret
        )

        // --- 消息格式化 ---
        // 将多条日志格式化为一条美观的 Markdown 消息。
        let title = "MAA 日志摘要 (\(logs.count)条)"
        let contentItems = logs.map { log in
            // 将每条日志格式化成一个列表项。
            let timeString = log.date.formatted(date: .omitted, time: .standard)
            // 对日志内容中的 Markdown 特殊字符（如 "）进行转义，防止最终格式错乱。
            let escapedContent = log.content.replacingOccurrences(of: "\"", with: "\\\"")
            // Markdown 语法: `-` 创建无序列表, `**...**` 使文本加粗。
            return "- **[\(timeString)]** \(escapedContent)"
        }
        // 使用 Markdown 语法将所有部分组合成一个完整的消息体。
        // `###` 是三级标题，`---` 是分割线，`\n\n` 在列表项之间创建更大的间距。
        let fullContent = """
        ### MAA 日志摘要 (\(logs.count)条新消息)
        ---
        \(contentItems.joined(separator: "\n\n"))
        """

        // --- 网络请求 ---
        do {
            // 在发送前，先通过 ViewModel 的日志系统记录一下，方便调试。
            viewModel.logInfo("准备发送钉钉日志摘要 (\(logs.count)条)...")
            
            // 异步调用您客户端的 `sendMarkdownMessage` 方法。
            _ = try await botClient.sendMarkdownMessage(title: title, text: fullContent)
            
            // 发送成功后，再记录一条成功日志。
            viewModel.logInfo("钉钉日志摘要发送成功。")
            
            // 发送成功，重置失败计数器
            consecutiveFailureCount = 0
        } catch {
            // 如果发送过程中出现任何错误（网络问题、API错误等），捕获它并记录一条错误日志，增加计数器并执行重试或禁用逻辑
            consecutiveFailureCount += 1
            viewModel.logError("发送钉钉通知摘要失败: \(error.localizedDescription)")

            if consecutiveFailureCount >= failureThreshold {
                // 如果连续失败次数达到阈值
                viewModel.DingTalkBot = false // 禁用功能
                viewModel.logError("钉钉通知连续失败 \(consecutiveFailureCount) 次，已自动关闭此功能。请检查网络和配置。")
            } else {
                // 如果失败次数未达到阈值
                viewModel.logWarn("钉钉通知发送失败（第 \(consecutiveFailureCount) 次尝试），将在下一周期重试。")
                // 将本次失败的日志重新加回缓冲区的最前端
                self.logBuffer.insert(contentsOf: logs, at: 0)
            }
        }
    }
}
