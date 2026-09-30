//
//  ExternalNotificationProviders.swift
//  MAA
//
//  Created by MAA on 2026/9/30.
//

import CryptoKit
import Foundation
import OSLog

/// 单个外部通知渠道的发送能力，与 WPF 的 `IExternalNotificationProvider` 对应。
protocol ExternalNotificationSending {
    /// 发送通知。
    /// - Returns: 发送成功与否。
    func send(title: String, content: String) async -> Bool
}

/// 各渠道 HTTP / SMTP 实现汇总，行为对齐 MaaWpfGui `Services/ExternalNotification` 下的同名 provider。
enum ExternalNotificationProviderFactory {
    static func make(config: ExternalNotificationConfig) -> ExternalNotificationSending {
        switch config.provider {
        case .serverChan: ServerChanProvider(config: config)
        case .telegram: TelegramProvider(config: config)
        case .discord: DiscordProvider(config: config)
        case .dingTalk: DingTalkProvider(config: config)
        case .smtp: SMTPProvider(config: config)
        case .bark: BarkProvider(config: config)
        case .qmsg: QmsgProvider(config: config)
        case .gotify: GotifyProvider(config: config)
        case .customWebhook: CustomWebhookProvider(config: config)
        }
    }
}

// MARK: - Shared Helpers

private let providerLogger = Logger(subsystem: "com.hguandl.MeoAsstMac", category: "ExternalNotification")

extension String {
    /// RFC 3986 unreserved 集合百分号编码，语义对齐 .NET 的 `Uri.EscapeDataString`。
    var formURLEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .formURLUnreserved) ?? self
    }
}

extension CharacterSet {
    static let formURLUnreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

struct HTTPResult {
    let statusCode: Int
    let body: String

    var isSuccess: Bool { (200..<300).contains(statusCode) }
}

private enum HTTP {
    /// 发送 POST 请求；网络错误时返回 nil 并记录日志。
    /// URL 默认按 OSLog 私有规则脱敏，避免密钥随日志泄漏。
    static func post(url: URL, headers: [String: String] = [:], body: Data) async -> HTTPResult? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            return HTTPResult(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? "")
        } catch {
            providerLogger.error("Failed to send POST request: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func postJSON(url: URL, headers: [String: String] = [:], json: Any) async -> HTTPResult? {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else { return nil }
        var allHeaders = ["Content-Type": "application/json"]
        allHeaders.merge(headers) { _, new in new }
        return await post(url: url, headers: allHeaders, body: data)
    }

    static func postForm(url: URL, headers: [String: String] = [:], fields: [String: String]) async -> HTTPResult? {
        let body = fields
            .map { "\($0.key)=\($0.value.formURLEncoded)" }
            .joined(separator: "&")
        var allHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        allHeaders.merge(headers) { _, new in new }
        return await post(url: url, headers: allHeaders, body: Data(body.utf8))
    }
}

extension ExternalNotificationConfig {
    var url: URL? {
        URL(string: webhookURL)
    }
}

/// 详情日志的通用正则（与 WPF 一致）：`[时间][颜色]内容`，
/// Gotify / SMTP 渠道发送前会按此清洗或重排日志行。
enum DetailedLog {
    static let pattern = try! NSRegularExpression(pattern: #"\[(.*?)\]\[(.*?)\]([\s\S]*?)(?=\n\[|$)"#)

    static func matches(in content: String) -> [NSTextCheckingResult] {
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return pattern.matches(in: content, range: range)
    }

    static func group(_ result: NSTextCheckingResult, _ index: Int, in content: String) -> String {
        guard let range = Range(result.range(at: index), in: content) else { return "" }
        return String(content[range])
    }
}

// MARK: - Server Chan

struct ServerChanProvider: ExternalNotificationSending {
    let config: ExternalNotificationConfig

    func send(title: String, content: String) async -> Bool {
        // 去掉 title 中的换行符，并确保长度不超过 32 个字符。
        var title = title.replacingOccurrences(of: "\n", with: "")
        if title.count > 32 {
            title = String(title.prefix(32))
        }

        let sendKey = config.serverChanSendKey
        guard let url = constructURL(sendKey) else {
            providerLogger.warning("Failed to send ServerChan notification, invalid key format for sctp")
            return false
        }

        guard let response = await HTTP.postForm(url: url, fields: ["text": title, "desp": content]) else {
            return false
        }

        guard let json = try? JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [String: Any],
            let code = json["code"] as? Int
        else {
            providerLogger.warning("Failed to send ServerChan notification, unknown response")
            return false
        }

        guard code == 0 else {
            providerLogger.warning("Failed to send ServerChan notification, code: \(code)")
            return false
        }
        return true
    }

