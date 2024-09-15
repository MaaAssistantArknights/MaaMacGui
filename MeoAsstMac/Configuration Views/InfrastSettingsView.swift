//
//  InfrastSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct InfrastSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Environment(\.defaultMinListRowHeight) private var rowHeight
    let id: UUID

    private var config: Binding<InfrastConfiguration> {
        viewModel.taskConfig(id: id)
    }

    var body: some View {
        VStack {
            HStack {
                facilityList
                preferenceForm
            }

            if useCustomPlan.wrappedValue {
                customPlanView
            }
        }
        .animation(.default, value: useCustomPlan.wrappedValue)
        .padding()
    }

    @ViewBuilder private var facilityList: some View {
        List {
            Section {
                ForEach(config.facility.wrappedValue) { facility in
                    Toggle(facility.description, isOn: facilityBinding(for: facility))
                }
                .onMove { source, destination in
                    config.facility.wrappedValue.move(fromOffsets: source, toOffset: destination)
                }
            } header: {
                Text(NSLocalizedString("已启用", comment: ""))
            }

            Section {
                ForEach(disabledFacilities) { facility in
                    Toggle(facility.description, isOn: facilityBinding(for: facility))
                }
            } header: {
                Text(NSLocalizedString("未启用", comment: ""))
            }
        }
        .animation(.default, value: config.facility.wrappedValue)
        .frame(height: 12 * rowHeight)
    }

    @ViewBuilder private var preferenceForm: some View {
        Form {
            Section {
                Text(NSLocalizedString("无人机用途：", comment: ""))
                Picker("", selection: config.drones) {
                    ForEach(MAAInfrastDroneUsage.allCases, id: \.self) { usage in
                        Text(usage.description).tag(usage)
                    }
                }
            }

            Divider().padding(.top)

            Section {
                Text("基建工作心情阈值: \(config.threshold.wrappedValue * 100, specifier: "%.0f")%")
                Slider(value: config.threshold, in: 0 ... 1)
            }

            Divider()

            Section {
                Toggle("宿舍空余位置蹭信赖", isOn: config.dorm_trust_enabled)
                Toggle("不将已进驻的干员放入宿舍", isOn: config.dorm_notstationed_enabled)
                Toggle("源石碎片自动补货", isOn: config.replenish)
            }

            Divider()

            Toggle("启用自定义基建配置(beta)", isOn: useCustomPlan)
        }
    }

    @ViewBuilder private var customPlanView: some View {
        VStack {
            Picker("方案：", selection: customPlan) {
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

            Picker("班次：", selection: config.plan_index) {
                try? MAAInfrast(path: config.filename.wrappedValue).planList
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
            config.filename.wrappedValue
        } set: {
            config.plan_index.wrappedValue = 0
            config.filename.wrappedValue = $0
        }
    }

    private var useCustomPlan: Binding<Bool> {
        Binding {
            config.mode.wrappedValue == 10000
        } set: {
            config.mode.wrappedValue = $0 ? 10000 : 0
        }
    }

    private var disabledFacilities: [MAAInfrastFacility] {
        MAAInfrastFacility.allCases.filter { facility in
            !config.facility.wrappedValue.contains(facility)
        }
    }

    private func facilityBinding(for facility: MAAInfrastFacility) -> Binding<Bool> {
        Binding {
            config.facility.wrappedValue.contains(facility)
        } set: { newValue in
            if newValue {
                config.facility.wrappedValue.append(facility)
            } else {
                config.facility.wrappedValue.removeAll { $0 == facility }
            }
        }
    }

    // MARK: - File Paths

    @State private var refreshCustomPlans = false

    private var customInfrastPaths: [String] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: customInfrastDirectory,
            includingPropertiesForKeys: [.contentTypeKey],
            options: .skipsHiddenFiles)
        else { return [] }

        // Dummy state to force refreshing files
        _ = refreshCustomPlans

        return urls
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

private extension String {
    var label: some View {
        if let plan = try? MAAInfrast(path: self) {
            return Text(plan.title ?? self).tag(self)
        } else {
            return Text("无效文件").tag(self)
        }
    }

    static let bundledPlans = [
        plan_153_3, plan_243_3, plan_243_4, plan_252_3, plan_333_3
    ]

    static let plan_153_3 = bundledPath(for: "153_layout_3_times_a_day.json")
    static let plan_243_3 = bundledPath(for: "243_layout_3_times_a_day.json")
    static let plan_243_4 = bundledPath(for: "243_layout_4_times_a_day.json")
    static let plan_252_3 = bundledPath(for: "252_layout_3_times_a_day.json")
    static let plan_333_3 = bundledPath(for: "333_layout_for_Orundum_3_times_a_day.json")

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
        InfrastSettingsView(id: UUID())
            .environmentObject(MAAViewModel())
    }
}
