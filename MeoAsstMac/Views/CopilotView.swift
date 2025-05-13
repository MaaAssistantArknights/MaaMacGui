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
                pilotConfiguration()

                Divider()

                ScrollView {
                    pilotDescription(pilot: copilot)
                }
            }
            .task(id: url) { updateCopilot() }
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

    private func addToCopilotList() {
        guard let pilot = MAACopilot(url: url) else { return }
        viewModel.addToCopilotList(copilot: pilot, url: url)
    }

    // MARK: - Copilot Config

    @ViewBuilder private func pilotConfiguration() -> some View {
        switch viewModel.copilot {
        case .regular(let innerConfig):
            let binding = Binding<RegularCopilotConfiguration> {
                innerConfig
            } set: { newValue in
                viewModel.copilot = .regular(newValue)
            }
            VStack {
                HStack {
                    Toggle("自动编队", isOn: binding.formation)
                    Toggle("信赖干员", isOn: binding.add_trust)
                }

                Button(action: addToCopilotList) {
                    Label("添加到战斗列表", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)

                if viewModel.copilotListConfig.items.contains(where: { $0.filename == innerConfig.filename }) {
                    Text("已添加到战斗列表")
                        .foregroundColor(.green)
                } else {
                    Text("未添加到战斗列表")
                        .foregroundColor(.red)
                }
            }

        case .sss(let innerConfig):
            let binding = Binding<SSSCopilotConfiguration> {
                innerConfig
            } set: { newValue in
                viewModel.copilot = .sss(newValue)
            }
            HStack {
                Text("循环次数")
                TextField("1", value: binding.loop_times, format: .number)
            }
            .frame(maxWidth: 130)

        case .none:
            EmptyView()
        }
    }

    // MARK: - Copilot Document

    @ViewBuilder private func pilotDescription(pilot: MAACopilot) -> some View {
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

struct CopilotView_Previews: PreviewProvider {
    static let url = Bundle.main.resourceURL!
        .appendingPathComponent("resource")
        .appendingPathComponent("copilot")
        .appendingPathComponent("OF-1_credit_fight")
        .appendingPathExtension("json")

    static var previews: some View {
        VStack {
            CopilotView(url: url)
        }
        .environmentObject(MAAViewModel())
    }
}
