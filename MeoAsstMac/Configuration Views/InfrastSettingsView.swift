//
//  InfrastSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct InfrastSettingsView: View {
    @Environment(\.defaultMinListRowHeight) private var rowHeight
    @Environment(\.isEnabled) private var isEnabled

    @Binding var config: InfrastConfiguration

    var body: some View {
        VStack {
            Form {
                Picker("基建模式", selection: $config.mode) {
                    Text("常规模式").tag(InfrastConfiguration.Mode.default)
                    Text("队列轮换").tag(InfrastConfiguration.Mode.rotation)
                    Text("自定义基建配置").tag(InfrastConfiguration.Mode.custom)
                }
                if config.mode == .custom {
                    customPlanView
                } else {
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
        .onAppear {
            if isEnabled { config.refreshCustomPlanSelection() }
        }
        .onChange(of: config.mode) { config.reloadCustomPlan() }
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

    @ViewBuilder private var customPlanView: some View {
        VStack {
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
            }
            .id(refreshCustomPlans)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Picker("班次", selection: $config.plan_index) {
                    if config.customPlan.hasPeriods {
                        let index = try? config.customPlan.select(-1, at: context.date).index
                        Text("时间轮换（\(config.customPlan.name(at: index ?? 0))）").tag(-1)
                    }
                    ForEach(Array(config.customPlan.plans.enumerated()), id: \.offset) { index, plan in
                        Text(plan.name ?? "\(index)").tag(index)
                    }
                }
            }

            if let error = config.customPlanError {
                Text("自定义基建配置文件解析错误：\(error)")
                    .foregroundStyle(.red)
            } else if config.customPlan.hasMixedPeriods {
                Text("自定义基建配置仅有部分计划存在时间段，请全部设置时间段或全部留空。")
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 20) {
                Button("打开自定义排班文件夹…") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: customInfrastDirectory.path)
                }
                Button("重新加载文件") {
                    config.reloadCustomPlan()
                    refreshCustomPlans.toggle()
                }
            }
        }
    }

    // MARK: - State Wrappers

    private var customPlan: Binding<String> {
        Binding {
            config.filename
        } set: {
            var updated = config
            updated.filename = $0
            updated.reloadCustomPlan(resetSelection: true)
            config = updated
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
