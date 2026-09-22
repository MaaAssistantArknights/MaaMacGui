//
//  UserDataUpdateSettingsView.swift
//  MAA
//
//  Created by zhangweijian on 22/9/2026.
//

import SwiftUI

struct UserDataUpdateSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    @Binding var config: UserDataUpdateConfiguration

    var body: some View {
        Form {
            Toggle("干员识别", isOn: $config.updateOperBox)
            lastSyncTime(viewModel.lastOperBoxSyncTime)

            Toggle("仓库识别", isOn: $config.updateDepot)
            lastSyncTime(viewModel.lastDepotSyncTime)

            Picker("触发间隔", selection: $config.triggerInterval) {
                ForEach(UserDataUpdateTriggerInterval.allCases, id: \.self) { interval in
                    Text(interval.description)
                }
            }
        }
        .padding()
    }

    @ViewBuilder private func lastSyncTime(_ time: Date?) -> some View {
        if let time {
            Text("上次同步时间：\(time.formatted(date: .numeric, time: .standard))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct UserDataUpdateSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        UserDataUpdateSettingsView(config: .constant(.init()))
            .environmentObject(MAAViewModel())
    }
}
