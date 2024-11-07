//
//  RoguelikeSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct RoguelikeSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let id: UUID

    private var config: Binding<RoguelikeConfiguration> {
        viewModel.taskConfig(id: id)
    }

    var body: some View {
        Form {
            generalSettings()
            Divider()
            goldSettings()
            Divider()
            squadSettings()
        }
        .animation(.default, value: config.use_support.wrappedValue)
        .animation(.default, value: config.start_with_elite_two.wrappedValue)
        .padding()
    }

    @ViewBuilder private func generalSettings() -> some View {
        Picker("肉鸽主题：", selection: config.theme) {
            ForEach(RoguelikeTheme.allCases, id: \.rawValue) { theme in
                Text("\(theme.description)").tag(theme)
            }
        }
        .onChange(of: config.wrappedValue.theme) { newValue in
            config.wrappedValue.mode = 0
            config.wrappedValue.squad = newValue.squads.first ?? ""
        }

        Picker("肉鸽难度：", selection: config.difficulty) {
            ForEach(config.theme.wrappedValue.difficulties) {
                Text($0.description).tag($0.id)
            }
        }

        Picker("策略：", selection: config.mode) {
            ForEach(config.theme.wrappedValue.modes) {
                Text($0.description).tag($0.id)
            }
        }

        TextField("最多探索次数：", value: config.starts_count, format: .number)
    }

    @ViewBuilder private func goldSettings() -> some View {
        Toggle("投资源石锭", isOn: config.investment_enabled)
        Toggle("刷新商店（指路鳞）", isOn: config.refresh_trader_with_dice)
        Toggle("储备源石锭达到上限时停止", isOn: config.stop_when_investment_full)

        TextField("最多投资源石锭数量：", value: config.investments_count, format: .number)
    }

    @ViewBuilder private func squadSettings() -> some View {
        Picker("开局分队：", selection: config.squad) {
            ForEach(config.theme.wrappedValue.squads, id: \.self) { squad in
                Text(squad).tag(squad)
            }
        }

        Picker("开局职业组：", selection: config.roles) {
            ForEach(config.wrappedValue.theme.roles, id: \.self) { role in
                Text(role).tag(role)
            }
        }

        TextField("开局干员（单个）：", text: config.core_char)

        Toggle("“开局干员”使用助战", isOn: config.use_support)
        if config.use_support.wrappedValue {
            Toggle("可以使用非好友助战", isOn: config.use_nonfriend_support)
        }

        Toggle("凹开局干员精二直升", isOn: config.start_with_elite_two)
        if config.start_with_elite_two.wrappedValue {
            Toggle("只凹直升不作战", isOn: config.only_start_with_elite_two)
        }
    }
}

struct RoguelikeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RoguelikeSettingsView(id: UUID())
            .environmentObject(MAAViewModel())
    }
}

// MARK: - Constants

enum RoguelikeTheme: String, CaseIterable, Codable, CustomStringConvertible {
    case Phantom
    case Mizuki
    case Sami
    case Sarkaz

    var description: String {
        switch self {
        case .Phantom:
            return NSLocalizedString("傀影", comment: "")
        case .Mizuki:
            return NSLocalizedString("水月", comment: "")
        case .Sami:
            return NSLocalizedString("萨米", comment: "")
        case .Sarkaz:
            return NSLocalizedString("萨卡兹", comment: "")
        }
    }
}

struct RoguelikeDifficulty: CustomStringConvertible, Equatable, Identifiable {
    let id: Int

    var description: String {
        switch id {
        case Int.max:
            return NSLocalizedString("最高难度", comment: "")
        case -1:
            return NSLocalizedString("当前难度", comment: "")
        default:
            return "\(id)"
        }
    }

    static let max = RoguelikeDifficulty(id: Int.max)
    static let current = RoguelikeDifficulty(id: -1)

    static func upto(maximum: Int) -> [RoguelikeDifficulty] {
        [.max] + (0...maximum).reversed().map { RoguelikeDifficulty(id: $0) }
    }
}

struct RoguelikeMode: CustomStringConvertible, Equatable, Identifiable {
    let id: Int

    var description: String {
        switch id {
        case 0: NSLocalizedString("刷等级，尽可能稳定地打更多层数", comment: "")
        case 1: NSLocalizedString("刷源石锭，第一层投资完就退出", comment: "")
        case 4: NSLocalizedString("刷开局，到达第三层后直接退出", comment: "")
        case 5: NSLocalizedString("刷坍缩范式，尽可能地积累坍缩值", comment: "")
        default: NSLocalizedString("未知策略 \(self.id)", comment: "")
        }
    }

    var shortDescription: String {
        switch id {
        case 0: NSLocalizedString("优先层数", comment: "")
        case 1: NSLocalizedString("优先投资", comment: "")
        case 4: NSLocalizedString("烧开水", comment: "")
        case 5: NSLocalizedString("刷坍缩", comment: "")
        default: NSLocalizedString("未知策略 \(self.id)", comment: "")
        }
    }

    static let commons = [0, 1, 4].map { RoguelikeMode(id: $0) }
}

extension RoguelikeTheme {
    var difficulties: [RoguelikeDifficulty] {
        switch self {
        case .Phantom:
            return [.current]
        case .Mizuki:
            return RoguelikeDifficulty.upto(maximum: 15) + [.current]
        case .Sami:
            return RoguelikeDifficulty.upto(maximum: 15) + [.current]
        case .Sarkaz:
            return RoguelikeDifficulty.upto(maximum: 18) + [.current]
        }
    }

    var modes: [RoguelikeMode] {
        switch self {
        case .Sami:
            return RoguelikeMode.commons + [RoguelikeMode(id: 5)]
        default:
            return RoguelikeMode.commons
        }
    }

    var squads: [String] {
        switch self {
        case .Phantom:
            [
                "指挥分队", "集群分队", "后勤分队", "矛头分队",
                "突击战术分队", "堡垒战术分队", "远程战术分队", "破坏战术分队",
                "研究分队", "高规格分队",
            ]
        case .Mizuki:
            [
                "心胜于物分队", "物尽其用分队", "以人为本分队",
                "指挥分队", "集群分队", "后勤分队", "矛头分队",
                "突击战术分队", "堡垒战术分队", "远程战术分队", "破坏战术分队",
                "研究分队", "高规格分队",
            ]
        case .Sami:
            [
                "指挥分队", "集群分队", "后勤分队", "矛头分队",
                "突击战术分队", "堡垒战术分队", "远程战术分队", "破坏战术分队",
                "高规格分队", "特训分队",
                "科学主义分队", "生活至上分队", "永恒狩猎分队",
            ]
        case .Sarkaz:
            [
                "魂灵护送分队", "博闻广记分队", "蓝图测绘分队",
                "指挥分队", "集群分队", "后勤分队", "矛头分队",
                "突击战术分队", "堡垒战术分队", "远程战术分队", "破坏战术分队",
                "高规格分队", "因地制宜分队",
                "点刺成锭分队", "拟态学者分队", "异想天开分队",
            ]
        }
    }

    var roles: [String] {
        ["先手必胜", "稳扎稳打", "取长补短", "随心所欲"]
    }
}
