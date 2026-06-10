//
//  MiniGameView.swift
//  MAA
//
//  Created by ninekirin on 3/8/2025.
//

import SwiftUI

struct MiniGameView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @SceneStorage("selectedMiniGame") private var selectedGame = MiniGameOption.greenTicketStore

    var body: some View {
        VStack(spacing: 20) {
            Picker("选择小游戏", selection: $selectedGame) {
                ForEach(MiniGameOption.allCases, id: \.self) { game in
                    Text(game.displayName).tag(game)
                }
            }
            .pickerStyle(.menu)

            VStack {
                Text(selectedGame.displayName)
                    .font(.title2)
                    .bold()
                    .padding()
                Text(selectedGame.instructions)
            }
            .animation(.easeInOut(duration: 0.2), value: selectedGame)

            Button("开始游戏") {
                startMiniGame()
            }
            .disabled(viewModel.status != .idle)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func startMiniGame() {
        Task {
            try await viewModel.miniGame(name: selectedGame.taskName)
        }
    }
}

enum MiniGameOption: String, CaseIterable {
    case positionalFootballTournament
    case rebuildingMandate
    case honeyFruit
    case greenGrass
    case atConversationRoom
    case greenTicketStore
    case yellowTickerStore
    case sideStoryStore
    case reclamationStore
    case osKarlanTradeTechnology
    case pvFireworksOrganizingCommittee
    case strongholdProtocolAlliance

    var taskName: String {
        switch self {
        case .positionalFootballTournament:
            return "MiniGame@PF@Begin"
        case .rebuildingMandate:
            return "MiniGame@RebuildingMandate@Begin"
        case .honeyFruit:
            return "MiniGame@ALL@GreenGrass@DuelChannel@Begin"
        case .greenGrass:
            return "MiniGame@ALL@GreenGrass@DuelChannel@Begin"
        case .atConversationRoom:
            return "MiniGame@AT@ConversationRoom"
        case .greenTicketStore:
            return "GreenTicket@Store@Begin"
        case .yellowTickerStore:
            return "YellowTicket@Store@Begin"
        case .sideStoryStore:
            return "SS@Store@Begin"
        case .reclamationStore:
            return "RA@Store@Begin"
        case .osKarlanTradeTechnology:
            return "MiniGame@OS@Begin"
        case .pvFireworksOrganizingCommittee:
            return "MiniGame@PV@Begin"
        case .strongholdProtocolAlliance:
            return "MiniGame@SPA@Begin"
        }
    }

    var displayName: String {
        switch self {
        case .positionalFootballTournament:
            return String(localized: "阵地足球锦标赛")
        case .rebuildingMandate:
            return String(localized: "RM-次生预案")
        case .honeyFruit:
            return String(localized: "争锋频道：蜜果城")
        case .greenGrass:
            return String(localized: "争锋频道：青草城")
        case .atConversationRoom:
            return String(localized: "AT-相谈室")
        case .greenTicketStore:
            return String(localized: "绿票商店")
        case .yellowTickerStore:
            return String(localized: "黄票商店")
        case .sideStoryStore:
            return String(localized: "活动商店")
        case .reclamationStore:
            return String(localized: "生息演算商店")
        case .osKarlanTradeTechnology:
            return String(localized: "OS-喀兰贸易技术研发部")
        case .pvFireworksOrganizingCommittee:
            return String(localized: "PV-烟花筹委会")
        case .strongholdProtocolAlliance:
            return String(localized: "卫戍协议：盟约")
        }
    }

    var instructions: String {
        switch self {
        case .positionalFootballTournament:
            String(localized:
                """
                手动通过教程关卡后，进入 PF-1 进行手动编队，
                要求仅编入 ｢克洛丝｣ 单个干员，
                并回到在活动关卡界面点击 PF-1 后开始任务。
                """)
        case .rebuildingMandate:
            String(localized:
                """
                过完新手教程后进入前哨支点，滑动到界面最左侧。
                """)
        case .honeyFruit:
            String(localized:
                """
                手动跳过教程对话，然后可以直接退出。
                在活动主界面（右下角有“加入赛事”处）开始任务。

                跟着鸭总喝口汤。
                """)
        case .greenGrass:
            String(localized:
                """
                手动跳过教程对话，然后可以直接退出。
                在活动主界面（右下角有“加入赛事”处）开始任务。

                跟着鸭总喝口汤。
                """)
        case .atConversationRoom:
            String(localized:
                """
                在活动主界面（右下角有“开始营业/继续营业”处）开始任务。
                等待自动完成相谈室对话。
                """)
        case .greenTicketStore:
            String(localized:
                """
                1层全买。
                2层买寻访凭证和招聘许可。
                """)
        case .yellowTickerStore:
            String(localized:
                """
                购买寻访凭证。
                请确保自己至少有258张黄票。
                """)
        case .sideStoryStore:
            String(localized:
                """
                请在活动商店页面开始。
                不买无限池。
                """)
        case .reclamationStore:
            String(localized:
                """
                请在活动商店页面开始。
                """)
        case .osKarlanTradeTechnology:
            String(localized:
                """
                在活动主界面（右下角有“开始重建”处）开始任务。
                """)
        case .pvFireworksOrganizingCommittee:
            String(localized:
                """
                在活动页面最左侧开始
                """)
        case .strongholdProtocolAlliance:
            String(localized:
                """
                在活动主界面（有“独立模拟”处开始任务）
                手动通关“标准模拟”可以更快的刷分
                只能刷等级奖励，拿蚀刻章得打完所有的“关键目标”
                """)
        }
    }
}

struct MiniGameView_Previews: PreviewProvider {
    static var previews: some View {
        MiniGameView()
            .environmentObject(MAAViewModel())
    }
}
