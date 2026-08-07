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

    var body: some View {
        VStack {
            Form {
                Picker("基建模式", selection: $config.mode) {
                    Text("常规模式").tag(InfrastConfiguration.Mode.default)
                    Text("队列轮换").tag(InfrastConfiguration.Mode.rotation)
                    Text("自定义基建配置").tag(InfrastConfiguration.Mode.custom)
                }
                if config.mode == .rotation {
                    Picker("轮换方式", selection: $config.rotation_style) {
                        ForEach(InfrastConfiguration.RotationStyle.allCases, id: \.self) { style in
                            Text(style.description).tag(style)
                        }
                    }
                }
                if config.usesCustomJsonPlan {
                    customPlanView
                } else if config.usesRotationStationPreset {
                    stationPresetLayoutForm
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
                if config.usesRotationStationPreset {
                    stationPresetRoomList
                } else if config.mode != .rotation {
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
        .animation(.default, value: config.rotation_style)
        .padding()
    }

    @ViewBuilder private var stationPresetLayoutForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                layoutStepper(title: "制造站", value: $config.preset_layout.mfg_count, range: StationPresetLayout.limits.mfg)
                layoutStepper(title: "贸易站", value: $config.preset_layout.trade_count, range: StationPresetLayout.limits.trade)
                layoutStepper(title: "发电站", value: $config.preset_layout.power_count, range: StationPresetLayout.limits.power)
            }
            .onChange(of: config.preset_layout) { _ in
                config.syncPresetRoomsAfterLayoutChange()
            }
        }
    }

    @ViewBuilder private func layoutStepper(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper("\(title) \(value.wrappedValue)", value: value, in: range)
    }

    @ViewBuilder private var stationPresetRoomList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("本次切换设施")
                    .font(.headline)
                Spacer()
                Button("全选") {
                    config.selectAllPresetRooms()
                }
                Button("清空") {
                    config.clearAllPresetRooms()
                }
            }
            List {
                Section {
                    ForEach(StationPresetRoomList.rooms(for: config.preset_layout)) { room in
                        Toggle(room.label, isOn: presetRoomBinding(for: room.id))
                    }
                } footer: {
                    Text("多班次请添加多个基建任务，每个任务配置一个班次。")
                }
            }
        }
        .frame(height: 14 * rowHeight)
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
        if config.usesRotationStationPreset {
            stationPresetPreferenceForm
        } else {
            defaultPreferenceForm
        }
    }

    @ViewBuilder private var defaultPreferenceForm: some View {
        sharedOperationalToggles
        sharedReceptionToggles
        sharedTrainingToggle
    }

    @ViewBuilder private var stationPresetPreferenceForm: some View {
        Toggle("切换后干员休整", isOn: $config.preset_rest)
        Toggle("使用无人机", isOn: $config.station_preset_drones.enable)
        if config.station_preset_drones.enable {
            Picker("无人机设施", selection: $config.station_preset_drones.room) {
                ForEach(StationPresetDrones.Room.allCases, id: \.self) { room in
                    Text(room.description).tag(room)
                }
            }
            Picker("设施序号", selection: $config.station_preset_drones.index) {
                ForEach(droneIndexRange, id: \.self) { index in
                    Text("\(index)").tag(index)
                }
            }
            Picker("使用时机", selection: $config.station_preset_drones.order) {
                ForEach(StationPresetDrones.Order.allCases, id: \.self) { order in
                    Text(order.description).tag(order)
                }
            }
            .onChange(of: config.station_preset_drones.room) { _ in
                let range = droneIndexRange
                if !range.contains(config.station_preset_drones.index), let first = range.first {
                    config.station_preset_drones.index = first
                }
            }
        }
        sharedOperationalToggles
        sharedReceptionToggles
        sharedTrainingToggle
    }

    @ViewBuilder private var sharedOperationalToggles: some View {
        Toggle("源石碎片自动补货", isOn: $config.replenish)
        Toggle("不将已进驻的干员放入宿舍", isOn: $config.dorm_notstationed_enabled)
        Toggle("宿舍空余位置蹭信赖", isOn: $config.dorm_trust_enabled)
    }

    @ViewBuilder private var sharedReceptionToggles: some View {
        Toggle("会客室信息板收取信用", isOn: $config.reception_message_board)
        Toggle("会客室接收线索", isOn: $config.reception_receive_clue)
        Toggle("会客室线索交流", isOn: $config.reception_clue_exchange)
        Toggle("会客室赠送线索", isOn: $config.reception_send_clue)
    }

    @ViewBuilder private var sharedTrainingToggle: some View {
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

            Picker("班次", selection: $config.plan_index) {
                try? MAAInfrast(path: config.filename).planList
            }

            if config.plan_index >= 0 {
                Toggle("完成后自动切换到下个班次", isOn: $config.auto_advance_plan_index)
            }

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

    // MARK: - State Wrappers

    private var customPlan: Binding<String> {
        Binding {
            config.filename
        } set: {
            config.plan_index = 0
            config.filename = $0
        }
    }

    private var disabledFacilities: [InfrastConfiguration.Facility] {
        InfrastConfiguration.Facility.allCases.filter { facility in
            !config.facility.contains(facility)
        }
    }

    private var droneIndexRange: [Int] {
        switch config.station_preset_drones.room {
        case .manufacture:
            return Array(1 ... config.preset_layout.mfg_count)
        case .trading:
            return Array(1 ... config.preset_layout.trade_count)
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

    private func presetRoomBinding(for roomID: String) -> Binding<Bool> {
        Binding {
            config.preset_selected_rooms.contains(roomID)
        } set: { isSelected in
            if isSelected {
                if !config.preset_selected_rooms.contains(roomID) {
                    config.preset_selected_rooms.append(roomID)
                }
            } else {
                config.preset_selected_rooms.removeAll { $0 == roomID }
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
        plan_153_3, plan_243_3, plan_243_4, plan_252_3, plan_333_3, plan_facility_preset_3,
    ]

    fileprivate static let plan_facility_preset_3 = bundledPath(for: "facility_preset_3_shifts_daily.json")

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
