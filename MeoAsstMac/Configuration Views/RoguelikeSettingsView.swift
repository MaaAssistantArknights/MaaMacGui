//
//  RoguelikeSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct RoguelikeSettingsView: View {
    @Binding var config: RoguelikeConfiguration

    var body: some View {
        Form {
            generalSettings()
            Divider()
            goldSettings()
            Divider()
            squadSettings()
        }
        .animation(.default, value: config.use_support)
        .animation(.default, value: config.start_with_elite_two)
        .padding()
    }

    @ViewBuilder private func generalSettings() -> some View {
        Picker("肉鸽主题：", selection: $config.theme) {
            ForEach(RoguelikeConfiguration.Theme.allCases, id: \.self) {
                Text($0.description).tag($0)
            }
        }

        Picker("肉鸽难度：", selection: $config.difficulty) {
            ForEach(config.theme.difficulties) {
                Text($0.description).tag($0)
            }
        }

        Picker("策略：", selection: $config.mode) {
            ForEach(config.theme.modes, id: \.self) {
                Text($0.description).tag($0)
            }
        }

        TextField("最多探索次数：", value: $config.starts_count, format: .number)
    }

    @ViewBuilder private func goldSettings() -> some View {
        Toggle("投资源石锭", isOn: $config.investment_enabled)
        Toggle("刷新商店（指路鳞）", isOn: $config.refresh_trader_with_dice)
        Toggle("储备源石锭达到上限时停止", isOn: $config.stop_when_investment_full)

        TextField("最多投资源石锭数量：", value: $config.investments_count, format: .number)

        Toggle("在第五层BOSS前暂停", isOn: $config.stop_at_final_boss)
    }

    @ViewBuilder private func squadSettings() -> some View {
        Picker("开局分队：", selection: $config.squad) {
            ForEach(config.theme.squads, id: \.self) { squad in
                Text(squad).tag(squad)
            }
        }

        Picker("开局职业组：", selection: $config.roles) {
            ForEach(config.theme.roles, id: \.self) { role in
                Text(role).tag(role)
            }
        }

        TextField("开局干员（单个）：", text: $config.core_char)

        Toggle("“开局干员”使用助战", isOn: $config.use_support)
        if config.use_support {
            Toggle("可以使用非好友助战", isOn: $config.use_nonfriend_support)
        }

        Toggle("凹开局干员精二直升", isOn: $config.start_with_elite_two)
        if config.start_with_elite_two {
            Toggle("只凹直升不作战", isOn: $config.only_start_with_elite_two)
        }
    }
}

struct RoguelikeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RoguelikeSettingsView(config: .constant(.init()))
    }
}

// MARK: - Constants

extension RoguelikeConfiguration.Mode {
    var description: String {
        switch self {
        case .exp:
            NSLocalizedString("刷分/奖励点数，尽可能稳定地打更多层数", comment: "")
        case .investment:
            NSLocalizedString("刷源石锭，第一层投资完就退出", comment: "")
        case .collectible:
            NSLocalizedString("凹开局，然后凹开局奖励", comment: "")
        case .clpPds:
            NSLocalizedString("刷坍缩范式，尽可能地积累坍缩值", comment: "")
        case .squad:
            NSLocalizedString("刷月度小队，尽可能稳定地打更多层数", comment: "")
        case .exploration:
            NSLocalizedString("刷深入调查，尽可能稳定地打更多层数", comment: "")
        }
    }
}

extension RoguelikeConfiguration.Theme: CustomStringConvertible {
    var description: String {
        switch self {
        case .Phantom:
            return NSLocalizedString("傀影与猩红血钻", comment: "")
        case .Mizuki:
            return NSLocalizedString("水月与深蓝之树", comment: "")
        case .Sami:
            return NSLocalizedString("探索者的银凇止境", comment: "")
        case .Sarkaz:
            return NSLocalizedString("萨卡兹的无终奇语", comment: "")
        }
    }

    var difficulties: [RoguelikeConfiguration.Difficulty] {
        switch self {
        case .Phantom:
            return []
        case .Mizuki:
            return RoguelikeConfiguration.Difficulty.upto(maximum: 15)
        case .Sami:
            return RoguelikeConfiguration.Difficulty.upto(maximum: 15)
        case .Sarkaz:
            return RoguelikeConfiguration.Difficulty.upto(maximum: 18)
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
