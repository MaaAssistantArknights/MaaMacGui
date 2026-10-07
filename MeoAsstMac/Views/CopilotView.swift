//
//  CopilotView.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import SwiftUI

struct CopilotView: View {
    let context: CopilotContext

    var body: some View {
        @Bindable var context = context
        if context.category == .list {
            if let set = context.copilotSet {
                switch context.content {
                case .copilot(_, let kind, let copilot):
                    CopilotConfigView(
                        kind: kind, isList: true, config: $context.config, adverse: adverseSelection(context)
                    ) {
                        CopilotDescriptionView(pilot: copilot)
                    }
                case .invalid:
                    Text("文件格式错误")
                case .pending:
                    ProgressView().controlSize(.small)
                default:
                    CopilotConfigView(kind: set.kind, isList: true, config: $context.config) {
                        CopilotSetDescriptionView(set: set.data)
                    }
                }
            } else {
                Text("请选择作业项目")
            }
        } else {
            switch context.content {
            case .copilot(let url, let kind, let copilot):
                Button("加入作业列表") {
                    Task {
                        let isRaid: Bool? = kind == .regular ? context.config.preferAdverse : nil
                        if await context.addToList(at: url, isRaid: isRaid) {
                            context.category = .list
                            context.selection = nil
                        }
                    }
                }
                .buttonStyle(.bordered)
                // SSSCopilot takes a single filename only.
                .disabled(kind == .sss || (context.copilotSet?.kind != nil && context.copilotSet?.kind != kind))
                CopilotConfigView(
                    kind: kind, isList: false, config: $context.config, adverse: adverseSelection(context)
                ) {
                    CopilotDescriptionView(pilot: copilot)
                }
                .onChange(of: url, initial: true) { _, _ in
                    if kind == .regular {
                        context.config.preferAdverse = copilot.difficulty == 2
                    }
                }
            case .set(let url, let set):
                Button("激活此作业集") {
                    Task {
                        await context.updateSet(at: url, set: set)
                        context.category = .list
                    }
                }
                .buttonStyle(.borderedProminent)
                Divider().padding(.vertical)
                CopilotSetDescriptionView(set: set)
            case .directory, nil:
                Text("请选择作业项目")
            case .invalid:
                Text("文件格式错误")
            case .pending:
                ProgressView().controlSize(.small)
            }
        }
    }
}

// MARK: - Copilot Config

private struct CopilotConfigView<D: View>: View {
    let kind: MAACopilot.Kind
    let isList: Bool

    @Binding var config: CopilotConfiguration
    var adverse: Binding<Bool>?

    let description: D

    init(
        kind: MAACopilot.Kind,
        isList: Bool,
        config: Binding<CopilotConfiguration>,
        adverse: Binding<Bool>? = nil,
        @ViewBuilder description: () -> D
    ) {
        self.kind = kind
        self.isList = isList
        self._config = config
        self.adverse = adverse
        self.description = description()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch kind {
                case .regular:
                    RegularCopilotConfigView(isList: isList, config: $config, adverse: adverse)
                    Divider()
                case .sss:
                    if !isList {
                        CopilotLoopView(config: $config)
                        Divider()
                    }
                case .paradox:
                    EmptyView()
                }
                VStack(alignment: .leading, spacing: 12) {
                    description
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
        }
        .padding(.top)
    }
}

@MainActor
private func adverseSelection(_ context: CopilotContext) -> Binding<Bool>? {
    if context.category == .list {
        guard case .copilot = context.content, context.selection != nil else {
            return nil
        }
        return Binding(
            get: {
                context.copilotList.first { $0.id == context.selection }?.isRaid == true
            },
            set: { newValue in
                guard let id = context.selection else { return }
                context.setRaid(id, isRaid: newValue)
            })
    }
    guard case .copilot(_, .regular, _) = context.content else {
        return nil
    }
    return Binding(
        get: { context.config.preferAdverse },
        set: { context.config.preferAdverse = $0 })
}

private struct RegularCopilotConfigView: View {
    let isList: Bool
    @Binding var config: CopilotConfiguration
    var adverse: Binding<Bool>?
    @State private var showAdditionalEditor = false

