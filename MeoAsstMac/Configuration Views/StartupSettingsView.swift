//
//  StartupSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 30/10/2022.
//

import SwiftUI

struct StartupSettingsView: View {
    @Binding var config: StartupConfiguration

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 3) {
                Text("客户端类型：\(config.client_type.description)")
                Text("请在“设置” > “游戏设置” 中选择客户端类型。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom)

            Toggle("自动启动客户端", isOn: $config.start_game_enabled)
                .disabled(config.client_type == .default)
        }
        .padding()
    }
}

struct StartupSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        StartupSettingsView(config: .constant(.init()))
    }
}
