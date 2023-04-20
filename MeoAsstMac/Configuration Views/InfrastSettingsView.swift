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
        }
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
        .animation(.default, value: config.facility.wrappedValue)
        .frame(height: 12 * rowHeight)
    }

    @ViewBuilder private var preferenceForm: some View {
        Form {
            Section {
                Text("无人机用途：")
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

            Section {
                customPlanView
            }
        }
        .animation(.default, value: useCustomPlan.wrappedValue)
    }

    @State private var showImport = false

    @ViewBuilder private var customPlanView: some View {
        Toggle("启用自定义基建配置(beta)", isOn: useCustomPlan)

        if useCustomPlan.wrappedValue {
            Picker("", selection: customPlan) {
                if case .custom = customPlan.wrappedValue {
                    Text(customPlan.wrappedValue.description).tag(customPlan.wrappedValue)
                }

                ForEach(InfrastPlan.bundled, id: \.self) { plan in
                    Text(plan.description).tag(plan)
                }

                Text("选择配置文件…").tag(InfrastPlan.import)
            }
            .padding(.top, 2)
            .onChange(of: customPlan.wrappedValue) {
                showImport = $0 == .import
            }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
                if case let .success(url) = result {
                    self.customPlan.wrappedValue = .init(path: url.path)
                }
            }

            Picker("", selection: config.plan_index) {
                try? MAAInfrast(path: config.filename.wrappedValue).planList
            }
            .padding(.top, 6)
        }
    }

    // MARK: - State Wrappers

    private var customPlan: Binding<InfrastPlan> {
        Binding {
            InfrastPlan(path: config.filename.wrappedValue)
        } set: {
            config.filename.wrappedValue = $0.path
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

    // MARK: - Infrast Plan

    enum InfrastPlan: Hashable {
        case bundled153_3
        case bundled243_3
        case bundled243_4
        case bundled252_3
        case bundled333_3

        case `import`
        case custom(String, MAAInfrast)
    }
}

extension InfrastSettingsView.InfrastPlan: CustomStringConvertible {
    init(path: String) {
        switch path {
        case Self.bundled153_3.path:
            self = .bundled153_3
            return
        case Self.bundled243_3.path:
            self = .bundled243_3
            return
        case Self.bundled243_4.path:
            self = .bundled243_4
            return
        case Self.bundled252_3.path:
            self = .bundled252_3
            return
        case Self.bundled333_3.path:
            self = .bundled333_3
            return
        default:
            break
        }

        if let plan = try? MAAInfrast(path: path) {
            self = .custom(path, plan)
        } else {
            self = .bundled153_3
        }
    }

    var description: String {
        switch self {
        case .bundled153_3:
            return NSLocalizedString("153_3", comment: "")
        case .bundled243_3:
            return NSLocalizedString("243_3", comment: "")
        case .bundled243_4:
            return NSLocalizedString("243_4", comment: "")
        case .bundled252_3:
            return NSLocalizedString("252_3", comment: "")
        case .bundled333_3:
            return NSLocalizedString("333_3", comment: "")
        case .import:
            return NSLocalizedString("选择配置文件…", comment: "")
        case let .custom(path, plan):
            return plan.title ?? plan.description ?? path
        }
    }

    static var bundled: [Self] {
        [.bundled153_3, .bundled243_3, .bundled243_4, .bundled252_3, .bundled333_3]
    }

    var path: String {
        switch self {
        case .bundled153_3:
            return bundledPath(for: "153_layout_3_times_a_day.json")
        case .bundled243_3:
            return bundledPath(for: "243_layout_3_times_a_day.json")
        case .bundled243_4:
            return bundledPath(for: "243_layout_4_times_a_day.json")
        case .bundled252_3:
            return bundledPath(for: "252_layout_3_times_a_day.json")
        case .bundled333_3:
            return bundledPath(for: "333_layout_for_Orundum_3_times_a_day.json")
        case .import:
            return ""
        case let .custom(path, _):
            return path
        }
    }

    private func bundledPath(for name: String) -> String {
        Bundle.main.resourceURL?
            .appendingPathComponent("resource")
            .appendingPathComponent("custom_infrast")
            .appendingPathComponent(name)
            .path ?? ""
    }
}

// struct InfrastSettingsView_Previews: PreviewProvider {
//    @State static var config: any MAATaskConfiguration = InfrastConfiguration.default()
//    static var previews: some View {
//        InfrastSettingsView(config: $config)
//    }
// }
