//
//  ExternalNotificationSettingsView.swift
//  MAA
//
//  Created by MAA on 2026/9/30.
//

import SwiftUI

/// 外部通知设置页，对齐 Windows 版的外部通知设置区块：
/// 发送时机开关 + 渠道配置列表（添加 / 删除 / 编辑 / 发送测试）。
struct ExternalNotificationSettingsView: View {
    @ObservedObject private var store = ExternalNotificationSettingsStore.shared

    @State private var testResults: [ExternalNotificationService.SendResult]?
    @State private var isSendingTest = false

    var body: some View {
        // 设置窗口宽度固定（App 层 frame(maxWidth: 360)），渠道卡片展开后内容
        // 高度会超出窗口，因此仅卡片列表区滚动；开关与操作区保持固定可见。
        //
        // 整页 ScrollView 不可行：macOS Settings 场景按内容理想高度决定窗口尺寸，
        // ScrollView 不传播内容理想高度（协商值≈0），切页签时窗口高度与内容
        // 首帧布局都不稳定，表现为页签下方闪动。固定区与其他页签同构（纯 VStack），
        // 首帧即完成渲染；卡片区定高滚动（minHeight == idealHeight），窗口尺寸恒定。
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsTabBarAvoidance())
    }

    @ViewBuilder
    private var content: some View {
        Text("外部通知会在任务全部完成或任务执行出错时发送；勾选 ｢输出详细信息｣ 后将附带运行日志。")
            .font(.caption)
            .foregroundStyle(.secondary)

        Toggle(isOn: $store.sendWhenComplete) {
            Text("任务完成后发送通知")
        }
        Toggle(isOn: $store.sendWhenError) {
            Text("任务出错时发送通知")
        }
        Toggle(isOn: $store.enableDetails) {
            Text("输出详细信息")
        }

        HStack {
            Menu {
                ForEach(ExternalNotificationProvider.allCases) { provider in
                    Button(provider.displayName) {
                        store.configs.append(ExternalNotificationConfig(provider: provider))
                    }
                }
            } label: {
                Label("添加推送", systemImage: "plus")
            }

            Spacer()

            Button {
                sendTest()
            } label: {
                if isSendingTest {
                    ProgressView().controlSize(.small)
                } else {
                    Text("发送测试")
                }
            }
            .disabled(isSendingTest)
        }

        if let testResults {
            ForEach(testResults) { result in
                HStack(spacing: 4) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                    Text("\(result.displayName) \(result.success ? "发送成功" : "发送失败")")
                        .font(.caption)
                }
            }
        }

            if !store.configs.isEmpty {
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach($store.configs) { $config in
                            ChannelConfigCard(config: $config) {
                                store.configs.removeAll { $0.id == config.id }
                            }
                        }
                    }
                    .padding(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, idealHeight: 160)
            }
    }

    private func sendTest() {
        isSendingTest = true
        Task {
            let results = await ExternalNotificationService.send(
                title: "MAA 外部通知测试",
                content: "这是 MAA 外部通知测试信息。如果你看到了这段内容，就说明通知发送成功了！",
                isTest: true)
            testResults = results
            isSendingTest = false
        }
    }
}

// MARK: - Settings Tab Bar Avoidance

/// macOS 26 起 Settings 页签栏悬浮于内容区上方，且不参与窗口高度协商：
/// 内容顶部需自行避让，否则顶部选项会被页签栏盖住（表现为设置选项
/// 「错位偏移到页签栏下面」）。旧系统页签栏为推挤式布局，无需处理。
/// 避让量 80 = 悬浮页签栏高度（约 65）+ 常规内容上间距（16）。
private struct SettingsTabBarAvoidance: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.safeAreaPadding(.top, 80)
        } else {
            content
        }
    }
}

// MARK: - Channel Card

