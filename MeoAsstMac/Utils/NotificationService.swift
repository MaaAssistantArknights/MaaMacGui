//
//  NotificationService.swift
//  MAA
//
//  Created by RainYang on 2025/8/30.
//

import Foundation

/// 一个通用的配置结构体，用于向服务传递所需的设置。
struct NotificationConfig {
    let dingTalkWebhook: String
    let dingTalkSecret: String?
    let barkKey: String
    let barkServer: String
}

/// 定义了所有通知服务都必须具备的功能。
protocol NotificationService {
    /// 异步发送格式化后的日志。
    /// - Parameters:
    ///   - logs: 需要发送的日志条目数组。
    ///   - config: 包含所有通知服务配置的结构体。
    ///   - viewModel: ViewModel 实例，用于记录发送状态日志。
    func send(logs: [MAALog], using config: NotificationConfig, viewModel: MAAViewModel) async -> [MAALog]?
}