    /// sctp 前缀为 Server酱3 的 key，推送域名随 key 中的通道号变化。
    private func constructURL(_ sendKey: String) -> URL? {
        if !sendKey.hasPrefix("sctp") {
            return URL(string: "https://sctapi.ftqq.com/\(sendKey).send")
        }

        guard let match = sendKey.firstMatch(of: /^sctp(\d+)t/) else {
            return nil
        }
        return URL(string: "https://\(match.1).push.ft07.com/send/\(sendKey).send")
    }
}

// MARK: - Telegram

struct TelegramProvider: ExternalNotificationSending {
    let config: ExternalNotificationConfig

    /// sendMessage 的 text 上限，超出时接口返回 400 message is too long。
    private static let maxTextLength = 4096
    private static let truncatedMark = "[...]\n"

    func send(title: String, content: String) async -> Bool {
        guard let url = URL(string: "https://api.telegram.org/bot\(config.telegramBotToken)/sendMessage") else {
            return false
        }

        var json: [String: Any] = [
            "chat_id": config.telegramChatID,
            "text": Self.truncate("\(title): \(content)"),
        ]
        // 仅在提供了话题 ID 时附加。
        if !config.telegramTopicID.isEmpty {
            json["message_thread_id"] = config.telegramTopicID
        }

        guard let response = await HTTP.postJSON(url: url, json: json) else {
            return false
        }

        guard response.isSuccess else {
            // 失败原因只在响应体里（如 message is too long），记下来便于排查。
            providerLogger.warning("Telegram API returned \(response.statusCode): \(response.body)")
            return false
        }

        return !response.body.contains("\"ok\":false")
    }

    /// 把消息裁到上限以内。开启「输出详细信息」后，完成通知会带上本轮全部日志，
    /// 长任务很容易超限而整条发不出去。保留末尾：用时、配置与出错清单等正文在日志之后。
    private static func truncate(_ text: String) -> String {
        guard text.count > maxTextLength else { return text }
        // Swift 字符串按字素簇切分，天然避免代理项对（如 emoji）被截半的问题。
        return truncatedMark + text.suffix(maxTextLength - truncatedMark.count)
    }
}

// MARK: - Discord

struct DiscordProvider: ExternalNotificationSending {
    let config: ExternalNotificationConfig

    private static let apiVersion = "v9"

    func send(title: String, content: String) async -> Bool {
        guard let channelId = await createDMChannel(botToken: config.discordBotToken, userId: config.discordUserID) else {
            return false
        }
        // 与其他渠道一致携带事件标题（WPF 版仅发送 content，此处为体验改进）。
        return await sendMessage(botToken: config.discordBotToken, channelId: channelId, message: "\(title): \(content)")
    }

    private func createDMChannel(botToken: String, userId: String) async -> String? {
        guard let url = URL(string: "https://discord.com/api/\(Self.apiVersion)/users/@me/channels") else {
            return nil
        }

        let response = await HTTP.postJSON(
            url: url,
            headers: [
                "Authorization": "Bot \(botToken)",
                // Discord 不允许浏览器系 User-Agent。
                "User-Agent": "DiscordBot",
            ],
            json: ["recipient_id": userId])

        guard let response, response.isSuccess else {
            providerLogger.warning("Failed to create DM channel.")
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [String: Any],
            let channelId = json["id"] as? String
        else {
            return nil
        }
        return channelId
    }

    private func sendMessage(botToken: String, channelId: String, message: String) async -> Bool {
        guard let url = URL(string: "https://discord.com/api/\(Self.apiVersion)/channels/\(channelId)/messages") else {
            return false
        }

        let response = await HTTP.postForm(
            url: url,
            headers: [
                "Authorization": "Bot \(botToken)",
                // Discord 不允许浏览器系 User-Agent。
                "User-Agent": "DiscordBot",
            ],
            fields: ["content": message])

        guard let response, response.isSuccess else {
            providerLogger.warning("Failed to send message.")
            return false
        }
        return true
    }
}

// MARK: - DingTalk

struct DingTalkProvider: ExternalNotificationSending {
    let config: ExternalNotificationConfig

