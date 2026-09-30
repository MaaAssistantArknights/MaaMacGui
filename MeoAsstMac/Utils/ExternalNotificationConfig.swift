//
//  ExternalNotificationConfig.swift
//  MAA
//
//  Created by MAA on 2026/9/30.
//

import Combine
import Foundation

/// 外部通知渠道类型，与 Windows 版 MaaWpfGui 的外部通知 provider 一一对应。
enum ExternalNotificationProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case serverChan
    case telegram
    case discord
    case dingTalk
    case smtp
    case bark
    case qmsg
    case gotify
    case customWebhook

    var id: String { rawValue }

    /// 渠道显示名：品牌名不本地化，与设置页渠道列表一致；自定义 Webhook 用本地化文案。
    var displayName: String {
        switch self {
        case .serverChan: "Server Chan"
        case .telegram: "Telegram"
        case .discord: "Discord"
        case .dingTalk: "DingTalk"
        case .smtp: "SMTP"
        case .bark: "Bark"
        case .qmsg: "Qmsg"
        case .gotify: "Gotify"
        case .customWebhook: String(localized: "自定义 Webhook")
        }
    }
}

/// 单条外部通知渠道配置。
///
/// 与 WPF 侧每渠道一个 record 不同，这里用一个超集结构承载全部字段：
/// 每种渠道只读写自己关心的字段，其余字段保持默认值并原样持久化，
/// 换来 SwiftUI 表单绑定与 Codable 的零样板。
struct ExternalNotificationConfig: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var provider: ExternalNotificationProvider = .serverChan

    // Server Chan
    var serverChanSendKey = ""

    // Telegram
    var telegramBotToken = ""
    var telegramChatID = ""
    var telegramTopicID = ""

    // Discord
    var discordBotToken = ""
    var discordUserID = ""

    // DingTalk
    var dingTalkAccessToken = ""
    var dingTalkSecret = ""

    // SMTP
    var smtpServer = ""
    var smtpPort = ""
    var smtpUser = ""
    var smtpPassword = ""
    var smtpFrom = ""
    var smtpTo = ""
    var smtpUseSSL = false
    var smtpRequiresAuthentication = false

    // Bark
    var barkSendKey = ""
    var barkServer = ""

    // Qmsg
    var qmsgServer = ""
    var qmsgKey = ""
    var qmsgUser = ""
    var qmsgBot = ""

    // Gotify
    var gotifyServer = ""
    var gotifyToken = ""

    // Custom Webhook
    var webhookURL = ""
    var webhookHeaders = ""
    var webhookBody = ""

    /// 该渠道在设置页用于编辑字段的键集合，切换渠道类型后用于剔除脏数据不必需——
    /// 未使用字段无害，仅由 UI 决定展示哪些。
    var displayName: String { provider.displayName }

    /// 新增渠道卡片：除类型外全部使用默认值。
    init(provider: ExternalNotificationProvider = .serverChan) {
        self.provider = provider
    }

    enum CodingKeys: String, CodingKey {
        case id, provider
        case serverChanSendKey
        case telegramBotToken, telegramChatID, telegramTopicID
        case discordBotToken, discordUserID
        case dingTalkAccessToken, dingTalkSecret
        case smtpServer, smtpPort, smtpUser, smtpPassword, smtpFrom, smtpTo
        case smtpUseSSL, smtpRequiresAuthentication
        case barkSendKey, barkServer
        case qmsgServer, qmsgKey, qmsgUser, qmsgBot
        case gotifyServer, gotifyToken
        case webhookURL, webhookHeaders, webhookBody
    }

    /// 全字段容错解码：缺省的 key 回落到默认值。
    /// synthesized Codable 会因新增字段缺 key 而让整份历史配置解码失败，故手写。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        provider = try container.decodeIfPresent(ExternalNotificationProvider.self, forKey: .provider) ?? .serverChan
        serverChanSendKey = try container.decodeIfPresent(String.self, forKey: .serverChanSendKey) ?? ""
        telegramBotToken = try container.decodeIfPresent(String.self, forKey: .telegramBotToken) ?? ""
        telegramChatID = try container.decodeIfPresent(String.self, forKey: .telegramChatID) ?? ""
        telegramTopicID = try container.decodeIfPresent(String.self, forKey: .telegramTopicID) ?? ""
        discordBotToken = try container.decodeIfPresent(String.self, forKey: .discordBotToken) ?? ""
        discordUserID = try container.decodeIfPresent(String.self, forKey: .discordUserID) ?? ""
        dingTalkAccessToken = try container.decodeIfPresent(String.self, forKey: .dingTalkAccessToken) ?? ""
        dingTalkSecret = try container.decodeIfPresent(String.self, forKey: .dingTalkSecret) ?? ""
        smtpServer = try container.decodeIfPresent(String.self, forKey: .smtpServer) ?? ""
        smtpPort = try container.decodeIfPresent(String.self, forKey: .smtpPort) ?? ""
        smtpUser = try container.decodeIfPresent(String.self, forKey: .smtpUser) ?? ""
        smtpPassword = try container.decodeIfPresent(String.self, forKey: .smtpPassword) ?? ""
        smtpFrom = try container.decodeIfPresent(String.self, forKey: .smtpFrom) ?? ""
        smtpTo = try container.decodeIfPresent(String.self, forKey: .smtpTo) ?? ""
        smtpUseSSL = try container.decodeIfPresent(Bool.self, forKey: .smtpUseSSL) ?? false
        smtpRequiresAuthentication = try container.decodeIfPresent(Bool.self, forKey: .smtpRequiresAuthentication) ?? false
        barkSendKey = try container.decodeIfPresent(String.self, forKey: .barkSendKey) ?? ""
        barkServer = try container.decodeIfPresent(String.self, forKey: .barkServer) ?? ""
        qmsgServer = try container.decodeIfPresent(String.self, forKey: .qmsgServer) ?? ""
        qmsgKey = try container.decodeIfPresent(String.self, forKey: .qmsgKey) ?? ""
        qmsgUser = try container.decodeIfPresent(String.self, forKey: .qmsgUser) ?? ""
        qmsgBot = try container.decodeIfPresent(String.self, forKey: .qmsgBot) ?? ""
        gotifyServer = try container.decodeIfPresent(String.self, forKey: .gotifyServer) ?? ""
        gotifyToken = try container.decodeIfPresent(String.self, forKey: .gotifyToken) ?? ""
        webhookURL = try container.decodeIfPresent(String.self, forKey: .webhookURL) ?? ""
        webhookHeaders = try container.decodeIfPresent(String.self, forKey: .webhookHeaders) ?? ""
        webhookBody = try container.decodeIfPresent(String.self, forKey: .webhookBody) ?? ""
    }
}

