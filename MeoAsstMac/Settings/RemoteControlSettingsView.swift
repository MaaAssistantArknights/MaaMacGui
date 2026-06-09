import SwiftUI

struct RemoteControlSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @State private var isConnectionTesting: Bool = false
    @State private var connectionTestSuccess: Bool = false
    @State private var connectionTestMessage: String = ""
    @State private var showingAlert: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("注意：随意填入未知来源的地址可能会导致您的账户受到损失。")
                .font(.caption)
                .foregroundColor(.orange)

            Divider()

            HStack {
                Text("获取任务端点").frame(width: 120, alignment: .center)
                TextField("", text: $viewModel.remoteControlGetTaskEndpointUri)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(
                        of: viewModel.remoteControlGetTaskEndpointUri,
                        perform: { uri in
                            if uri.isEmpty {
                                viewModel.startRemoteControl()
                            } else {
                                viewModel.stopRemoteControlPolling()
                            }
                        })
            }

            HStack {
                Text("汇报任务端点").frame(width: 120, alignment: .center)
                TextField("", text: $viewModel.remoteControlReportStatusUri)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            HStack {
                Text("轮询间隔 (ms)").frame(width: 120, alignment: .center)
                TextField("", value: $viewModel.remoteControlPollIntervalMs, format: .number)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            HStack {
                Text("用户标识符").frame(width: 120, alignment: .center)
                TextField("", text: $viewModel.remoteControlUserIdentity)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: {
                    performConnectionTest()
                }) {
                    if isConnectionTesting {
                        Text("测试中...")
                    } else {
                        Text("测试连接")
                    }
                }
            }

            HStack {
                Text("设备标识符（只读）").frame(width: 120, alignment: .center)
                TextField("", text: $viewModel.remoteControlDeviceIdentity)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(true)
                Button(action: {
                    regenerateDeviceIdentity()
                }) {
                    Text("重新生成")
                }
            }

            Divider()

            Text("了解如何开发相关功能，可以访问[远程控制功能开发者文档](https://maa.plus/docs/zh-cn/protocol/integration.html)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .onAppear {
            if viewModel.remoteControlDeviceIdentity.isEmpty {
                regenerateDeviceIdentity()
            }
        }
        .alert(connectionTestSuccess ? "连接测试成功" : "连接测试失败", isPresented: $showingAlert) {
            Button("确定") {}
        } message: {
            if !connectionTestMessage.isEmpty {
                Text(connectionTestMessage)
            }
        }
    }

    private func performConnectionTest() {
        guard !viewModel.remoteControlGetTaskEndpointUri.isEmpty else {
            connectionTestSuccess = false
            connectionTestMessage = "连接端点为空。"
            showingAlert = true
            return
        }

        guard
            viewModel.remoteControlGetTaskEndpointUri.lowercased().hasPrefix("http://")
                || viewModel.remoteControlGetTaskEndpointUri.lowercased().hasPrefix("https://")
        else {
            connectionTestSuccess = false
            connectionTestMessage = "连接端点不为 http(s) 地址。"
            showingAlert = true
            return
        }

        let isHttps = viewModel.remoteControlGetTaskEndpointUri.lowercased().hasPrefix("https://")
        isConnectionTesting = true

        Task {
            do {
                connectionTestSuccess = try await viewModel.testRemoteControlConnection()
            } catch {
                connectionTestSuccess = false
                connectionTestMessage = "\(error.localizedDescription)"
            }
            if connectionTestSuccess && !isHttps {
                connectionTestMessage = "连接端点未启用 https，可能不安全。"
            }
            isConnectionTesting = false
            showingAlert = true
        }
    }

    private func regenerateDeviceIdentity() {
        viewModel.remoteControlDeviceIdentity = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

#Preview {
    RemoteControlSettingsView()
        .environmentObject(MAAViewModel())
}