    func send(title: String, content: String) async -> Bool {
        guard !config.dingTalkAccessToken.isEmpty,
            let endpoint = Self.webhookEndpoint(accessToken: config.dingTalkAccessToken, secret: config.dingTalkSecret)
        else {
            providerLogger.warning("Failed to send DingTalk notification: Access Token is empty")
            return false
        }

        guard let response = await HTTP.postJSON(
            url: endpoint,
            json: [
                "msgtype": "text",
                "text": ["content": "\(title): \(content)"],
            ])
        else {
            return false
        }

        guard let json = try? JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [String: Any],
            let errorCode = json["errcode"] as? Int
        else {
            providerLogger.warning("Failed to parse DingTalk response.")
            return false
        }

        guard errorCode == 0 else {
            providerLogger.warning(
                "Failed to send DingTalk notification, error code: \(errorCode), error message: \(json["errmsg"] as? String ?? "")")
            return false
        }
        return true
    }

    private static func webhookEndpoint(accessToken: String, secret: String) -> URL? {
        var urlString = "https://oapi.dingtalk.com/robot/send?access_token=\(accessToken)"

        if !secret.isEmpty {
            let timestamp = Int64(Date.now.timeIntervalSince1970 * 1000)
            let signBase = "\(timestamp)\n\(secret)"
            let key = SymmetricKey(data: Data(secret.utf8))
            let authCode = HMAC<SHA256>.authenticationCode(for: Data(signBase.utf8), using: key)
            let sign = Data(authCode).base64EncodedString().formURLEncoded
            urlString += "&timestamp=\(timestamp)&sign=\(sign)"
        }

        return URL(string: urlString)
    }
}

// MARK: - Bark

struct BarkProvider: ExternalNotificationSending {
    let config: ExternalNotificationConfig

    func send(title: String, content: String) async -> Bool {
        if config.barkSendKey.isEmpty {
            providerLogger.warning("Failed to send Bark notification, Bark send key is empty")
            return false
        }
        if config.barkServer.isEmpty {
            providerLogger.warning("Failed to send Bark notification, Bark server address is empty")
            return false
        }

        guard let baseURL = URL(string: config.barkServer.trimmingCharacters(in: CharacterSet(charactersIn: "/")).appending("/")),
            let pushURL = URL(string: "push", relativeTo: baseURL)
        else {
            return false
        }

        guard let response = await HTTP.postJSON(
            url: pushURL,
            json: [
                // 分组与图标为可选字段，设置它们以便在 Bark 端更好地组织与展示。
                "device_key": config.barkSendKey,
                "title": title,
                "body": content,
                "group": "MaaAssistantArknights",
                "icon": "https://cdn.jsdelivr.net/gh/MaaAssistantArknights/design@main/v2/icons/maa-logo_256x256.png",
            ])
        else {
            providerLogger.warning("Failed to send Bark notification, response is null")
            return false
        }

        guard let json = try? JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [String: Any],
            let code = json["code"] as? Int
        else {
            return false
        }

        guard code == 200 else {
            providerLogger.warning("Failed to send Bark notification: \(code) \(json["message"] as? String ?? "")")
            return false
        }
        return true
    }
}

// MARK: - Qmsg

struct QmsgProvider: ExternalNotificationSending {
    let config: ExternalNotificationConfig

    func send(title: String, content: String) async -> Bool {
        guard let url = URL(string: "\(config.qmsgServer)/jsend/\(config.qmsgKey)") else {
            return false
        }

        guard let response = await HTTP.postJSON(
            url: url,
            json: ["msg": content, "qq": config.qmsgUser, "bot": config.qmsgBot])
        else {
            providerLogger.warning("Failed to send Qmsg notification")
            return false
        }

        if response.body.isEmpty {
            providerLogger.warning("Failed to send Qmsg notification")
            return false
        }

        guard let json = try? JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [String: Any] else {
            providerLogger.warning("Failed to send Qmsg notification, unknown response")
            return false
        }

        guard let success = json["success"] as? Bool else {
            providerLogger.warning("Failed to send Qmsg notification, unknown response")
            return false
        }

        return success
    }
}

// MARK: - Gotify

struct GotifyProvider: ExternalNotificationSending {
    let config: ExternalNotificationConfig