    var body: some View {
        GroupBox("自动编队") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("自动编队", isOn: $config.formation)
                    .help("自动编队可能无法识别带有「特别关注」标记的干员")

                if config.formation {
                    Picker("编队栏位", selection: $config.formation_index) {
                        Text("当前").tag(0)
                        ForEach(1...4, id: \.self) { index in
                            Text("\(index)").tag(index)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("忽略干员属性要求", isOn: $config.ignore_requirements)
                        .help("跳过技能等级、模组等前置检查，可能导致作业无法正常运行；干员精英化等级仍须满足要求。")
                    Toggle("补充低信赖干员", isOn: $config.add_trust)

                    Picker("借助战", selection: $config.support_unit_usage) {
                        ForEach(CopilotConfiguration.SupportUnitUsage.allCases, id: \.self) {
                            Text($0.description).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("缺少一名干员时可尝试借助战；缺少多名干员时请更换作业。")

                    if config.support_unit_usage == .specific {
                        TextField("助战干员名称", text: $config.support_unit_name)
                    }

                    HStack {
                        Toggle("追加自定干员", isOn: $config.enableUserAdditional)
                        Button("编辑…") { showAdditionalEditor = true }
                            .disabled(!config.enableUserAdditional)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
        .sheet(isPresented: $showAdditionalEditor) {
            UserAdditionalEditor(config: $config)
        }

        GroupBox("作业执行") {
            VStack(alignment: .leading, spacing: 10) {
                if let adverse {
                    Picker("难度", selection: adverse) {
                        Text("普通").tag(false)
                        Text("磨难").tag(true)
                    }
                    .pickerStyle(.menu)
                    .help("磨难会在进入关卡时切换为突袭模式。")
                }
                if isList || adverse?.wrappedValue == true {
                    Toggle("吃理智药", isOn: $config.use_sanity_potion)
                }
                if !isList {
                    CopilotLoopView(config: $config)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

private struct CopilotLoopView: View {
    @Binding var config: CopilotConfiguration

    var body: some View {
        HStack {
            Toggle("循环次数", isOn: $config.enableLoop)
            if config.enableLoop {
                Stepper(value: $config.loop_times, in: 1...9_999) {
                    Text("\(config.loop_times)")
                }
                .fixedSize()
            }
        }
    }
}

private struct UserAdditionalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: CopilotConfiguration
    @State private var units: [Unit]

    private struct Unit: Identifiable {
        let id = UUID()
        var name: String
        var skill: Int
    }

    init(config: Binding<CopilotConfiguration>) {
        self._config = config
        self._units = State(
            initialValue: config.wrappedValue.user_additional.map {
                Unit(name: $0.name, skill: $0.skill)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("追加自定干员")
                .font(.headline)
            Text("按顺序追加干员；技能 0 表示保持当前技能。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($units) { $unit in
                        HStack {
                            TextField("干员名称", text: $unit.name)
                            Picker("技能序号", selection: $unit.skill) {
                                ForEach(0...3, id: \.self) { skill in
                                    Text("\(skill)").tag(skill)
                                }
                            }
                            .frame(width: 95)
                            Button {
                                units.removeAll { $0.id == unit.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("移除干员")
                        }
                    }
                }
            }
            .frame(minHeight: 80, maxHeight: 280)

            HStack {
                Button("添加") {
                    units.append(Unit(name: "", skill: 0))
                }
                .disabled(units.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    config.user_additional = units.compactMap { unit in
                        let name = unit.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        return name.isEmpty ? nil : .init(name: name, skill: unit.skill)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 460)
    }
}

// MARK: - Copilot Document

private struct CopilotDescriptionView: View {
    let pilot: MAACopilot
    @State private var level: MAAProvider.MapLevel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let level {
                Text(level.name.isEmpty ? level.code : "\(level.code) · \(level.name)")
                    .font(.headline)
            }
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
        .task(id: pilot.stage_name) {
            level = await MAAProvider.shared.mapLevel(matching: pilot.stage_name)
        }
    }
}

private struct CopilotSetDescriptionView: View {
    let set: CopilotSetData

    var body: some View {
        Text(set.name).font(.title2)
        Text(set.description)
    }
}

#Preview("Regular Copilot Config") {
    let context = CopilotContext()
    let url = URL.bundledCopilotDirectory
        .appending(path: "OF-1_credit_fight")
        .appendingPathExtension("json")
    context.selection = .init(url: url, isRaid: nil)

    return VStack {
        CopilotView(context: context)
    }
    .frame(width: 720, height: 800)
}

#Preview("SSS Copilot Config") {
    let context = CopilotContext()
    let url = URL.bundledCopilotDirectory
        .appending(path: "old/")
        .appending(path: "约翰老妈新建地块_Mama_Johns_New_Plate/")
        .appending(path: "SSS_约翰老妈新建地块")
        .appendingPathExtension("json")
    context.selection = .init(url: url, isRaid: nil)

    return VStack {
        CopilotView(context: context)
    }
    .frame(width: 720, height: 800)
}