private struct ChannelConfigCard: View {
    @Binding var config: ExternalNotificationConfig
    let onRemove: () -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            fields
                .padding(.top, 4)
        } label: {
            HStack {
                Picker("", selection: $config.provider) {
                    ForEach(ExternalNotificationProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Spacer()

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder
    private var fields: some View {
        switch config.provider {
        case .serverChan:
            LabeledField("Server Chan 发送密钥", text: $config.serverChanSendKey)
        case .telegram:
            LabeledField("机器人 Token", text: $config.telegramBotToken)
            LabeledField("聊天 ID", text: $config.telegramChatID)
            LabeledField("话题ID（可选）", text: $config.telegramTopicID)
        case .discord:
            LabeledField("机器人 Token", text: $config.discordBotToken)
            LabeledField("用户 ID", text: $config.discordUserID)
        case .dingTalk:
            LabeledField("Access Token", text: $config.dingTalkAccessToken)
            LabeledField("加签密钥", text: $config.dingTalkSecret)
        case .smtp:
            LabeledField("SMTP 服务器", text: $config.smtpServer)
            LabeledField("端口", text: $config.smtpPort)
            LabeledField("发件人", text: $config.smtpFrom)
            LabeledField("收件人", text: $config.smtpTo)
            Toggle(isOn: $config.smtpUseSSL) {
                Text("使用 SSL")
            }
            Toggle(isOn: $config.smtpRequiresAuthentication) {
                Text("需要登录")
            }
            if config.smtpRequiresAuthentication {
                LabeledField("用户名", text: $config.smtpUser)
                VStack(alignment: .leading, spacing: 2) {
                    Text("密码").font(.caption)
                    SecureField("密码", text: $config.smtpPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
            }
        case .bark:
            LabeledField("Bark 发送密钥", text: $config.barkSendKey)
            LabeledField("Bark 服务器", text: $config.barkServer)
        case .qmsg:
            LabeledField("Server", text: $config.qmsgServer)
            LabeledField("Key", text: $config.qmsgKey)
            LabeledField("用户 QQ", text: $config.qmsgUser)
            LabeledField("机器人 QQ", text: $config.qmsgBot)
        case .gotify:
            LabeledField("服务器 URL", text: $config.gotifyServer)
            LabeledField("应用程序令牌", text: $config.gotifyToken)
        case .customWebhook:
            CustomWebhookFields(config: $config)
        }
    }
}

// MARK: - Custom Webhook

private struct CustomWebhookFields: View {
    @Binding var config: ExternalNotificationConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledField("Webhook URL", text: $config.webhookURL)

            Menu("预置模板") {
                ForEach(WebhookPreset.all) { preset in
                    Button(preset.name) {
                        config.webhookURL = preset.url
                        config.webhookHeaders = preset.headers
                        config.webhookBody = preset.body
                    }
                }
            }
            Text("请将预制模板中的 <> 占位符（如 <nickname>）替换为实际值")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Webhook Headers")
                Text("每行一条，格式：名称: 值")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    text: $config.webhookHeaders,
                    prompt: Text(verbatim: "Content-Type: application/json")) {
                        Text("Webhook Headers")
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("消息体模板")
                Text("可用占位符：{title}、{content}、{time}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    text: $config.webhookBody,
                    prompt: Text(verbatim: "{\"title\": \"{title}\"}"),
                    axis: .vertical) {
                        Text("消息体模板")
                    }
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// 自定义 Webhook 的预置模板，与 WPF 的 `WebhookPresetTemplate` 一一对应。
/// 模板中的 `\n` 是 JSON 字符串内的转义序列，发送前不做占位符以外的改写。
private struct WebhookPreset: Identifiable {
    let name: String
    let url: String
    let headers: String
    let body: String

    var id: String { name }

    static let all = [
        WebhookPreset(name: "自定义", url: "", headers: "", body: ""),
        WebhookPreset(name: "Discord Webhook", url: "", headers: "", body: "{\"content\": \"{content}\"}"),
        WebhookPreset(
            name: "KOOK Channel",
            url: "https://www.kookapp.cn/api/v3/message/create",
            headers: "Authorization: Bot <bot_token>",
            body: "{\"type\": 9, \"target_id\": \"<channel_id>\", \"content\": \"**{title}**\\n{content}\"}"),
        WebhookPreset(
            name: "KOOK Direct",
            url: "https://www.kookapp.cn/api/v3/direct-message/create",
            headers: "Authorization: Bot <bot_token>",
            body: "{\"type\": 9, \"target_id\": \"<user_id>\", \"content\": \"**{title}**\\n{content}\"}"),
        WebhookPreset(
            name: "MeoW",
            url: "https://api.chuckfang.com/<nickname>",
            headers: "",
            body: "{\"title\":\"{title}\",\"msg\":\"{content}\\n{time}\"}"),
        WebhookPreset(
            name: "ntfy",
            url: "https://ntfy.sh/<topic>",
            headers: "",
            body: "{\"message\": \"{content}\", \"title\": \"{title}\"}"),
        WebhookPreset(
            name: "WeCom",
            url: "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=<key>",
            headers: "",
            body: "{\"msgtype\": \"text\", \"text\": {\"content\": \"{content}\"}}"),
    ]
}

// MARK: - Field

private struct LabeledField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .frame(maxWidth: .infinity)
        }
    }
}

struct ExternalNotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ExternalNotificationSettingsView()
    }
}
