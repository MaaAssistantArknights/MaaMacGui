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
            Toggle(NSLocalizedString("领取每日/每周任务奖励", comment: ""), isOn: config.award)

            Toggle(NSLocalizedString("领取所有邮件奖励", comment: ""), isOn: config.mail)

            Toggle(NSLocalizedString("进行每日免费单抽", comment: ""), isOn: config.recruit)

            Toggle(NSLocalizedString("领取幸运墙合成玉奖励", comment: ""), isOn: config.orundum)

            Toggle(NSLocalizedString("领取限时开采许可合成玉奖励", comment: ""), isOn: config.mining)

            Toggle(NSLocalizedString("领取五周年赠送月卡奖励", comment: ""), isOn: config.specialaccess)
        }
        .padding()
    }
}

struct AwardSettings_Preview: PreviewProvider {
    static var previews: some View {
        AwardSettingsView(id: UUID())
            .environmentObject(MAAViewModel())
    }
}
