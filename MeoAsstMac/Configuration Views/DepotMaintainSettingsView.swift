//
//  DepotMaintainSettingsView.swift
//  MAA
//

import SwiftUI

struct DepotMaintainSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var config: DepotMaintainConfiguration

    @State private var expandedPlanIDs = Set<UUID>()
    @State private var dropItems = [(id: String, name: String)]()
    @State private var dropNames = [String: String]()
    @State private var stageDropIDs = [String: Set<String>]()
    @State private var showClearConfirmation = false
    @State private var settingsPage = SettingsPage.general

    private enum SettingsPage: Hashable {
        case general
        case advanced
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch settingsPage {
                case .general:
                    generalSettings
                case .advanced:
                    advancedSettings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            Picker("设置页面", selection: $settingsPage) {
                Text("常规设置").tag(SettingsPage.general)
                Text("高级设置").tag(SettingsPage.advanced)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 240)
            .padding(.vertical, 8)
        }
        .disabled(viewModel.status != .idle)
        .onAppear(perform: loadDropItems)
        .alert("清空全部计划？", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                config.plans.removeAll()
                expandedPlanIDs.removeAll()
            }
        } message: {
            Text("此操作无法撤销。")
        }
    }

    private var generalSettings: some View {
        Form {
            Section {
                if config.plans.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("暂无计划")
                            .font(.headline)
                        Text("添加计划或使用预设来设定目标库存。")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                } else {
                    List {
                        ForEach($config.plans) { $plan in
                            planEditor(plan: $plan)
                        }
                        .onMove { source, destination in
                            config.plans.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                    .frame(minHeight: 220, idealHeight: 380)
                }

                HStack(spacing: 0) {
                    Button("全部折叠") {
                        expandedPlanIDs.removeAll()
                    }
                    .disabled(expandedPlanIDs.isEmpty)

                    Button("清空") {
                        showClearConfirmation = true
                    }
                    .disabled(config.plans.isEmpty)

                    Button {
                        let plan = DepotMaintainConfiguration.Plan()
                        config.plans.append(plan)
                        expandedPlanIDs.insert(plan.id)
                    } label: {
                        Label("添加计划", systemImage: "plus")
                    }

                    Menu("预设") {
                        ForEach(DepotMaintainConfiguration.Preset.allCases) { preset in
                            Button(preset.title) {
                                let plans = preset.plans
                                config.plans.append(contentsOf: plans)
                                expandedPlanIDs.formUnion(plans.map(\.id))
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)
            } header: {
                Text("计划")
            } footer: {
                Text("计划可拖拽排序；每条计划开始前都会按最新库存重新计算缺口。")
            }
        }
    }

    private var advancedSettings: some View {
        Form {
            Section("任务行为") {
                Toggle("任务开始前更新库存数据", isOn: $config.updateDepot)
                Toggle("活动期间跳过", isOn: $config.skipDuringActivity)
                Toggle("资源收集限时全天开放期间跳过", isOn: $config.skipDuringResourceCollection)
            }

            Section("关卡与作战") {
                Toggle("AUTO 代理倍率", isOn: $config.useAutoSeries)
                    .help("开启后使用当前理智允许的最大代理倍率，单次掉落可能超过目标库存。")
            }

            Section("理智恢复") {
                Toggle("启用「使用药剂」勾选框", isOn: $config.enableMedicine)
                Toggle("启用「使用源石」勾选框", isOn: $config.enableStone)
                Toggle("使用 48 小时内过期的理智药", isOn: $config.useExpiringMedicine)
                    .help("对全部计划生效，包括没有单独设置药剂预算的计划。")
            }
        }
    }

    private func planEditor(plan: Binding<DepotMaintainConfiguration.Plan>) -> some View {
        let id = plan.wrappedValue.id
        let index = config.plans.firstIndex { $0.id == id }.map { $0 + 1 } ?? 0
        let current = viewModel.depot?.count(of: plan.wrappedValue.dropID)

        return DisclosureGroup(isExpanded: expansionBinding(for: id)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("关卡编号", text: stageBinding(for: plan))
                    Menu {
                        ForEach(stageChoices, id: \.self) { stage in
                            Button(stage) { stageBinding(for: plan).wrappedValue = stage }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .help("选择常用关卡")
                }

                HStack(spacing: 8) {
                    Picker("指定掉落物", selection: plan.dropID) {
                        Text("请选择").tag("")
                        ForEach(dropItems(for: plan.wrappedValue.stage), id: \.id) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    TextField("目标库存", value: plan.target, format: .number)
                        .frame(width: 110)
                }

                if config.enableMedicine {
                    HStack {
                        Toggle("使用药剂", isOn: plan.useMedicine)
                            .help("设置预算后，本计划不会因预估理智不足而提前跳过。")
                        Spacer()
                        Stepper(value: plan.medicineCount, in: 0...999) {
                            TextField("数量", value: plan.medicineCount, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                        .fixedSize()
                        .help("本计划最多使用的理智药数量；未勾选时不会实际使用。")
                    }
                }

                if config.enableStone {
                    HStack {
                        Toggle("使用源石", isOn: plan.useStone)
                            .help("设置预算后，本计划不会因预估理智不足而提前跳过。")
                        Spacer()
                        Stepper(value: plan.stoneCount, in: 0...999) {
                            TextField("数量", value: plan.stoneCount, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                        .fixedSize()
                        .help("本计划最多使用的源石数量；未勾选时不会实际使用。")
                    }
                }
            }
            .padding(.vertical, 6)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "\(index): \(plan.wrappedValue.stage.isEmpty ? String(localized: "未选择关卡") : plan.wrappedValue.stage) - \(dropName(for: plan.wrappedValue.dropID)) ×\(plan.wrappedValue.target)"
                    )
                    .lineLimit(1)
                    Text("库存 \(current.map(String.init) ?? "--") / \(plan.wrappedValue.target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    config.plans.removeAll { $0.id == id }
                    expandedPlanIDs.remove(id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除计划")
            }
        }
    }

    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding {
            expandedPlanIDs.contains(id)
        } set: { expanded in
            if expanded {
                expandedPlanIDs.insert(id)
            } else {
                expandedPlanIDs.remove(id)
            }
        }
    }

    private func stageBinding(for plan: Binding<DepotMaintainConfiguration.Plan>) -> Binding<String> {
        Binding {
            plan.wrappedValue.stage
        } set: { stage in
            let stage = FightStageSchedule.normalizedStage(stage)
            plan.wrappedValue.stage = stage
            let dropID = plan.wrappedValue.dropID
            if !dropID.isEmpty, stageDropIDs[stage]?.contains(dropID) != true {
                plan.wrappedValue.dropID = ""
            }
        }
    }

    private func dropItems(for stage: String) -> [(id: String, name: String)] {
        guard let allowedIDs = stageDropIDs[FightStageSchedule.normalizedStage(stage)] else { return [] }
        return dropItems.filter { allowedIDs.contains($0.id) }
    }

    private var stageChoices: [String] {
        let common = [
            "1-7", "R8-11", "12-17-HARD",
            "LS-6", "CE-6", "AP-5", "CA-5", "SK-5",
            "PR-A-1", "PR-A-2", "PR-B-1", "PR-B-2",
            "PR-C-1", "PR-C-2", "PR-D-1", "PR-D-2",
            "OF-1", "OF-F3",
        ]
        let activityStages = viewModel.stageActivity?.fightScheduleData.activeStageValues(at: Date()) ?? []
        return Array(Set(common + activityStages)).sorted()
    }

    private func dropName(for id: String) -> String {
        guard !id.isEmpty else { return String(localized: "未选择材料") }
        return dropNames[id] ?? id
    }

    private func loadDropItems() {
        do {
            try FightConfiguration.initDropItems(Bundle.main.preferredLocalizations.first ?? "zh-cn")
            dropItems = FightConfiguration.dropItems.map { ($0.id, $0.item.name) }
            dropNames = Dictionary(uniqueKeysWithValues: dropItems.map { ($0.id, $0.name) })
            loadStageDrops()
        } catch {
            print(String(localized: "Read item_index.json failed: \(error.localizedDescription)"))
        }
    }

    private func loadStageDrops() {
        struct StageRecord: Decodable {
            struct DropInfo: Decodable {
                let itemId: String
            }

            let code: String
            let dropInfos: [DropInfo]
        }

        let external = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("resource/stages.json")
        let bundled = Bundle.main.resourceURL!.appendingPathComponent("resource/stages.json")
        let url = FileManager.default.fileExists(atPath: external.path) ? external : bundled

        do {
            let records = try JSONDecoder().decode([StageRecord].self, from: Data(contentsOf: url))
            var result = [String: Set<String>]()
            for record in records {
                let stage = FightStageSchedule.normalizedStage(record.code)
                result[stage, default: []].formUnion(record.dropInfos.map(\.itemId))

                // stages.json does not list the fixed currencies from these resource stages.
                if stage.hasPrefix("CE-") {
                    result[stage, default: []].insert("4001")
                } else if stage.hasPrefix("AP-") {
                    result[stage, default: []].insert("4006")
                }
            }
            stageDropIDs = result
            for index in config.plans.indices {
                let stage = FightStageSchedule.normalizedStage(config.plans[index].stage)
                config.plans[index].stage = stage
                let dropID = config.plans[index].dropID
                if let allowedIDs = result[stage], !dropID.isEmpty, !allowedIDs.contains(dropID) {
                    config.plans[index].dropID = ""
                }
            }
        } catch {
            print(String(localized: "Read stages.json failed: \(error.localizedDescription)"))
        }
    }
}

struct DepotMaintainSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        DepotMaintainSettingsView(config: .constant(.init()))
            .environmentObject(MAAViewModel())
    }
}