/// 外部通知设置 store：渠道配置列表与发送时机开关，全部持久化到 UserDefaults。
///
/// 开关键名与 WPF 配置语义对齐（任务完成 / 任务出错 / 输出详细信息）；
/// 「任务日志输出停滞时发送」依赖 WPF 独有的 StallTimeout 功能，macOS 版不提供。
@MainActor
final class ExternalNotificationSettingsStore: ObservableObject {
    static let shared = ExternalNotificationSettingsStore()

    private static let configsKey = "MAAExternalNotificationConfigs"
    static let sendWhenCompleteKey = "MAAExternalNotificationSendWhenComplete"
    static let sendWhenErrorKey = "MAAExternalNotificationSendWhenError"
    static let enableDetailsKey = "MAAExternalNotificationEnableDetails"

    @Published var configs: [ExternalNotificationConfig] {
        didSet {
            guard let data = try? JSONEncoder().encode(configs) else { return }
            UserDefaults.standard.set(data, forKey: Self.configsKey)
        }
    }

    @Published var sendWhenComplete: Bool {
        didSet { UserDefaults.standard.set(sendWhenComplete, forKey: Self.sendWhenCompleteKey) }
    }

    @Published var sendWhenError: Bool {
        didSet { UserDefaults.standard.set(sendWhenError, forKey: Self.sendWhenErrorKey) }
    }

    @Published var enableDetails: Bool {
        didSet { UserDefaults.standard.set(enableDetails, forKey: Self.enableDetailsKey) }
    }

    private init() {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: Self.configsKey),
            let decoded = try? JSONDecoder().decode([ExternalNotificationConfig].self, from: data)
        {
            configs = decoded
        } else {
            configs = []
        }
        // 与 WPF 默认值一致：完成与出错默认开启，详细信息默认关闭。
        sendWhenComplete = ud.object(forKey: Self.sendWhenCompleteKey) as? Bool ?? true
        sendWhenError = ud.object(forKey: Self.sendWhenErrorKey) as? Bool ?? true
        enableDetails = ud.object(forKey: Self.enableDetailsKey) as? Bool ?? false
    }
}
