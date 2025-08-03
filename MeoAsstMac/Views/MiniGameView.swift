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
            HStack {
                Picker("选择小游戏", selection: $selectedGame) {
                    ForEach(MiniGameOption.allCases, id: \.self) { game in
                        Text(game.displayName).tag(game)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 200)
                
                Spacer()
            }
            
            VStack(spacing: 10) {
                Text(selectedGame.displayName)
                    .font(.title2)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .center)
                
                VStack(spacing: 8) {
                    ForEach(selectedGame.instructions, id: \.self) { instruction in
                        Text(instruction)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(minHeight: 60, alignment: .top)
                
                Group {
                    if let note = selectedGame.note {
                        Text(note)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("")
                            .frame(height: 20)
                    }
                }
                .frame(minHeight: 40, alignment: .top)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .top)
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
    
    var taskName: String {
        switch self {
        case .greenGrass:
            return "GreenGrass@DuelChannel@Begin"
        case .atConversationRoom:
            return "MiniGame@AT@ConversationRoom"
        }
    }
    
    var displayName: String {
        switch self {
        case .greenGrass:
            return "争锋频道：青草城"
        case .atConversationRoom:
            return "AT-相谈室"
        }
    }
    
    var instructions: [String] {
        switch self {
        case .greenGrass:
            return [
                "手动跳过教程对话，然后可以直接退出",
                "在活动主界面（右下角有“加入赛事”处）开始任务。"
            ]
        case .atConversationRoom:
            return [
                "在活动主界面（右下角有“开始营业/继续营业”处）开始任务",
                "等待自动完成相谈室对话"
            ]
        }
    }
    
    var note: String? {
        switch self {
        case .greenGrass:
            return "跟着鸭总喝口汤"
        case .atConversationRoom:
            return nil
        }
    }
}

struct MiniGameView_Previews: PreviewProvider {
    static var previews: some View {
        MiniGameView()
            .environmentObject(MAAViewModel())
    }
}
