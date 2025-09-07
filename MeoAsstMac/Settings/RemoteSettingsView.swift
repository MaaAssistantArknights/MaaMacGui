//
//  RemoteSettingsView.swift
//  MAA
//
//  Created by RainYang on 2025/8/21.
//

import AppKit
import SwiftUI

// 用于 Picker 的服务类型定义
enum NotificationServiceType: String, CaseIterable, Identifiable {
    case dingTalk = "DingTalkBot"
    case bark = "Bark"
    case qmsg = "Qmsg"
    case custom = "自定义 Webhook"
    var id: Self { self }
}

struct RemoteSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    @State private var testMessageContent: String = "这是 MAA 外部通知测试信息。如果你看到了这段内容，就说明通知发送成功了！"
    @State private var statusMessage: String = "准备就绪"
    @State private var isLoading: Bool = false

    // 新增状态，用于控制当前显示哪个服务的设置
    @State private var selectedService: NotificationServiceType = .dingTalk

    // MARK: 用于组合所有影响布局的状态
    private struct AnimationID: Equatable {
        let service: NotificationServiceType
        let isDingTalkEnabled: Bool
        let isBarkEnabled: Bool
        let isCustomWebhookEnabled: Bool
        let isSendAllLogsEnabled: Bool
    }

    // MARK: 计算属性来生成 AnimationID
    private var animationID: AnimationID {
        AnimationID(
            service: selectedService,
            isDingTalkEnabled: viewModel.DingTalkBot,
            isBarkEnabled: viewModel.BarkBot,
            isCustomWebhookEnabled: viewModel.customWebhook.isEnabled,
            isSendAllLogsEnabled: viewModel.notificationTriggers.sendAllLogs
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - 通用设置
                Section {
                    HStack {
                        Text("发送间隔")
                        Spacer()
                        // 使用 TextField 允许用户直接输入
                        TextField("分钟", value: $viewModel.notificationSendingInterval, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)  // 限制输入框宽度
                        Text("分钟")
                    }
                    .help("设置合并日志并发送通知的时间间隔，单位为分钟（1-120）。")
                    
                    Toggle("发送所有日志", isOn: $viewModel.notificationTriggers.sendAllLogs)
                    
                    if !viewModel.notificationTriggers.sendAllLogs {
                        VStack(alignment: .leading, spacing: 10) {
                            SubToggleView(title: "任务完成后发送通知", isOn: $viewModel.notificationTriggers.onTaskCompletion)
                            SubToggleView(title: "任务出错时发送通知", isOn: $viewModel.notificationTriggers.onTaskError)
                        }
                        .padding(.leading, 5)
                    }
                }
                // MARK: - 主表单
                Form {
                    Toggle("记录发送日志", isOn: $viewModel.showSendLogsInGUI)
                    // MARK: - 服务选择器
                    Section {
                        Picker("通知服务", selection: $selectedService.animation(.default)) {  // 将动画应用到状态变更上
                            ForEach(NotificationServiceType.allCases) { service in
                                Text(service.rawValue).tag(service)
                            }
                        }
                        .pickerStyle(.menu)  // 使用下拉菜单样式，方便未来扩展
                    }

                    // MARK: - 动态设置区域
                    // 根据选择的服务，动态显示对应的设置内容
                    switch selectedService {
                    case .dingTalk:
                        DingTalkSettingsView(isLoading: $isLoading, sendAction: sendDingTalkTestMessage)
                            .transition(.opacity.combined(with: .offset(y: 10)))
                    case .bark:
                        BarkSettingsView(isLoading: $isLoading, sendAction: sendBarkTestMessage)
                            .transition(.opacity.combined(with: .offset(y: 10)))
                    case .qmsg:
                        QmsgSettingsView(isLoading: $isLoading, sendAction: sendQmsgTestMessage)
                            .transition(.opacity.combined(with: .offset(y: 10)))
                    case .custom:
                        CustomWebhookSettingsView(isLoading: $isLoading, sendAction: sendCustomWebhookTestMessage)
                            .transition(.opacity.combined(with: .offset(y: 10)))

                    }
                }
                
                Text("将在下一发送周期生效")
                    .font(.caption).foregroundColor(.secondary)

                // MARK: - 统一的状态栏页脚
                StatusFooter(isLoading: isLoading, statusMessage: statusMessage)
            }
            .padding()  // 应用全局内边距，解决控件贴边问题
            //当 selectedService 变化时，所有相关的布局和视图变化都会有动画效果
            .animation(.default, value: animationID)
        }
        .frame(maxWidth: 360, maxHeight: 240)
    }
    // MARK: - 测试消息发送逻辑

    private func sendDingTalkTestMessage() {
        isLoading = true
        statusMessage = "正在发送至钉钉..."

        let botClient = DingTalkBotClient(
            webhookURL: viewModel.DKwebhookURL,
            secret: viewModel.DKsecret
        )

        Task {
            do {
                _ = try await botClient.sendTextMessage(content: testMessageContent)
                statusMessage = "钉钉发送成功！(\(Date().formatted(date: .omitted, time: .standard)))"
            } catch {
                statusMessage = "钉钉发送失败: \(error.localizedDescription)"
            }
            isLoading = false
        }

    }

    private func sendBarkTestMessage() {
        isLoading = true
        statusMessage = "正在发送至 Bark..."

        Task {
            do {
                let title = "MAA 测试消息"
                guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                    let encodedBody = testMessageContent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                else {
                    throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "消息内容编码失败"])
                }

                let urlString =
                    "\(viewModel.BarkServer)\(viewModel.BarkKey)/\(encodedTitle)/\(encodedBody)?group=MAA&icon=https://maa.plus/docs/images/maa-logo_512x512.png"

                guard let url = URL(string: urlString) else {
                    throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "无效的 Bark URL 或 Key"])
                }

                let (_, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(
                        .badServerResponse,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "服务器响应错误，状态码: \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                        ])
                }

                statusMessage = "Bark 发送成功！(\(Date().formatted(date: .omitted, time: .standard)))"

            } catch {
                statusMessage = "Bark 发送失败: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    /// 发送自定义 Webhook 测试消息
    private func sendCustomWebhookTestMessage() {
        isLoading = true
        statusMessage = "正在发送至自定义 Webhook..."

        Task {
            do {
                let settings = viewModel.customWebhook
                guard let url = URL(string: settings.url) else {
                    throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "无效的 Webhook URL"])
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let title = "MAA 测试消息"
                let escapedContent =
                    testMessageContent
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                let time = Date().formatted(date: .omitted, time: .standard)

                var processedBody = settings.bodyTemplate
                processedBody = processedBody.replacingOccurrences(of: "{title}", with: title)
                processedBody = processedBody.replacingOccurrences(of: "{content}", with: escapedContent)
                processedBody = processedBody.replacingOccurrences(of: "{time}", with: time)

                request.httpBody = processedBody.data(using: .utf8)

                let (_, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode)
                else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw URLError(
                        .badServerResponse, userInfo: [NSLocalizedDescriptionKey: "服务器响应错误，状态码: \(statusCode)"])
                }

                statusMessage = "自定义 Webhook 发送成功！(\(Date().formatted(date: .omitted, time: .standard)))"
            } catch {
                statusMessage = "自定义 Webhook 发送失败: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    /// 发送 Qmsg 测试消息 (新增)
    private func sendQmsgTestMessage() {
        isLoading = true
        statusMessage = "正在发送至 Qmsg..."

        Task {
            do {
                let settings = viewModel.qmsg
                guard var components = URLComponents(string: settings.server) else {
                    throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "无效的 Qmsg 服务器地址"])
                }
                components.path = "/send/\(settings.key)"

                guard let url = components.url else {
                    throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "无效的 Qmsg URL 或 Key"])
                }

                guard !settings.userQQ.isEmpty else {
                    throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "用户 QQ 不能为空"])
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

                var formComponents = URLComponents()
                formComponents.queryItems = [
                    URLQueryItem(name: "msg", value: testMessageContent),
                    URLQueryItem(name: "qq", value: settings.userQQ),
                ]
                if !settings.botQQ.isEmpty {
                    formComponents.queryItems?.append(URLQueryItem(name: "bot", value: settings.botQQ))
                }

                request.httpBody = formComponents.query?.data(using: .utf8)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw URLError(
                        .badServerResponse, userInfo: [NSLocalizedDescriptionKey: "服务器响应错误，状态码: \(statusCode)"])
                }

                if let responseString = String(data: data, encoding: .utf8), responseString.contains("\"code\":0") {
                    statusMessage = "Qmsg 发送成功！(\(Date().formatted(date: .omitted, time: .standard)))"
                } else {
                    let reason = String(data: data, encoding: .utf8) ?? "未知响应"
                    throw URLError(
                        .cannotParseResponse, userInfo: [NSLocalizedDescriptionKey: "Qmsg API 错误: \(reason)"])
                }

            } catch {
                statusMessage = "Qmsg 发送失败: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

// MARK: - 带连接线的子 Toggle 视图
struct SubToggleView: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 这就是我们的“连接线”，用一个圆角矩形或胶囊体模拟
            Capsule()
                .fill(Color.gray.opacity(0.5)) // 设置颜色和透明度
                .frame(width: 2.5) // 线的宽度
                .frame(maxHeight: 25) // 线的高度，可以根据你的 Toggle 高度微调

            Toggle(title, isOn: $isOn)
        }
    }
}

