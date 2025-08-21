import Foundation
import SwiftUI
import CryptoKit

/// 一个用于与钉钉自定义机器人交互的客户端。
///
/// 这个类处理了与钉钉机器人API通信的所有细节，包括网络请求和安全签名（加签）。
/// 它可以轻松地集成到任何Swift项目中，尤其适合在SwiftUI中使用。
///
/// ## 使用方法:
///
/// 1. **初始化客户端**:
/// ```
/// let botClient = DingTalkBotClient(
///     webhookURL: "YOUR_WEBHOOK_URL",
///     secret: "YOUR_SECRET_KEY" // 如果设置了“加签”，请提供密钥
/// )
/// ```
///
/// 2. **在 SwiftUI 视图的 `Task` 中发送消息**:
/// ```
/// Task {
///     do {
///         try await botClient.sendTextMessage(content: "这是一条来自 SwiftUI 的测试消息")
///         print("消息发送成功！")
///     } catch {
///         print("消息发送失败: \(error.localizedDescription)")
///     }
/// }
/// ```
class DingTalkBotClient {
    
    /// 钉钉机器人的 Webhook URL。
    private let webhookURL: String
    
    /// 用于“加签”安全设置的密钥。如果未设置，则为 `nil`。
    private let secret: String?
    
    /// 自定义错误类型，用于更好地描述发送过程中可能出现的问题。
    enum BotError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case apiError(code: Int, message: String)
        case encodingError
        case featureDisabled
        case unknownError
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "无效的 Webhook URL。"
            case .networkError(let error):
                return "网络请求失败: \(error.localizedDescription)"
            case .apiError(let code, let message):
                return "钉钉 API 错误 (代码: \(code)): \(message)"
            case .encodingError:
                return "请求体编码失败。"
            case .featureDisabled:
                return "此功能已被禁用。"
            case .unknownError:
                return "发生未知错误。"
            }
        }
    }

    /// 初始化一个钉钉机器人客户端实例。
    /// - Parameters:
    ///   - webhookURL: 钉钉机器人的完整 Webhook URL。
    ///   - secret: （可选）如果你的机器人开启了“加签”安全设置，请提供此处。
    init(webhookURL: String, secret: String? = nil) {
        self.webhookURL = webhookURL
        self.secret = secret
    }
    
    // MARK: - Public Methods
    
    /// 发送文本消息。
    /// - Parameters:
    ///   - content: 消息文本内容。**注意**: 如果机器人设置了“自定义关键词”，内容中必须包含其中一个关键词。
    ///   - atMobiles: 需要@的用户的手机号列表。
    ///   - isAtAll: 是否@所有人。
    @discardableResult
    func sendTextMessage(content: String, atMobiles: [String] = [], isAtAll: Bool = false) async throws -> DingTalkResponse {
        let payload = DingTalkPayload.text(
            text: DingTalkPayload.TextPayload(content: content),
            at: DingTalkPayload.AtPayload(atMobiles: atMobiles, isAtAll: isAtAll)
        )
        return try await sendRequest(payload: payload)
    }
    
    /// 发送 Markdown 格式消息。
    /// - Parameters:
    ///   - title: 消息标题，会显示在推送通知中。
    ///   - text: Markdown 格式的消息内容。
    ///   - atMobiles: 需要@的用户的手机号列表。
    ///   - isAtAll: 是否@所有人。
    @discardableResult
    func sendMarkdownMessage(title: String, text: String, atMobiles: [String] = [], isAtAll: Bool = false) async throws -> DingTalkResponse {
        let payload = DingTalkPayload.markdown(
            markdown: DingTalkPayload.MarkdownPayload(title: title, text: text),
            at: DingTalkPayload.AtPayload(atMobiles: atMobiles, isAtAll: isAtAll)
        )
        return try await sendRequest(payload: payload)
    }
    
    // MARK: - Private Helpers
    
    /// 根据是否提供了 `secret` 来生成最终的请求 URL。
    /// 如果提供了 `secret`，则会计算签名并附加到 URL 参数中。
    private func getSignedURL() throws -> URL {
        guard var components = URLComponents(string: webhookURL) else {
            throw BotError.invalidURL
        }

        // 如果没有 secret，直接返回原始 URL
        guard let secret = secret, !secret.isEmpty else {
            guard let url = components.url else { throw BotError.invalidURL }
            return url
        }
        
        // --- 开始计算签名 ---
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let stringToSign = "\(timestamp)\n\(secret)"
        
        let secretData = Data(secret.utf8)
        let stringToSignData = Data(stringToSign.utf8)
        
        let key = SymmetricKey(data: secretData)
        let signature = HMAC<SHA256>.authenticationCode(for: stringToSignData, using: key)
        let signatureBase64 = Data(signature).base64EncodedString()
        
        // URL-encode 签名结果
        guard let encodedSign = signatureBase64.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw BotError.encodingError
        }

        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "timestamp", value: timestamp),
            URLQueryItem(name: "sign", value: encodedSign)
        ]
        
        guard let signedUrl = components.url else {
            throw BotError.invalidURL
        }
        
        return signedUrl
    }
    
    /// 发送网络请求的核心方法。
    private func sendRequest<T: Encodable>(payload: T) async throws -> DingTalkResponse {
        let url = try getSignedURL()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw BotError.encodingError
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw BotError.networkError(NSError(domain: "HTTPError", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: nil))
        }
        
        let apiResponse = try JSONDecoder().decode(DingTalkResponse.self, from: data)
        
        if apiResponse.errcode != 0 {
            throw BotError.apiError(code: apiResponse.errcode, message: apiResponse.errmsg)
        }
        
        return apiResponse
    }
}


// MARK: - DingTalk Data Models

/// 钉钉机器人消息的通用响应体。
struct DingTalkResponse: Decodable {
    let errcode: Int
    let errmsg: String
}

/// 钉钉机器人消息的载荷（Payload）结构体。
/// 使用 `enum` 来区分不同的消息类型。
private enum DingTalkPayload: Encodable {
    case text(text: TextPayload, at: AtPayload)
    case markdown(markdown: MarkdownPayload, at: AtPayload)
    // 在这里可以添加更多消息类型，如 link, actionCard 等

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text, let at):
            try container.encode("text", forKey: .msgtype)
            try container.encode(text, forKey: .text)
            try container.encode(at, forKey: .at)
        case .markdown(let markdown, let at):
            try container.encode("markdown", forKey: .msgtype)
            try container.encode(markdown, forKey: .markdown)
            try container.encode(at, forKey: .at)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case msgtype, text, markdown, at
    }
    
    // MARK: - Nested Payload Structs
    struct TextPayload: Encodable {
        let content: String
    }
    
    struct MarkdownPayload: Encodable {
        let title: String
        let text: String
    }
    
    struct AtPayload: Encodable {
        let atMobiles: [String]
        let isAtAll: Bool
    }
}
