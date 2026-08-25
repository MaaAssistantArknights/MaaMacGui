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

    var body: some View {
        Form {
            Section {
                Toggle("使用备选关卡", isOn: $config.useOptionalStage)
                    .help("从上往下选择当天第一个开放的关卡；全部关闭时跳过任务")
                    .onChange(of: config.useOptionalStage) { _, enabled in
                        if enabled, config.stagePlan.isEmpty {
                            config.stagePlan = [config.stage]
                        } else if !enabled, let first = config.stagePlan.first {
                            config.stage = first
                        }
                    }

                if config.useOptionalStage {
                    StagePlanEditor(
                        stages: $config.stagePlan,
                        server: viewModel.clientChannel.fightStageServer,
                        activities: scheduleActivities,
                        choices: stageChoices)
                } else {
                    HStack(spacing: 20) {
                        if useCustomStage || stageNotListed {
                            TextField("关卡名", text: $config.stage)
                        } else {
                            Picker("关卡选择", selection: $config.stage) {
                                ForEach(baseStageChoices) { choice in
                                    Text(choice.title).tag(choice.value)
                                }
                            }
                        }
                        Toggle("手动输入关卡名", isOn: isUsingCustomStage)
                    }
                    .animation(.default, value: config.stage)
                }
            }

            if !config.useOptionalStage && (useCustomStage || stageNotListed) {
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
                    ForEach((1...10).reversed(), id: \.self) { i in
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

    private var stageNotListed: Bool {
        !baseStageChoices.contains { $0.value == config.stage }
    }

    private var baseStageChoices: [FightStageChoice] {
        [
            .init(value: "", title: String(localized: "当前/上次")),
            .init(value: "1-7", title: "1-7"),
            .init(value: "CE-6", title: "CE-6"),
            .init(value: "AP-5", title: "AP-5"),
            .init(value: "CA-5", title: "CA-5"),
            .init(value: "LS-6", title: "LS-6"),
            .init(value: "SK-5", title: "SK-5"),
            .init(value: "Annihilation", title: String(localized: "剿灭模式")),
        ]
    }

    private var stageChoices: [FightStageChoice] {
        let known = Set(baseStageChoices.map(\.value))
        let activities = viewModel.stageActivity?.fightScheduleData
        let activityChoices =
            activities?.activeStageValues(at: Date())
            .filter { !known.contains($0) }
            .map { FightStageChoice(value: $0, title: $0) } ?? []
        return baseStageChoices + activityChoices
    }

    private var scheduleActivities: FightStageSchedule.ActivityData? {
        viewModel.stageActivity?.fightScheduleData
    }

}

struct FightSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        FightSettingsView(config: .constant(.init()))
            .environmentObject(MAAViewModel())
    }
}

private struct FightStageChoice: Identifiable {
    let value: String
    let title: String
    var id: String { value }
}

// MARK: - StagePlanEditor

private struct StagePlanEditor: View {
    @Environment(\.defaultMinListRowHeight) private var rowHeight

    @Binding var stages: [String]
    let server: FightStageSchedule.Server
    let activities: FightStageSchedule.ActivityData?
    let choices: [FightStageChoice]

    @State private var selection: Int?

    private let schedule = FightStageSchedule()

    var body: some View {
        List(selection: $selection) {
            ForEach(stages.indices, id: \.self) { index in
                stageRow(at: index)
                    .tag(index)
            }
            .onMove(perform: moveStage)
        }
        .frame(height: min(max(CGFloat(stages.count + 1) * rowHeight, 2 * rowHeight), 6 * rowHeight))

        HStack {
            Button(action: addStage) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("添加备选关卡")

            Button(action: deleteStage) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("删除备选关卡")
            .disabled(stages.count <= 1 || selection == nil)
        }
    }

    private func stageRow(at index: Int) -> some View {
        let stage = stages[index]
        let isOpen = schedule.isOpen(stage, server: server, activities: activities)

        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            TextField("当前/上次", text: $stages[index])
            Menu {
                ForEach(choices) { choice in
                    Button(choice.title) {
                        stages[index] = choice.value
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
            }
            .menuStyle(.borderlessButton)
            .help("选择关卡")

            Image(systemName: isOpen ? "checkmark.circle.fill" : "clock.fill")
                .foregroundStyle(isOpen ? .green : .orange)
                .help(isOpen ? "今天开放" : "今天不开放")

            if index < stages.count - 1,
                schedule.blocksFollowingStages(stage, activities: activities)
            {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("该常驻关卡会使后续备选关卡无法执行")
            }
        }
    }

    private func moveStage(source: IndexSet, destination: Int) {
        stages.move(fromOffsets: source, toOffset: destination)
        selection = nil
    }

    private func addStage() {
        stages.append("")
        selection = stages.count - 1
    }

    private func deleteStage() {
        guard let selection, stages.indices.contains(selection) else { return }
        stages.remove(at: selection)
        self.selection = stages.indices.last
    }
}