// MARK: - 钉钉设置子视图
struct DingTalkSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var isLoading: Bool
    let sendAction: () -> Void

    var body: some View {
        // 使用 Group 包裹，以便应用统一的动画效果
        Group {
            Section {
                Toggle("启用 DingTalk 通知", isOn: $viewModel.DingTalkBot)

                if viewModel.DingTalkBot {
                    Text("若配置无效则将在正式运行中自动关闭")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("Webhook", text: $viewModel.DKwebhookURL)
                    SecureField("密钥 (可选)", text: $viewModel.DKsecret)
                }
            }

            if viewModel.DingTalkBot {
                Section {
                    Button(action: sendAction) {
                        Label("发送测试", systemImage: "paperplane.fill")
                    }
                    .disabled(viewModel.DKwebhookURL.isEmpty || isLoading)
                }
            }
        }
        // 添加动画修饰符，监听开关值的变化
        .animation(.default, value: viewModel.DingTalkBot)
    }
}

// MARK: - Bark 设置子视图
struct BarkSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var isLoading: Bool
    let sendAction: () -> Void

    var body: some View {
        // 使用 Group 包裹，以便应用统一的动画效果
        Group {
            Section {
                Toggle("启用 Bark 通知", isOn: $viewModel.BarkBot)

                if viewModel.BarkBot {
                    Text("若配置无效则将在正式运行中自动关闭")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("服务器地址", text: $viewModel.BarkServer)
                    SecureField("Key", text: $viewModel.BarkKey)
                }
            }

            if viewModel.BarkBot {
                Section {
                    Button(action: sendAction) {
                        Label("发送测试", systemImage: "paperplane.fill")
                    }
                    .disabled(viewModel.BarkKey.isEmpty || isLoading)
                }
            }
        }
        // 添加动画修饰符，监听开关值的变化
        .animation(.default, value: viewModel.BarkBot)
    }
}

