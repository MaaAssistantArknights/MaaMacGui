//
//  RecruitSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct RecruitSettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("自动刷新3星Tags", isOn: $appDelegate.autoRefresh)
            Toggle("自动使用加急许可*", isOn: $appDelegate.autoUseExpedited)
            Toggle("3星设置7:40而非9:00", isOn: $appDelegate.level3UseShortTime)

            Stepper(value: $appDelegate.recruitMaxTimes, in: 0 ... 4) {
                Text("每次执行时最大招募次数: \(appDelegate.recruitMaxTimes)").padding(.vertical)
            }

            Toggle("手动确认“支援机械”", isOn: $appDelegate.manuallySelectLevel1)
            Toggle("自动确认3星", isOn: $appDelegate.autoSelectLevel3)
            Toggle("自动确认4星", isOn: $appDelegate.autoSelectLevel4)
            Toggle("自动确认5星", isOn: $appDelegate.autoSelectLevel5)
            Toggle("自动确认6星", isOn: .constant(false)).disabled(true)
        }
    }
}

struct RecruitSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RecruitSettingsView()
    }
}
