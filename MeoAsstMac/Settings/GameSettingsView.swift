//
//  GameSettingsView.swift
//  MAA
//
//  Created by hguandl on 28/4/2023.
//

import SwiftUI

struct GameSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Picker("客户端类型：", selection: $viewModel.clientChannel) {
                ForEach(MAAClientChannel.allCases, id: \.rawValue) { channel in
                    Text(channel.description).tag(channel)
                }
            }

            Divider()

            Group {
                Toggle(isOn: $viewModel.runDurationLimitEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("限制单次运行时长")
                        Text("从点击「开始」开始计时，到达上限后自动停止任务。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if viewModel.runDurationLimitEnabled {
                    Stepper(value: $viewModel.runDurationLimitMinutes, in: 1...11451) {
                        HStack {
                            Text("运行时长上限（分钟）：")
                            TextField("", value: $viewModel.runDurationLimitMinutes, format: .number)
                                .frame(maxWidth: 50)
                        }
                    }
                }
            }
            .disabled(viewModel.status != .idle)
        }
        .padding()
    }
}

struct GameSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GameSettingsView().environmentObject(MAAViewModel())
    }
}
