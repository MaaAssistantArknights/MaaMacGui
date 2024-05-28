//
//  FightSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct FightSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let id: UUID

    private var config: Binding<FightConfiguration> {
        viewModel.taskConfig(id: id)
    }

    @State private var useCustomStage = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 20) {
                    if useCustomStage || stageNotListed {
                        TextField("关卡名", text: config.stage)
                    } else {
                        Picker("关卡选择", selection: config.stage) {
                            Text("当前/上次").tag("")
                            Text("1-7").tag("1-7")
                            Text("CE-6").tag("CE-6")
                            Text("AP-5").tag("AP-5")
                            Text("CA-5").tag("CA-5")
                            Text("LS-6").tag("LS-6")
                            Text("剿灭模式").tag("Annihilation")
                        }
                    }
                    Toggle("手动输入关卡名", isOn: isUsingCustomStage)
                }
                .animation(.default, value: config.stage.wrappedValue)
                .animation(.default, value: useCustomStage)
            }

            Divider()

            Section {
                TextField(value: config.medicine, format: .number) {
                    Toggle("吃理智药", isOn: useMedicine)
                }

                TextField(value: config.stone, format: .number) {
                    Toggle("吃源石", isOn: useStone)
                }

                TextField(value: config.times, format: .number) {
                    Toggle("指定次数", isOn: limitBattles)
                }

                TextField(value: config.series, format: .number) {
                    Toggle("连战次数", isOn: seriesBattles)
                }

                Picker(selection: .constant(0)) {
                    // TODO: stage
                } label: {
                    Toggle("指定材料", isOn: .constant(false))
                }
                .disabled(true)
            }

            Divider()

            Section {
                Toggle("博朗台碎石模式", isOn: config.DrGrandet)
                Toggle("无限吃48小时内过期的理智药", isOn: useExpiringMedicine)
            }

            Divider()

            TextField("企鹅物流ID", text: .constant(""))
        }
        .padding()
    }

    private var useExpiringMedicine: Binding<Bool> {
        Binding {
            config.expiring_medicine.wrappedValue ?? 0 > 0
        } set: {
            config.expiring_medicine.wrappedValue = $0 ? 999 : nil
        }
    }

    private var useMedicine: Binding<Bool> {
        Binding {
            config.medicine.wrappedValue != nil
        } set: {
            config.medicine.wrappedValue = $0 ? 999 : nil
        }
    }

    private var useStone: Binding<Bool> {
        Binding {
            config.stone.wrappedValue != nil
        } set: {
            config.stone.wrappedValue = $0 ? 0 : nil
        }
    }

    private var limitBattles: Binding<Bool> {
        Binding {
            config.times.wrappedValue != nil
        } set: {
            config.times.wrappedValue = $0 ? 5 : nil
        }
    }

    private var seriesBattles: Binding<Bool> {
        Binding {
            config.series.wrappedValue != nil
        } set: {
            config.series.wrappedValue = $0 ? 1 : nil
        }
    }

    private var isUsingCustomStage: Binding<Bool> {
        Binding {
            useCustomStage || stageNotListed
        } set: { newValue in
            if !newValue {
                config.stage.wrappedValue = ""
            }
            useCustomStage = newValue
        }
    }

    private var stageNotListed: Bool { !listedStages.contains(config.stage.wrappedValue) }
    private let listedStages = ["", "1-7", "CE-6", "AP-5", "CA-5", "LS-6", "Annihilation"]
}

 struct FightSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        FightSettingsView(id: UUID())
            .environmentObject(MAAViewModel())
    }
 }