    func send(title: String, content: String) async -> Bool {
        if config.gotifyServer.isEmpty {
            providerLogger.warning("Failed to send Gotify notification, server URL is empty")
            return false
        }

        let server = config.gotifyServer.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let baseURL = URL(string: server.appending("/")),
            let scheme = baseURL.scheme, ["http", "https"].contains(scheme)
        else {
            return false
        }

        if config.gotifyToken.isEmpty {
            providerLogger.warning("Failed to send Gotify notification, application token is empty")
            return false
        }

        guard let messageURL = URL(string: "message", relativeTo: baseURL) else {
            return false
        }

        // 处理内容，去掉时间戳和颜色标记。
        let processedContent = Self.processContent(content)

        guard let response = await HTTP.postJSON(
            url: messageURL,
            headers: ["X-Gotify-Key": config.gotifyToken],
            json: ["title": title, "message": processedContent])
        else {
            providerLogger.warning("Failed to send Gotify notification, response is null")
            return false
        }

        if response.body.isEmpty {
            providerLogger.warning("Failed to send Gotify notification, response is null")
            return false
        }

        guard let json = try? JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [String: Any],
            json["id"] != nil
        else {
            providerLogger.warning("Failed to send Gotify notification, unknown response: \(response.body)")
            return false
        }
        return true
    }

    /// 把 `[时间][颜色]内容` 形式的日志行折叠为 `[时间]内容`，去掉不适合纯文本渠道的颜色标记。
    private static func processContent(_ content: String) -> String {
        let matches = DetailedLog.matches(in: content)
        if matches.isEmpty {
            return content
        }

        var result = ""
        for match in matches {
            let time = DetailedLog.group(match, 1, in: content)
            let contentText = DetailedLog.group(match, 3, in: content)
            result += "[\(time)]\(contentText.trimmingCharacters(in: CharacterSet(charactersIn: "\n\r")))"
            result += "\n"
        }
        return String(result.dropLast())
    }
}

// MARK: - Custom Webhook

struct CustomWebhookProvider: ExternalNotificationSending {
    let config: ExternalNotificationConfig

    func send(title: String, content: String) async -> Bool {
        if config.webhookURL.isEmpty || config.webhookBody.isEmpty {
            providerLogger.warning("Custom Webhook failed to send: URL or message body is empty")
            return false
        }
        guard let url = config.url else {
            providerLogger.warning("Custom Webhook failed to send: invalid URL")
            return false
        }

        // 占位符替换；标题和内容会原样嵌入 JSON 模板的字符串字面量，
        // 需转义反斜杠、引号和换行，否则含这些字符的任务日志会破坏 JSON 结构。
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = formatter.string(from: Date())

        let body = config.webhookBody
            .replacingOccurrences(of: "{title}", with: Self.escapeJSONString(title))
            .replacingOccurrences(of: "{content}", with: Self.escapeJSONString(content))
            .replacingOccurrences(of: "{time}", with: now)

        var headers: [String: String] = [:]
        for line in config.webhookHeaders.replacingOccurrences(of: "\r", with: "").split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            headers[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                String(parts[1]).trimmingCharacters(in: .whitespaces)
        }

        guard let response = await HTTP.post(url: url, headers: headers, body: Data(body.utf8)) else {
            providerLogger.warning("Custom Webhook failed to send: response is null")
            return false
        }

        guard response.isSuccess else {
            providerLogger.warning("Custom Webhook failed to send: HTTP \(response.statusCode)")
            return false
        }
        return true
    }

    /// 转义嵌入 JSON 字符串字面量的特殊字符：反斜杠、引号；换行转为 \n 字面量，\r 丢弃。
    private static func escapeJSONString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// MARK: - SMTP

struct SMTPProvider: ExternalNotificationSending {
    let config: ExternalNotificationConfig

    func send(title: String, content: String) async -> Bool {
        let processedContent = Self.processContent(content)

        guard let port = Int(config.smtpPort), !config.smtpServer.isEmpty, port > 0, port <= 65535 else {
            providerLogger.error("Failed to send Email notification, invalid SMTP configuration")
            return false
        }

        let emailFrom = config.smtpFrom
        let emailTo = config.smtpTo
        if emailFrom.isEmpty || emailTo.isEmpty {
            providerLogger.error("Failed to send Email notification, sender or recipient is empty")
            return false
        }

        if config.smtpRequiresAuthentication && (config.smtpUser.isEmpty || config.smtpPassword.isEmpty) {
            providerLogger.error("Failed to send Email notification, authentication is enabled but credentials are incomplete")
            return false
        }

        // title 不含换行；正文换行转 <br/> 供 HTML 展示。
        let subject = title.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        let htmlContent = processedContent
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "<br/>")
        let body = Self.buildEmailBody(subject: subject, content: htmlContent)

