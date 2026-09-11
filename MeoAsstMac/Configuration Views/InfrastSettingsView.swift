//
//  InfrastSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct InfrastSettingsView: View {
    @Environment(\.defaultMinListRowHeight) private var rowHeight

    @Binding var config: InfrastConfiguration
    var connectionScope: String = ""

    var body: some View {
        if config.mode == .custom {
            ScrollView {
                settingsContent
            }
        } else {
            settingsContent
        }
    }

    private var settingsContent: some View {
        VStack {
            if config.mode == .custom {
                customPlanView
            } else {
                Form {
                    modePicker
                    Picker("无人机用途", selection: $config.drones) {
                        ForEach(droneUsages, id: \.self) { usage in
                            Text(usage.description).tag(usage)
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .top) {
                if config.mode != .rotation {
                    facilityList
                }
                Form {
                    if config.mode != .rotation {
                        Section {
                            Text("基建工作心情阈值: \(config.threshold * 100, specifier: "%.0f")%")
                            Slider(value: $config.threshold, in: 0...1)
                        }
                        Divider()
                    }
                    Section {
                        preferenceForm
                    }
                }
            }
        }
        .animation(.default, value: config.mode)
        .padding()
    }

    @ViewBuilder private var facilityList: some View {
        List {
            Section {
                ForEach(config.facility) { facility in
                    Toggle(facility.description, isOn: facilityBinding(for: facility))
                }
                .onMove { source, destination in
                    config.facility.move(fromOffsets: source, toOffset: destination)
                }
            } header: {
                Text("已启用")
            }

            Section {
                ForEach(disabledFacilities) { facility in
                    Toggle(facility.description, isOn: facilityBinding(for: facility))
                }
            } header: {
                Text("未启用")
            }
        }
        .animation(.default, value: config.facility)
        .frame(height: 12 * rowHeight)
    }

    @ViewBuilder private var preferenceForm: some View {
        Toggle("宿舍空余位置蹭信赖", isOn: $config.dorm_trust_enabled)
        Toggle("不将已进驻的干员放入宿舍", isOn: $config.dorm_notstationed_enabled)
        Toggle("源石碎片自动补货", isOn: $config.replenish)
        Toggle("会客室信息板收取信用", isOn: $config.reception_message_board)
        Toggle("训练完成后继续尝试专精当前技能", isOn: $config.continue_training)
    }

    private var modePicker: some View {
        Picker("基建模式", selection: $config.mode) {
            Text("常规模式").tag(InfrastConfiguration.Mode.default)
            Text("队列轮换").tag(InfrastConfiguration.Mode.rotation)
            Text("自定义基建配置").tag(InfrastConfiguration.Mode.custom)
        }
    }

    @ViewBuilder private var customPlanView: some View {
        VStack(spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("基建模式").frame(width: 96, alignment: .trailing).foregroundStyle(.secondary)
                    modePicker.labelsHidden()
                }
                GridRow {
                    Text("方案").frame(width: 96, alignment: .trailing).foregroundStyle(.secondary)
                    Picker("方案", selection: customPlan) {
                        Section {
                            ForEach(customInfrastPaths, id: \.self) { path in
                                path.label
                            }
                        } header: {
                            Text("自定义排班")
                        }

                        Section {
                            ForEach(String.bundledPlans, id: \.self) { path in
                                path.label
                            }
                        } header: {
                            Text("内置排班")
                        }
                    }.labelsHidden()
                }
                GridRow {
                    Text("基建计划").frame(width: 96, alignment: .trailing).foregroundStyle(.secondary)
                    Picker("基建计划", selection: planSelection) {
                        Text("自动").tag(-1)
                        try? MAAInfrast(path: config.filename).planList
                    }.labelsHidden()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)

            rotationStatusView

            HStack(spacing: 20) {
                Button("打开自定义排班文件夹…") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: customInfrastDirectory.path)
                }
                Button("重新加载文件") {
                    refreshCustomPlans.toggle()
                }
            }
        }
    }

    private var planSelection: Binding<Int> {
        Binding {
            config.rotation?.automatic == true ? -1 : config.plan_index
        } set: { index in
            var rotation = config.rotation ?? InfrastRotation()
            rotation.automatic = index == -1
            if rotation.current?.status != .running && rotation.current?.status != .prepared {
                rotation.current = nil
            }
            config.rotation = rotation
            if index >= 0 { config.plan_index = index }
        }
    }

    private var intervalSelection: Binding<Bool> {
        Binding {
            config.rotation?.intervalMinutes != nil
        } set: { custom in
            var rotation = config.rotation ?? InfrastRotation()
            rotation.intervalMinutes = custom ? 1440 : nil
            config.rotation = rotation
        }
    }

    private var intervalHours: Binding<Double> {
        Binding {
            (config.rotation?.intervalMinutes ?? 1440) / 60
        } set: { hours in
            var rotation = config.rotation ?? InfrastRotation()
            guard let minutes = InfrastRotation.validMinutes(hours * 60) else { return }
            rotation.intervalMinutes = minutes
            config.rotation = rotation
        }
    }

    @ViewBuilder private var rotationStatusView: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 6) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: config.filename)),
                    let plan = try? JSONDecoder().decode(MAAInfrast.self, from: data), !plan.plans.isEmpty
                {
                    let fingerprint = InfrastRotationRun.fingerprint(data)
                    let rotation = config.rotation ?? InfrastRotation()
                    let nextIndex =
                        rotation.nextIndex(
                            fingerprint: fingerprint, count: plan.plans.count, fallback: config.plan_index,
                            connection: connectionScope) ?? 0
                    let last = rotation.lastCompleted
                    let validLast =
                        last?.fingerprint == fingerprint && last?.connection == connectionScope
                        && plan.plans.indices.contains(last?.index ?? -1)
                    let attempt = rotation.current
                    let validAttempt = attempt?.fingerprint == fingerprint && attempt?.connection == connectionScope

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            Text("上次换班").frame(width: 96, alignment: .trailing).foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                if let last {
                                    Text(verbatim: last.name).fontWeight(.medium)
                                    Text(last.completedAt, format: .dateTime.month().day().hour().minute())
                                        .monospacedDigit().foregroundStyle(.secondary)
                                    if !validLast { Text("记录已不适用").foregroundStyle(.secondary) }
                                } else {
                                    Text("暂无完成记录").foregroundStyle(.secondary)
                                }
                            }
                        }
                        GridRow {
                            Text("本次换班").frame(width: 96, alignment: .trailing).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                if let attempt, validAttempt {
                                    Text(verbatim: attempt.name)
                                    Text(attemptLabel(attempt.status)).foregroundStyle(.secondary)
                                } else {
                                    Text(verbatim: plan.plans[nextIndex].name ?? String(nextIndex + 1))
                                    Text("待执行").foregroundStyle(.secondary)
                                }
                            }
                        }
                        GridRow {
                            Text("下次换班建议").frame(width: 96, alignment: .trailing).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                if let last, validLast {
                                    let suggestedIndex = (last.index + 1) % plan.plans.count
                                    Text(verbatim: plan.plans[suggestedIndex].name ?? String(suggestedIndex + 1))
                                    if let date = rotation.suggestedDate(
                                        fingerprint: fingerprint, connection: connectionScope)
                                    {
                                        Text(date, format: .dateTime.month().day().hour().minute())
                                            .monospacedDigit().foregroundStyle(.secondary)
                                        if date <= context.date { Text("已到建议时间").foregroundStyle(.orange) }
                                    } else {
                                        Text("暂无有效时长").foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("下次完成后计算").foregroundStyle(.secondary)
                                }
                            }
                        }
                        GridRow {
                            Text("建议间隔").frame(width: 96, alignment: .trailing).foregroundStyle(.secondary)
                            Picker("建议间隔", selection: intervalSelection) {
                                Text("按排班表时长").tag(false)
                                Text("自定义固定间隔").tag(true)
                            }.labelsHidden().fixedSize()
                        }
                        if intervalSelection.wrappedValue {
                            GridRow {
                                Text("间隔（小时）").frame(width: 96, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("间隔（小时）", value: intervalHours, format: .number)
                                    .labelsHidden().frame(width: 100)
                            }
                        }
                    }
                    Divider().padding(.vertical, 4)
                    if rotation.automatic {
                        Text("自动按计划顺序选班；由你启动换班，时间段不参与选班。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("建议不改变手动选择的计划。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("暂无有效排班计划").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
        }
    }

    private func attemptLabel(_ status: InfrastRotation.Attempt.Status) -> String {
        switch status {
        case .prepared: String(localized: "待执行")
        case .running: String(localized: "执行中")
        case .completed: String(localized: "已完成")
        case .incomplete: String(localized: "本次未完成")
        }
    }

    // MARK: - State Wrappers

    private var customPlan: Binding<String> {
        Binding {
            config.filename
        } set: {
            config.plan_index = 0
            config.filename = $0
            config.rotation?.current = nil
        }
    }

    private var disabledFacilities: [InfrastConfiguration.Facility] {
        InfrastConfiguration.Facility.allCases.filter { facility in
            !config.facility.contains(facility)
        }
    }

    private func facilityBinding(for facility: InfrastConfiguration.Facility) -> Binding<Bool> {
        Binding {
            config.facility.contains(facility)
        } set: { newValue in
            if newValue {
                config.facility.append(facility)
            } else {
                config.facility.removeAll { $0 == facility }
            }
        }
    }

    private var droneUsages: [InfrastConfiguration.DroneUsage] {
        var usages = [InfrastConfiguration.DroneUsage.NotUse]

        if config.mode == .rotation {
            return InfrastConfiguration.DroneUsage.allCases
        } else if config.mode == .custom {
            return usages
        }

        if config.facility.contains(.Mfg) {
            usages.append(contentsOf: [.Chip, .CombatRecord, .OriginStone, .PureGold, .SyntheticJade])
        }

        if config.facility.contains(.Trade) {
            usages.append(.Money)
        }

        return usages
    }

    // MARK: - File Paths

    @State private var refreshCustomPlans = false

    private var customInfrastPaths: [String] {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: customInfrastDirectory,
                includingPropertiesForKeys: [.contentTypeKey],
                options: .skipsHiddenFiles)
        else { return [] }

        // Dummy state to force refreshing files
        _ = refreshCustomPlans

        return
            urls
            .filter { url in
                let value = try? url.resourceValues(forKeys: [.contentTypeKey])
                return value?.contentType == .json
            }
            .map(\.path)
    }

    private var customInfrastDirectory: URL {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("infrast")

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        return directory
    }
}

// MARK: - Infrast Plan

extension String {
    fileprivate var label: some View {
        if let plan = try? MAAInfrast(path: self) {
            return Text(plan.title ?? self).tag(self)
        } else {
            return Text("无效文件").tag(self)
        }
    }

    fileprivate static let bundledPlans = [
        plan_153_3, plan_243_3, plan_243_4, plan_252_3, plan_333_3,
    ]

    fileprivate static let plan_153_3 = bundledPath(for: "153_layout_3_times_a_day.json")
    fileprivate static let plan_243_3 = bundledPath(for: "243_layout_3_times_a_day.json")
    fileprivate static let plan_243_4 = bundledPath(for: "243_layout_4_times_a_day.json")
    fileprivate static let plan_252_3 = bundledPath(for: "252_layout_3_times_a_day.json")
    fileprivate static let plan_333_3 = bundledPath(for: "333_layout_for_Orundum_3_times_a_day.json")

    private static func bundledPath(for name: String) -> String {
        Bundle.main.resourceURL?
            .appendingPathComponent("resource")
            .appendingPathComponent("custom_infrast")
            .appendingPathComponent(name)
            .path ?? ""
    }
}

struct InfrastSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        InfrastSettingsView(config: .constant(.init()))
    }
}