// MARK: - Qmsg 设置子视图 (新增)
struct QmsgSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var isLoading: Bool
    let sendAction: () -> Void

    var body: some View {
        Group {
            Section {
                Toggle("启用 Qmsg 通知", isOn: $viewModel.qmsg.isEnabled)

                if viewModel.qmsg.isEnabled {
                    Text("若配置无效则将在正式运行中自动关闭")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("Server", text: $viewModel.qmsg.server)
                        .onAppear {
                            if viewModel.qmsg.server.isEmpty {
                                viewModel.qmsg.server = "https://qmsg.zendee.cn/"
                            }
                        }

                    SecureField("Key", text: $viewModel.qmsg.key)

                    TextField("用户 QQ (接收消息)", text: $viewModel.qmsg.userQQ)

                    TextField("机器人 QQ (可选)", text: $viewModel.qmsg.botQQ)
                }
            }

            if viewModel.qmsg.isEnabled {
                Section {
                    Button(action: sendAction) {
                        Label("发送测试", systemImage: "paperplane.fill")
                    }
                    .disabled(viewModel.qmsg.key.isEmpty || viewModel.qmsg.userQQ.isEmpty || isLoading)
                }
            }
        }
        .animation(.default, value: viewModel.qmsg.isEnabled)
    }
}

// MARK: - 自定义 Webhook 设置子视图
struct CustomWebhookSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var isLoading: Bool
    let sendAction: () -> Void

    var body: some View {
        Group {
            Section {
                Toggle("启用自定义 Webhook", isOn: $viewModel.customWebhook.isEnabled)

                if viewModel.customWebhook.isEnabled {
                    Text("若配置无效则将在正式运行中自动关闭")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("Webhook URL", text: $viewModel.customWebhook.url)

                    VStack(alignment: .leading) {
                        Text("请求体 (JSON Body Template)").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: $viewModel.customWebhook.bodyTemplate)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 150)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }

                    DisclosureGroup("可用占位符说明") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("{title}").fontWeight(.bold) + Text(" - 消息标题")
                            Text("{content}").fontWeight(.bold) + Text(" - 格式化后的日志正文")
                            Text("{time}").fontWeight(.bold) + Text(" - 发送时间")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }

            if viewModel.customWebhook.isEnabled {
                Section {
                    Button(action: sendAction) {
                        Label("发送测试", systemImage: "paperplane.fill")
                    }
                    .disabled(viewModel.customWebhook.url.isEmpty || isLoading)
                }
            }
        }
        .animation(.default, value: viewModel.customWebhook.isEnabled)
    }
}

// MARK: - 可重用的状态页脚视图
struct StatusFooter: View {
    let isLoading: Bool
    let statusMessage: String

    var body: some View {
        HStack {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                Text("正在发送...")
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: statusMessage.contains("失败") ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(
                        statusMessage.contains("失败") ? .red : (statusMessage == "准备就绪" ? .secondary : .green))

                Text(statusMessage)
                    .foregroundColor(statusMessage.contains("失败") ? .red : .secondary)
                    .fixedSize()
            }
            Spacer()
        }
        .padding(.horizontal)
        .frame(height: 20)
    }
}

struct RemoteSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteSettingsView()
            .environmentObject(MAAViewModel())
            .frame(width: 400, height: 500)
    }
}
