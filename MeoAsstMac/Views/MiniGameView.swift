//
//  MiniGameView.swift
//  MAA
//
//  Created by ninekirin on 3/8/2025.
//

import SwiftUI

struct MiniGameView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @State private var selectedGame: MiniGameOption = .greenGrass

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

enum MiniGameOption: CaseIterable {
    case greenGrass
    case atConversationRoom
    case greenTicketStore
    case yellowTickerStore
    case sideStoryStore
    case reclamationStore

    var taskName: String {
        switch self {
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
        }
    }

    var displayName: String {
        switch self {
        case .honeyFruit:
            return NSLocalizedString("争锋频道：蜜果城", comment: "")
        case .greenGrass:
            return NSLocalizedString("争锋频道：青草城", comment: "")
        case .atConversationRoom:
            return NSLocalizedString("AT-相谈室", comment: "")
        case .greenTicketStore:
            return NSLocalizedString("绿票商店", comment: "")
        case .yellowTickerStore:
            return NSLocalizedString("黄票商店", comment: "")
        case .sideStoryStore:
            return NSLocalizedString("活动商店", comment: "")
        case .reclamationStore:
            return NSLocalizedString("生息演算商店", comment: "")
        }
    }

    var instructions: String {
        switch self {
        case .honeyFruit:
            NSLocalizedString(
                """
                手动跳过教程对话，然后可以直接退出。
                在活动主界面（右下角有“加入赛事”处）开始任务。

                跟着鸭总喝口汤。
                """, comment: "")
        case .greenGrass:
            NSLocalizedString(
                """
                手动跳过教程对话，然后可以直接退出。
                在活动主界面（右下角有“加入赛事”处）开始任务。

                跟着鸭总喝口汤。
                """, comment: "")
        case .atConversationRoom:
            NSLocalizedString(
                """
                在活动主界面（右下角有“开始营业/继续营业”处）开始任务。
                等待自动完成相谈室对话。
                """, comment: "")
        case .greenTicketStore:
            NSLocalizedString(
                """
                1层全买。
                2层买寻访凭证和招聘许可。
                """, comment: "")
        case .yellowTickerStore:
            NSLocalizedString(
                """
                购买寻访凭证。
                请确保自己只少有258张黄票。
                """, comment: "")
        case .sideStoryStore:
            NSLocalizedString(
                """
                请在活动商店页面开始。
                不买无限池。
                """, comment: "")
        case .reclamationStore:
            NSLocalizedString(
                """
                请在活动商店页面开始。
                """, comment: "")
        }
    }
}

struct MiniGameView_Previews: PreviewProvider {
    static var previews: some View {
        MiniGameView()
            .environmentObject(MAAViewModel())
    }
}
