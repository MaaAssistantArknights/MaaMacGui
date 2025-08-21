//
//  RemoteSettingsView.swift
//  MAA
//
//  Created by RainYang on 2025/8/21.
//

import SwiftUI

struct RemoteSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    
    @State private var testMessageContent: String = "这是一条来自MAA的测试消息"
    @State private var statusMessage: String = "准备就绪"
    @State private var isLoading: Bool = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Form {
                Section {
                    Toggle("启用钉钉机器人通知", isOn: $viewModel.DingTalkBot)
                    
                    TextField("Webhook", text: $viewModel.DKwebhookURL)
                        .disabled(!viewModel.DingTalkBot)
                    
                    SecureField("密钥", text: $viewModel.DKsecret)
                        .disabled(!viewModel.DingTalkBot)
                }
                
                Button(action: sendTestMessage) {
                    Label("发送测试", systemImage: "paperplane.fill")
                }
                // 只有在启用、URL不为空且不在加载时才可点击
                .disabled(!viewModel.DingTalkBot || viewModel.DKwebhookURL.isEmpty || isLoading)
                
                Section(header: Text("状态")) {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("正在发送...")
                        }
                    } else {
                        Text(statusMessage)
                            .foregroundColor(statusMessage.contains("失败") ? .red : .secondary)
                    }
                }
            }
        }
        .padding()
        .animation(.default, value: viewModel.touchMode)
    }
    
    private func sendTestMessage() {
        isLoading = true
        statusMessage = "正在发送..."
        
        // 检查功能是否启用
        guard viewModel.DingTalkBot else {
            statusMessage = "发送失败: 功能未启用。"
            isLoading = false
            return
        }
        
        // 使用 ViewModel 中的数据初始化客户端
        let botClient = DingTalkBotClient(
            webhookURL: viewModel.DKwebhookURL,
            secret: viewModel.DKsecret
        )
        
        Task {
            do {
                let response = try await botClient.sendTextMessage(content: testMessageContent)
                statusMessage = "发送成功！(\(Date().formatted(date: .omitted, time: .standard)))"
                print("发送成功: \(response)")
            } catch {
                statusMessage = "发送失败: \(error.localizedDescription)"
                print("发送失败: \(error)")
            }
            isLoading = false
        }
    }
}

struct RemoteSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteSettingsView().environmentObject(MAAViewModel())
    }
}
