//
//  CopilotView.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import SwiftUI

struct CopilotView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let url: URL

    var body: some View {
        if let copilot = MAACopilot(url: url) {
            VStack(spacing: 20) {
                CopilotConfigView(config: $viewModel.copilot).padding(.top)

                Divider()

                ScrollView {
                    CopilotDescriptionView(pilot: copilot)
                }
            }
            .task(id: url) { updateCopilot() }
            .animation(.default, value: formation)
        } else {
            Text("文件格式错误")
        }
    }

    private func updateCopilot() {
        guard let copilot = MAACopilot(url: url) else { return }
        if copilot.type == "SSS" {
            viewModel.copilot = .sss(.init(filename: url.path))
        } else {
            viewModel.copilot = .regular(.init(filename: url.path))
        }
    }

    private var copilot: MAACopilot? {
        MAACopilot(url: url)
    }

    private var formation: Bool {
        switch viewModel.copilot {
        case .regular(let innerConfig):
            innerConfig.formation
        default:
            false
        }
    }
}

// MARK: - Copilot Config

private struct CopilotConfigView: View {
    @Binding var config: CopilotConfiguration?

    var body: some View {
        switch config {
        case .regular(let innerConfig):
            let binding = Binding {
                innerConfig
            } set: { newValue in
                self.config = .regular(newValue)
            }
            RegularCopilotConfigView(config: binding)
        case .sss(let innerConfig):
            let binding = Binding {
                innerConfig
            } set: { newValue in
                self.config = .sss(newValue)
            }
            SSSCopilotConfigView(config: binding)
        case .none:
            EmptyView()
        }
    }
}

private struct RegularCopilotConfigView: View {
    @Binding var config: RegularCopilotConfiguration

    var body: some View {
        VStack {
            Toggle("自动编队", isOn: $config.formation)
            if config.formation {
                HStack {
                    Picker("编队栏位", selection: $config.formation_index) {
                        Text("当前").tag(0)
                        ForEach(0..<RegularCopilotConfiguration.formationCount, id: \.self) { index in
                            Text("\(index + 1)").tag(index + 1)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("忽视干员属性要求", isOn: $config.ignore_requirements)
                    Toggle("补充低信赖干员", isOn: $config.add_trust)
                }
                HStack {
                    Picker("助战模式", selection: $config.support_unit_usage) {
                        ForEach(RegularCopilotConfiguration.SupportUnitUsage.allCases, id: \.self) {
                            Text($0.description).tag($0)
                        }
                    }
                    if config.support_unit_usage == .specific {
                        TextField("干员名称", text: $config.support_unit_name)
                            .frame(maxWidth: 150)
                    }
                }
                .animation(.default, value: config.support_unit_usage)
            }
        }
    }
}

private struct SSSCopilotConfigView: View {
    @Binding var config: SSSCopilotConfiguration

    var body: some View {
        HStack {
            Text("循环次数")
            TextField("1", value: $config.loop_times, format: .number)
        }
        .frame(maxWidth: 130)
    }
}

// MARK: - Copilot Document

private struct CopilotDescriptionView: View {
    let pilot: MAACopilot

    var body: some View {
        if let title = pilot.doc?.title {
            Text(title).font(.title2)
        }
        if let details = pilot.doc?.details {
            Text(details)
        }

        if let equipments = pilot.equipment {
            Text("装备：") + Text(equipments.joined(separator: ", "))
        }

        if let strategy = pilot.strategy {
            Text(strategy)
        }

        if pilot.opers.count > 0 {
            VStack {
                ForEach(pilot.opers, id: \.name) { oper in
                    Text(oper.description)
                }
            }
        }

        if let groups = pilot.groups {
            VStack {
                ForEach(groups, id: \.name) { group in
                    Text(group.name) + Text(verbatim: ": ")
                        + Text(group.opers.map(\.description).joined(separator: " / "))
                }
            }
        }

        if let toolmen = pilot.tool_men {
            Text(toolmen.sorted { $0.key < $1.key }.map { "\($1)\($0)" }.joined(separator: ", "))
        }
    }
}

#Preview("Regular Copilot Config") {
    let url = Bundle.main.resourceURL!
        .appendingPathComponent("resource")
        .appendingPathComponent("copilot")
        .appendingPathComponent("OF-1_credit_fight")
        .appendingPathExtension("json")

    VStack {
        CopilotView(url: url)
    }
    .environmentObject(MAAViewModel())
}

#Preview("SSS Copilot Config") {
    let url = Bundle.main.resourceURL!
        .appendingPathComponent("resource")
        .appendingPathComponent("copilot")
        .appendingPathComponent("old")
        .appendingPathComponent("约翰老妈新建地块_Mama_Johns_New_Plate")
        .appendingPathComponent("SSS_约翰老妈新建地块")
        .appendingPathExtension("json")

    VStack {
        CopilotView(url: url)
    }
    .environmentObject(MAAViewModel())
}
