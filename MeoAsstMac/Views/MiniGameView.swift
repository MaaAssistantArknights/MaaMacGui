//
//  MiniGameView.swift
//  MAA
//
//  Created by ninekirin on 3/8/2025.
//

import SwiftUI

struct MiniGameView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @SceneStorage("selectedMiniGame") private var selection = MiniGameOption.sideStoryStore.taskName
    @State private var selectedGame = MiniGameOption.greenTicketStore.tag
    @State private var taskParams: Any?

    var body: some View {
        VStack(spacing: 20) {
            TimelineView(.everyMinute) { context in
                Picker("选择小游戏", selection: $selectedGame) {
                    Section("当期活动") {
                        ForEach(otaMiniGames, id: \.Value) { game in
                            if game.isValid(at: context.date) {
                                Text(game.displayName).tag(game.tag)
                            }
                        }
                    }
                    Section("常驻活动") {
                        ForEach(MiniGameOption.allCases, id: \.self) { game in
                            Text(game.displayName).tag(game.tag)
                        }
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: context.date) {
                    if !selectedGame.isValid(at: $1) {
                        selectedGame = MiniGameOption.greenTicketStore.tag
                    }
                }
            }

            Button("开始游戏") {
                startMiniGame()
            }
            .disabled(viewModel.status != .idle)
            .buttonStyle(.borderedProminent)

            Divider()

            switch selectedGame.taskName {
            case "MiniGame@PixelPaint@Begin":
                PixelPaintView(params: $taskParams)
            default:
                ScrollView {
                    LazyVStack {
                        Text(selectedGame.instructions)
                    }
                }
            }
        }
        .padding()
        .animation(.default, value: selectedGame)
        .onChange(of: otaMiniGames, initial: true) {
            for game in $1 {
                if game.Value == selection {
                    selectedGame = game.tag
                    return
                }
            }
            for game in MiniGameOption.allCases {
                if game.taskName == selection {
                    selectedGame = game.tag
                    return
                }
            }
        }
        .onChange(of: selectedGame) {
            selection = $1.taskName
        }
    }

    private var otaMiniGames: [MAAStageActivity.MiniGame] {
        viewModel.stageActivity?.miniGame ?? []
    }

    private func startMiniGame() {
        Task {
            try await viewModel.miniGame(name: selectedGame.taskName, params: taskParams)
        }
    }
}

enum MiniGameOption: String, CaseIterable {
    case sideStoryStore
    case greenTicketStore
    case yellowTickerStore
    case reclamationStore

    var taskName: String {
        switch self {
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
        case .greenTicketStore:
            return String(localized: "绿票商店")
        case .yellowTickerStore:
            return String(localized: "黄票商店")
        case .sideStoryStore:
            return String(localized: "活动商店")
        case .reclamationStore:
            return String(localized: "生息演算商店")
        }
    }

    var instructions: String {
        switch self {
        case .greenTicketStore:
            String(
                localized:
                    """
                    1层全买。
                    2层买寻访凭证和招聘许可。
                    """)
        case .yellowTickerStore:
            String(
                localized:
                    """
                    购买寻访凭证。
                    请确保自己至少有258张黄票。
                    """)
        case .sideStoryStore:
            String(
                localized:
                    """
                    请在活动商店页面开始。
                    不买无限池。
                    """)
        case .reclamationStore:
            String(
                localized:
                    """
                    请在活动商店页面开始。
                    """)
        }
    }
}

@available(*, unavailable, message: "This type is only for localization key extraction.")
private enum LocalizableMiniGameKey {
}

struct MiniGameView_Previews: PreviewProvider {
    static var previews: some View {
        MiniGameView()
            .environmentObject(MAAViewModel())
    }
}

private struct MiniGameTag: Hashable {
    let instructions: String
    let taskName: String
    let activation: Date?
    let expiry: Date?

    func isValid(at date: Date = .now) -> Bool {
        guard let activation, let expiry else {
            return true
        }
        return date >= activation && date <= expiry
    }
}

extension MiniGameOption {
    fileprivate var tag: MiniGameTag {
        .init(
            instructions: instructions, taskName: taskName,
            activation: nil, expiry: nil)
    }
}

extension MAAStageActivity.MiniGame {
    var displayName: String {
        if let DisplayKey {
            return NSLocalizedString(DisplayKey, value: Display, comment: "")
        } else {
            return Display
        }
    }

    fileprivate var tag: MiniGameTag {
        let defaultTip = Tip ?? ""
        let tip: String
        if let TipKey {
            tip = NSLocalizedString(TipKey, value: defaultTip, comment: "")
        } else {
            tip = defaultTip
        }
        return .init(
            instructions: tip, taskName: Value,
            activation: startTime, expiry: expireTime)
    }

    func isValid(at date: Date = .now) -> Bool {
        date >= startTime && date <= expireTime
    }
}
