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
        .padding()
    }

    @ViewBuilder private func generalSettings() -> some View {
        Picker("肉鸽主题：", selection: config.theme) {
            ForEach(RoguelikeTheme.allCases, id: \.rawValue) { theme in
                Text("\(theme.description)").tag(theme)
            }
        }

        Picker("策略：", selection: config.mode) {
            Text("刷蜡烛，尽可能稳定地打更多层数").tag(0)
            Text("刷源石锭，第一层投资完就退出").tag(1)
        }

        TextField("最多探索次数：", value: config.starts_count, format: .number)
    }

    @ViewBuilder private func goldSettings() -> some View {
        HStack {
            Toggle("投资源石锭", isOn: config.investment_enabled)
            Spacer()
            Toggle("储备源石锭达到上限时停止", isOn: config.stop_when_investment_full)
            Spacer()
        }

        TextField("最多投资源石锭数量：", value: config.investments_count, format: .number)
    }

    @ViewBuilder private func squadSettings() -> some View {
        Picker("开局分队：", selection: config.squad) {
            ForEach(roguelikeSquads[config.theme.wrappedValue] ?? [], id: \.self) { squad in
                Text(squad).tag(squad)
            }
        }

        Picker("开局职业组：", selection: config.roles) {
            ForEach(roguelikeRoles, id: \.self) { role in
                Text(role).tag(role)
            }
        }

        TextField("开局干员（单个）：", text: config.core_char)
    }
}

// struct RoguelikeSettingsView_Previews: PreviewProvider {
//    @State static var config: any MAATaskConfiguration = RoguelikeConfiguration.default()
//    static var previews: some View {
//        RoguelikeSettingsView(config: $config)
//    }
// }

// MARK: - Constants

enum RoguelikeTheme: String, CaseIterable, Codable, CustomStringConvertible {
    case Phantom
    case Mizuki

    var description: String {
        switch self {
        case .Phantom:
            return NSLocalizedString("傀影", comment: "")
        case .Mizuki:
            return NSLocalizedString("水月", comment: "")
        }
    }
}

private let roguelikeSquads: [RoguelikeTheme: [String]] = [
    .Phantom: ["指挥分队", "集群分队", "后勤分队", "矛头分队",
               "突击战术分队", "堡垒战术分队", "远程战术分队", "破坏战术分队",
               "研究分队", "高规格分队"],
    .Mizuki: ["心胜于物分队", "物尽其用分队", "以人为本分队",
              "指挥分队", "集群分队", "后勤分队", "矛头分队",
              "突击战术分队", "堡垒战术分队", "远程战术分队", "破坏战术分队",
              "研究分队", "高规格分队"]
]

private let roguelikeRoles = ["先手必胜", "稳扎稳打", "取长补短", "随心所欲"]
