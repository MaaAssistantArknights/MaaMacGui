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
            Picker("客户端类型：", selection: $config.clientOverride) {
                Text("跟随游戏设置").tag(nil as MAAClientChannel?)
                ForEach(MAAClientChannel.allCases, id: \.self) { client in
                    Text(client.description).tag(Optional(client))
                        .disabled(touchMode == .MacPlayTools && client == .Bilibili)
                }
            }
            Divider()

            Toggle("自动启动客户端", isOn: Binding(
                get: { config.launchesClient },
                set: { config.start_game_enabled = $0 }
            ))
                .disabled(config.clientOverride != nil)
                .padding(.vertical)

            Picker("账号切换", selection: $config.account_name) {
                Text("不切换").tag("")
                ForEach(accountNames.wrappedValue, id: \.hashValue) { account in
                    Text(account).tag(account)
                }
            }

            if touchMode == .MacPlayTools {
                Text("请参考“实用工具” > “分辨率指南”设置PlayCover的分辨率。")
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