        let request = SMTPClient.Request(
            host: config.smtpServer,
            port: UInt16(port),
            useSSL: config.smtpUseSSL,
            requiresAuthentication: config.smtpRequiresAuthentication,
            user: config.smtpUser,
            password: config.smtpPassword,
            from: emailFrom,
            to: emailTo,
            subject: subject,
            htmlBody: body)

        return await SMTPClient.send(request)
    }

    /// 把 `[时间][颜色]内容` 形式的日志行重排为带颜色的 HTML span；
    /// 时间戳统一用 trace 色，正文颜色与 GUI 日志配色一致。
    /// 日志内容可能来自 Core 输出或用户自定义配置（如基建计划描述），
    /// 嵌入 HTML 前必须转义，否则会破坏邮件 DOM 结构。
    private static func processContent(_ content: String) -> String {
        let matches = DetailedLog.matches(in: content)
        if matches.isEmpty {
            return htmlEscape(content)
        }

        var result = content
        let traceColor = rgbColor(for: .trace)
        for match in matches.reversed() {
            let time = DetailedLog.group(match, 1, in: content)
            let colorCode = DetailedLog.group(match, 2, in: content)
            let contentText = DetailedLog.group(match, 3, in: content)

            guard let logColor = MAALog.LogColor(resourceKey: colorCode) else { continue }
            guard let fullRange = Range(match.range, in: result) else { continue }
            let replacement =
                "<span style='color: \(traceColor);'>\(htmlEscape(time))  </span><span style='color: \(rgbColor(for: logColor));'>\(htmlEscape(contentText))</span>"
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func rgbColor(for color: MAALog.LogColor) -> String? {
        switch color {
        case .trace: "rgb(128, 128, 128)"
        case .info: "rgb(0, 0, 0)"
        case .rare: "rgb(255, 165, 0)"
        case .warning: "rgb(160, 32, 240)"
        case .error: "rgb(255, 0, 0)"
        }
    }

    private static func buildEmailBody(subject: String, content: String) -> String {
        emailTemplateSource
            .replacingOccurrences(of: "{greeting}", with: String(localized: "博士，有新的通知哦！"))
            .replacingOccurrences(of: "{title}", with: subject)
            .replacingOccurrences(of: "{content}", with: content)
            .replacingOccurrences(of: "{footerLineOne}", with: String(localized: "您会收到此邮件，是因为您在 MAA 中设置了 SMTP 服务器并开启了邮件通知服务。"))
            .replacingOccurrences(of: "{footerLineTwo}", with: String(localized: "此邮件为系统自动发送，请勿回复。"))
            .replacingOccurrences(of: "{officialSite}", with: String(localized: "官网"))
            .replacingOccurrences(of: "{copilotSite}", with: String(localized: "作业站"))
    }

    /// 邮件 HTML 版式与 WPF 保持一致（标题居中、正文与页脚、官方链接）。
    private static let emailTemplateSource =
        """
        <html lang="zh">
        <style>
            .title {
            font-size: xx-large;
            font-weight: bold;
            color: black;
            text-align: center;
            }

            .heading {
            font-size: large;
            }

            .notification h1 {
            font-size: large;
            font-weight: bold;
            }

            .notification p {
            font-size: medium;
            }

            .footer {
            font-size: small;
            }

            .space {
            padding-left: 0.5rem;
            padding-right: 0.5rem;
            }
        </style>

        <h1 class="title">Maa Assistant Arknights</h1>

        <div class="heading">
            <p>{greeting}</p>
        </div>

        <hr />

        <div class="notification">
            <h1>{title}</h1>
            <p>{content}</p>
        </div>

        <hr />

        <div class="footer">
            <p>
            {footerLineOne}
            </p>
            <p>{footerLineTwo}</p>
            <p>
            <a class="space" href="https://github.com/MaaAssistantArknights">
                GitHub
            </a>
            <a class="space" href="https://space.bilibili.com/3493274731940507">
                Bilibili
            </a>
            <a class="space" href="https://maa.plus">{officialSite}</a>
            <a class="space" href="https://prts.plus">{copilotSite}</a>
            </p>
        </div>
        </html>
        """
}
