//
//  FightSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct FightSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var config: FightConfiguration

    @State private var useCustomStage = false
    @State private var dropItemList: [(name: String, id: String)] = []
    @AppStorage("MAAHideUnavailableStage") private var hideUnavailableStage = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 20) {
                    if useCustomStage || stageNotListed {
                        TextField("关卡名", text: $config.stage)
                    } else {
                        Picker("关卡选择", selection: $config.stage) {
                            Text("当前/上次").tag("")
                            ForEach(pickerStages) { stage in
                                stageLabel(stage).tag(stage.value)
                            }
                        }
                    }
                    Toggle("手动输入关卡名", isOn: isUsingCustomStage)
                }
                .animation(.default, value: config.stage)

                if !useCustomStage && !stageNotListed {
                    Toggle("隐藏未开放关卡", isOn: $hideUnavailableStage)
                    if let tip = selectedStageTip {
                        Text(tip).font(.caption).foregroundStyle(.secondary)
                    }
                }
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
        }
        .padding()
        .animation(.default, value: useCustomStage)
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

    // MARK: - Stage List

    /// In-game weekday (accounts for the 04:00 server day-rollover), per current channel.
    private var currentWeekday: Int {
        GameCalendar.yjWeekday(channel: viewModel.clientChannel)
    }

    /// Stages shown in the picker, respecting the "hide unavailable" toggle.
    /// The currently-selected stage is always kept visible so the picker never shows blank.
    private var pickerStages: [MAAStageInfo] {
        var listed = viewModel.stages.listedStages(hideClosed: hideUnavailableStage, weekday: currentWeekday)
        if !config.stage.isEmpty, !listed.contains(where: { $0.value == config.stage }),
            let selected = viewModel.stages.stageInfo(for: config.stage)
        {
            listed.insert(selected, at: 0)
        }
        return listed
    }

    /// Tip text of the currently-selected stage (e.g. open days or activity description),
    /// combined with the stage's drop material when available.
    private var selectedStageTip: String? {
        guard let stage = viewModel.stages.stageInfo(for: config.stage) else {
            return nil
        }

        var parts: [String] = []
        if !stage.tip.isEmpty {
            parts.append(stage.tip)
        }
        if let drop = dropDescription(for: stage) {
            parts.append(String(localized: "可刷取：\(drop)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// Human-readable drop material for a stage. The `drop` field is either an item id
    /// (resolved to its localized name via item_index) or already a descriptive string.
    private func dropDescription(for stage: MAAStageInfo) -> String? {
        guard let drop = stage.drop, !drop.isEmpty else { return nil }
        if let idx = FightConfiguration.id2index[drop] {
            return FightConfiguration.dropItems[idx].item.name
        }
        return drop
    }

    /// Renders a stage entry: dimmed when closed today, strikethrough when its activity expired.
    @ViewBuilder private func stageLabel(_ stage: MAAStageInfo) -> some View {
        let isOpen = stage.isStageOpen(weekday: currentWeekday)
        if stage.isOutdated {
            Text(stage.display).strikethrough().foregroundStyle(.red)
        } else if isOpen {
            Text(stage.display)
        } else {
            Text(stage.display).foregroundStyle(.secondary)
        }
    }

    private var stageNotListed: Bool {
        guard !config.stage.isEmpty else { return false }
        return viewModel.stages.stageInfo(for: config.stage) == nil
    }
}

struct FightSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        FightSettingsView(config: .constant(.init()))
            .environmentObject(MAAViewModel())
    }
}
