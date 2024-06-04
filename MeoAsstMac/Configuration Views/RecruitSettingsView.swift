//
//  RecruitSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct RecruitSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let id: UUID

    private var config: Binding<RecruitConfiguration> {
        viewModel.taskConfig(id: id)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Toggle("自动刷新3星Tags", isOn: config.refresh)

            Toggle("自动使用加急许可", isOn: config.expedite)

            Toggle("3星设置7:40而非9:00", isOn: level3UseShortTime)

            Stepper(value: config.times, in: 0 ... 1000) {
                HStack{
                    Text("每次执行时最大招募次数: ")
                    TextField("", value: config.times, format: .number)
                        .frame(maxWidth: 50)
                }
            }

            Toggle("手动确认1星", isOn: config.skip_robot)
            Toggle("自动确认3星", isOn: autoConfirm(level: 3))
            Toggle("自动确认4星", isOn: autoConfirm(level: 4))
            Toggle("自动确认5星", isOn: autoConfirm(level: 5))
            Toggle("自动确认6星", isOn: .constant(false)).disabled(true)
        }
        .padding()
    }

    private var level3UseShortTime: Binding<Bool> {
        Binding {
            config.recruitment_time["3"].wrappedValue == 460
        } set: { newValue in
            if newValue {
                config.recruitment_time["3"].wrappedValue = 460
            } else {
                config.recruitment_time["3"].wrappedValue = 540
            }
        }
    }

    private func autoConfirm(level: Int) -> Binding<Bool> {
        Binding {
            config.confirm.wrappedValue.contains(level)
        } set: { newValue in
            if newValue {
                var levels = Set(config.confirm.wrappedValue)
                levels.insert(level)
                config.confirm.wrappedValue = levels.sorted()
            } else {
                config.confirm.wrappedValue.removeAll { $0 == level }
            }
        }
    }
}

struct RecruitSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RecruitSettingsView(id: UUID())
            .environmentObject(MAAViewModel())
    }
}
