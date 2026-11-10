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
    @State private var selectedGame = MiniGameOption.sideStoryStore.tag
    @State private var taskParams: Any?
    @AppStorage("SecretFrontEnding") private var secretFrontEnding = SecretFrontConfiguration.Ending.A
    @AppStorage("SecretFrontEvent") private var secretFrontEvent = SecretFrontConfiguration.Event.unspecified
    @State private var startError: String?

    private var isSecretFront: Bool { selectedGame.taskName == MiniGameOption.secretFront.taskName }


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

            if isSecretFront {
                Picker("目标结局", selection: $secretFrontEnding) {
                    ForEach(SecretFrontConfiguration.Ending.allCases, id: \.self) { ending in
                        Text("结局 \(ending.rawValue)").tag(ending)
                    }
                }
                .disabled(viewModel.status != .idle)
                Picker("指定事件", selection: $secretFrontEvent) {
                    ForEach(SecretFrontConfiguration.Event.allCases, id: \.self) { event in
                        Text(event.displayName).tag(event)
                    }
                }
                .disabled(viewModel.status != .idle)
                if let reason = viewModel.secretFrontUnavailableReason {
                    Text(reason)
                        .foregroundStyle(.secondary)
                }
            }

            Button("开始游戏") {
                startMiniGame()
            }
            .disabled(viewModel.status != .idle || (isSecretFront && viewModel.secretFrontUnavailableReason != nil))
            .buttonStyle(.borderedProminent)

            Divider()

            switch selectedGame.taskName {
            case "MiniGame@PixelPaint@Begin":
                PixelPaintView(params: $taskParams)
            case MiniGameOption.secretFront.taskName:
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedGame.instructions)
                    Text("运行日志").font(.headline)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(viewModel.secretFrontRun.messages.enumerated()), id: \.offset) { _, message in
                                Text(message).textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            default:
                ScrollView {
                    LazyVStack {
                        Text(selectedGame.instructions)
                    }
                }
            }
        }
        .padding()
        .alert("小游戏启动失败", isPresented: Binding(
            get: { startError != nil }, set: { if !$0 { startError = nil } }
        )) {
            Button("好", role: .cancel) { startError = nil }
        } message: { Text(startError ?? "") }
        .animation(.default, value: otaMiniGames)
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
            taskParams = nil
        }
    }

    private var otaMiniGames: [MAAStageActivity.MiniGame] {
        viewModel.stageActivity?.miniGame ?? []
    }

    private func startMiniGame() {
        Task {
            do {
                if isSecretFront {
                    guard viewModel.secretFrontUnavailableReason == nil else { return }
                    let configuration = SecretFrontConfiguration(ending: secretFrontEnding, event: secretFrontEvent)
                    try await viewModel.miniGame(name: configuration.taskName, secretFront: configuration)
                } else {
                    try await viewModel.miniGame(name: selectedGame.taskName, params: taskParams)
                }
            } catch {
                startError = error.localizedDescription
            }
        }
    }
}

enum MiniGameOption: String, CaseIterable {
    case sideStoryStore
    case greenTicketStore
    case yellowTickerStore
    case reclamationStore
    case secretFront

    var taskName: String {
        switch self {
        case .secretFront:
            return "MiniGame@SecretFront@Begin"
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
        case .secretFront:
            return String(localized: "隐秘战线")
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
        case .secretFront:
            String(localized: "请先进入隐秘战线的分队选择页面。指定事件出现时优先选择，成功率不足时可能先积累属性。识别失败时可用工具栏停止；从路线、危机或终点页面恢复需要相应 Core 资源支持。")
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
        let defaultDisplay = Display ?? Value
        if let DisplayKey {
            return Bundle.main.localizedString(forKey: DisplayKey, value: defaultDisplay, table: nil)
        } else {
            return defaultDisplay
        }
    }

    fileprivate var tag: MiniGameTag {
        let defaultTip = Tip ?? ""
        let tip: String
        if let TipKey {
            tip = Bundle.main.localizedString(forKey: TipKey, value: defaultTip, table: nil)
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
