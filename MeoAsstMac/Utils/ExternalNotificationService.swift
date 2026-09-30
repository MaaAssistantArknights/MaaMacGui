//
//  ExternalNotificationService.swift
//  MAA
//
//  Created by MAA on 2026/9/30.
//

import Foundation
import OSLog

/// 外部通知发送入口，行为对齐 WPF 的 `ExternalNotificationService`：
/// 标题统一加 `[MAA]` 前缀，遍历全部已配置渠道逐个发送，结果记入 OSLog。
enum ExternalNotificationService {
    private static let logger = Logger(subsystem: "com.hguandl.MeoAsstMac", category: "ExternalNotificationService")

    /// 一次发送的结果（渠道显示名 + 是否成功），供设置页「发送测试」展示。
    struct SendResult: Identifiable {
        let displayName: String
        let success: Bool

        var id: String { displayName }
    }

    /// 向全部已配置渠道发送通知。
    ///
    /// - Parameters:
    ///   - title: 通知标题（自动加 `[MAA]` 前缀）。
    ///   - content: 通知正文。
    ///   - isTest: 是否为设置页发起的测试发送。
    @MainActor
    static func send(title: String, content: String, isTest: Bool = false) async -> [SendResult] {
        let configs = ExternalNotificationSettingsStore.shared.configs
        var results = [SendResult]()

        for config in configs {
            let provider = ExternalNotificationProviderFactory.make(config: config)
            let success = await provider.send(title: "[MAA] " + title, content: content)
            if !isTest && success {
                continue
            }

            // 与 WPF 一致：实际任务事件只在失败时提示，测试发送总是给出结果。
            if !isTest {
                logger.warning("Failed to send External Notification via \(config.provider.displayName, privacy: .public)")
            }
            results.append(SendResult(displayName: config.provider.displayName, success: success))
        }
        return results
    }

    /// 组装「输出详细信息」的日志文本，格式与 WPF 一致：`[时间][颜色]内容`。
    @MainActor
    static func detailLogs(from logStore: (any LogStore)?) -> String {
        guard let logStore, ExternalNotificationSettingsStore.shared.enableDetails else {
            return ""
        }
        return logStore.logs
            .map { "[\($0.date.maaGuiLogFormat)][\($0.color.logTag)]\($0.content)\n" }
            .joined()
    }

    // MARK: - Events

    /// 「所有任务完成」事件：详情日志 + 完成信息 + 理智恢复预估。
    @MainActor
    static func allTasksCompleted(duration: String, sanityReport: String, detailLogs: String) async -> [SendResult] {
        guard ExternalNotificationSettingsStore.shared.sendWhenComplete else {
            return []
        }
        var content = detailLogs
        content += "用时 \(duration)"
        if !sanityReport.isEmpty {
            content += "\n" + sanityReport
        }
        return await send(title: "任务全部完成", content: content)
    }

    /// 「任务出错」事件：出错的任务链名称，附带详情日志。
    @MainActor
    static func taskError(taskchainName: String, detailLogs: String) async -> [SendResult] {
        guard ExternalNotificationSettingsStore.shared.sendWhenError else {
            return []
        }
        return await send(title: "任务执行出错", content: detailLogs + taskchainName)
    }

    /// 「存在未领取的奖励」事件。WPF 无对应事件；作为正向的运行时提醒，
    /// 与「任务完成后发送通知」开关走同一门控。
    @MainActor
    static func uncollectedReward() async -> [SendResult] {
        guard ExternalNotificationSettingsStore.shared.sendWhenComplete else {
            return []
        }
        return await send(title: "存在未领取的奖励", content: String(localized: "存在未领取的奖励"))
    }
}
