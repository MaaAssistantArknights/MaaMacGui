//
//  FightSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct FightSettingsView: View {
    @Binding var config: FightConfiguration

    @State private var useCustomStage = false
    @State private var dropItemList: [(name: String, id: String)] = []

    var body: some View {
        Form {
            Section {
                HStack(spacing: 20) {
                    if useCustomStage || stageNotListed {
                        TextField("关卡名", text: $config.stage)
                    } else {
                        Picker("关卡选择", selection: $config.stage) {
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
                .animation(.default, value: config.stage)
            }

            if useCustomStage || stageNotListed {
                Text("<无忧梦呓>请使用特殊关卡名，如AveMujica-8").foregroundStyle(.secondary)
            }

            Divider()

            Section {
                TextField(value: $config.medicine, format: .number) {
                    Toggle("吃理智药", isOn: useMedicine)
                }

                TextField(value: $config.stone, format: .number) {
                    Toggle("吃源石", isOn: useStone)
                }

                TextField(value: $config.times, format: .number) {
                    Toggle("指定次数", isOn: limitBattles)
                }

                Picker(selection: $config.series) {
                    Text(verbatim: "AUTO").tag(0)
                    ForEach((1...6).reversed(), id: \.self) { i in
                        Text(verbatim: "\(i)").tag(i)
                    }
                    Text("不使用").tag(Int?.none)
                } label: {
                    Toggle("连战次数", isOn: seriesBattles)
                }
            }

            Divider()

            Section {
                Picker(selection: dropItemIdx) {
                    Text("").tag(nil as Int?)
                    ForEach(Array(zip(dropItemList.indices, dropItemList)), id: \.0) {
                        Text($1.0).tag($0 as Int?)
                    }
                } label: {
                    Toggle("指定材料", isOn: dropItemToggle)
                }
                if dropItemToggle.wrappedValue {
                    TextField(value: dropItemCount, format: .number) {
                        Text("刷取数量")
                    }
                }
            }.onAppear {
                do {
                    try FightConfiguration.initDropItems("zh-cn")
                } catch let err {
                    print(String(localized: "Read item_index.json failed: \(err.localizedDescription)"))
                }
                dropItemList = FightConfiguration.dropItems.map {
                    (name: $0.item.name, id: $0.id)
                }
                dropItem = config.drops?.first
            }

            Divider()

            Section {
                Toggle("博朗台碎石模式", isOn: $config.DrGrandet)
                Toggle("无限吃48小时内过期的理智药", isOn: useExpiringMedicine)
            }

            Divider()

            TextField(text: $config.penguin_id) {
                Toggle("企鹅物流汇报ID", isOn: $config.report_to_penguin)
            }

            Divider()

            Section {
                Toggle(String(localized: "启用周计划"), isOn: $config.useWeeklySchedule)
                if config.useWeeklySchedule {
                    Text((String(localized: "此处星期根据游戏时间计算（每日 4:00 刷新），而非现实时间。例如游戏在 4:00 刷新，则 3:59 仍算作前一天。")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]) {
                        ForEach(weekdayRange, id: \.self) { day in
                            Toggle(weekdayLabel(for: day), isOn: weekdayBinding(for: day))
                        }
                    }
                }
            }
        }
        .padding()
        .animation(.default, value: useCustomStage)
        .animation(.default, value: config.useWeeklySchedule)
    }

    private var useExpiringMedicine: Binding<Bool> {
        Binding {
            config.expiring_medicine ?? 0 > 0
        } set: {
            config.expiring_medicine = $0 ? 999 : nil
        }
    }

    private var useMedicine: Binding<Bool> {
        Binding {
            config.medicine != nil
        } set: {
            config.medicine = $0 ? 999 : nil
        }
    }

    private var useStone: Binding<Bool> {
        Binding {
            config.stone != nil
        } set: {
            config.stone = $0 ? 0 : nil
        }
    }

    private var limitBattles: Binding<Bool> {
        Binding {
            config.times != nil
        } set: {
            config.times = $0 ? 5 : nil
        }
    }

    private var seriesBattles: Binding<Bool> {
        Binding {
            config.series != nil
        } set: {
            config.series = $0 ? 0 : nil
        }
    }

    @State private var dropItem: (String, Int)? = nil {
        didSet {
            if dropItemToggle.wrappedValue {
                config.drops =
                    if let dropItem {
                        [dropItem.0: dropItem.1]
                    } else {
                        nil
                    }
            }
        }
    }

    private var dropItemIdx: Binding<Int?> {
        Binding {
            guard let id = dropItem?.0 else { return nil }
            return FightConfiguration.id2index[id]
        } set: {
            dropItem =
                if let idx = $0 {
                    (dropItemList[idx].id, dropItemCount.wrappedValue)
                } else {
                    nil
                }
        }
    }

    private var dropItemCount: Binding<Int> {
        Binding {
            dropItem?.1 ?? 5
        } set: {
            guard dropItem != nil else { return }
            dropItem!.1 = $0
        }
    }

    private var dropItemToggle: Binding<Bool> {
        Binding {
            config.drops != nil
        } set: {
            config.drops =
                if $0 {
                    if let dropItem { [dropItem.0: dropItem.1] } else { nil }
                } else {
                    nil
                }
        }
    }

    private var isUsingCustomStage: Binding<Bool> {
        Binding {
            useCustomStage || stageNotListed
        } set: { newValue in
            if !newValue {
                config.stage = ""
            }
            useCustomStage = newValue
        }
    }

    private var stageNotListed: Bool { !listedStages.contains(config.stage) }
    private let listedStages = ["", "1-7", "CE-6", "AP-5", "CA-5", "LS-6", "Annihilation"]

    // MARK: - Weekly Schedule

    private let weekdayRange = 1...7
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    private func weekdayLabel(for day: Int) -> String {
        weekdaySymbols[day - 1]
    }

    private func weekdayBinding(for day: Int) -> Binding<Bool> {
        Binding {
            config.weeklySchedule[day]
        } set: {
            config.weeklySchedule[day] = $0
        }
    }
}

struct FightSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        FightSettingsView(config: .constant(.init()))
    }
}
