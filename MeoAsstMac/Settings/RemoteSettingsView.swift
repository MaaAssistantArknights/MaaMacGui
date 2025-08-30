//
//  RemoteSettingsView.swift
//  MAA
//
//  Created by RainYang on 2025/8/21.
//

import SwiftUI

// 用于 Picker 的服务类型定义
enum NotificationServiceType: String, CaseIterable, Identifiable {
    case dingTalk = "DingTalkBot"
    case bark = "Bark"
    var id: Self { self }
}

struct RemoteSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    
    @State private var testMessageContent: String = "这是一条来自 MAA 的测试消息"
    @State private var statusMessage: String = "准备就绪"
    @State private var isLoading: Bool = false
    
    // 新增状态，用于控制当前显示哪个服务的设置
    @State private var selectedService: NotificationServiceType = .dingTalk

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - 主表单
            Form {
                Toggle("记录发送日志", isOn: $viewModel.showSendLogsInGUI)
                // MARK: - 服务选择器
                Section {
                    Picker("通知服务", selection: $selectedService.animation(.default)) { // 将动画应用到状态变更上
                        ForEach(NotificationServiceType.allCases) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }
                    .pickerStyle(.menu) // 使用下拉菜单样式，方便未来扩展
                }

                // MARK: - 动态设置区域
                // 根据选择的服务，动态显示对应的设置内容
                switch selectedService {
                case .dingTalk:
                    DingTalkSettingsView(isLoading: $isLoading, sendAction: sendDingTalkTestMessage)
                        // 修改动画效果为淡入淡出和垂直位移
                        .transition(.opacity.combined(with: .offset(y: 10)))
                case .bark:
                    BarkSettingsView(isLoading: $isLoading, sendAction: sendBarkTestMessage)
                        // 修改动画效果为淡入淡出和垂直位移
                        .transition(.opacity.combined(with: .offset(y: 10)))
                }
            }
            
            // MARK: - 统一的状态栏页脚
            StatusFooter(isLoading: isLoading, statusMessage: statusMessage)
        }
        .padding() // 应用全局内边距，解决控件贴边问题
        // 移除了全局动画，让 transition 生效
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
                
                let urlString = "\(viewModel.BarkServer)\(viewModel.BarkKey)/\(encodedTitle)/\(encodedBody)?group=MAA&icon=https://maa.plus/docs/images/maa-logo_512x512.png"
                
                guard let url = URL(string: urlString) else {
                    throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "无效的 Bark URL 或 Key"])
                }
                
                let (_, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "服务器响应错误，状态码: \((response as? HTTPURLResponse)?.statusCode ?? -1)"])
                }
                
                statusMessage = "Bark 发送成功！(\(Date().formatted(date: .omitted, time: .standard)))"
                
            } catch {
                statusMessage = "Bark 发送失败: \(error.localizedDescription)"
            }
            isLoading = false
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
                    .foregroundColor(statusMessage.contains("失败") ? .red : (statusMessage == "准备就绪" ? .secondary : .green))
                
                Text(statusMessage)
                    .foregroundColor(statusMessage.contains("失败") ? .red : .secondary)
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

