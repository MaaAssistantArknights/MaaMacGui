//
//  StartupSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 30/10/2022.
//

import SwiftUI

struct StartupSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let id: UUID

    private var config: Binding<StartupConfiguration> {
        viewModel.taskConfig(id: id)
    }

    var body: some View {
        Form {
            Picker("客户端类型：", selection: config.client_type) {
                ForEach(MAAClientChannel.allCases, id: \.rawValue) { channel in
                    Text("\(channel.description)").tag(channel)
                }
            }

            Toggle("自动启动客户端", isOn: config.start_game_enabled)
                .disabled(config.client_type.wrappedValue == .default)
        }
        .padding()
    }
}

// struct StartupSettingsView_Previews: PreviewProvider {
//    static var previews: some View {
//        StartupSettingsView(id: MAAViewModel().tasks.randomElement()?.id ?? UUID())
//    }
// }
