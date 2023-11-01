//
//  AwardSettingsView.swift
//  MAA
//
//  Created by hguandl on 1/11/2023.
//

import SwiftUI

struct AwardSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let id: UUID

    private var config: Binding<AwardConfiguration> {
        viewModel.taskConfig(id: id)
    }

    var body: some View {
        Form {
            Toggle("领取每日/每周任务奖励", isOn: config.award)

            Toggle("领取所有邮件奖励", isOn: config.mail)
        }
        .padding()
    }
}

#Preview {
    AwardSettingsView(id: UUID())
        .environmentObject(MAAViewModel())
}
