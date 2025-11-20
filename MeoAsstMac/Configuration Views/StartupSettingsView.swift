//
//  StartupSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 30/10/2022.
//

import SwiftUI

struct StartupSettingsView: View {
    @Binding var config: StartupConfiguration

    @AppStorage("MAATouchMode") var touchMode = MaaTouchMode.maatouch

    @State private var accountInput = ""

    @State private var showAccountInput = false {
        didSet {
            accountInput = ""
        }
    }

    private var accountNames: Binding<[String]> {
        Binding {
            UserDefaults.standard.stringArray(forKey: "AccountNames") ?? []
        } set: { newValue in
            UserDefaults.standard.set(newValue, forKey: "AccountNames")
        }
    }

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 3) {
                Text("客户端类型：\(config.client_type.description)")
                Text("请在“设置” > “游戏设置” 中选择客户端类型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()

            Toggle("自动启动客户端", isOn: $config.start_game_enabled)
                .padding(.vertical)

            Picker("账号切换", selection: $config.account_name) {
                Text("不切换").tag("")
                ForEach(accountNames.wrappedValue, id: \.hashValue) { account in
                    Text(account).tag(account)
                }
            }

            if touchMode == .MacPlayTools {
                Text("请将PlayCover的分辨率设置为1280x720、分辨率缩放设置为1.0。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !showAccountInput {
                HStack {
                    Button("添加…") {
                        showAccountInput = true
                    }
                    Button("删除") {
                        accountNames.wrappedValue.removeAll { $0 == config.account_name }
                        config.account_name = accountNames.wrappedValue.first ?? ""
                    }
                    .disabled(config.account_name.isEmpty)
                }
            } else {
                HStack {
                    Button("添加") {
                        if !accountNames.wrappedValue.contains(accountInput) {
                            accountNames.wrappedValue.append(accountInput)
                        }
                        config.account_name = accountInput
                        showAccountInput = false
                    }
                    .disabled(accountInput.isEmpty)
                    Button("取消") {
                        showAccountInput = false
                    }
                }
                TextField("登录名", text: $accountInput)
            }
        }
        .padding()
        .animation(.default, value: showAccountInput)
    }
}

struct StartupSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        StartupSettingsView(config: .constant(.init()))
    }
}
