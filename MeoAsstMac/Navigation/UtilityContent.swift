//
//  UtilityContent.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import SwiftUI

struct UtilityContent: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var selection: UtilityEntry?

    var body: some View {
        List(UtilityEntry.allCases, selection: $selection) { entry in
            entry.label
        }
        .toolbar(content: listToolbar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private func listToolbar() -> some ToolbarContent {
        ToolbarItemGroup {
            switch viewModel.status {
            case .pending:
                Button(action: {}) {
                    ProgressView().controlSize(.small)
                }
                .disabled(true)
            case .busy:
                Button(action: stop) {
                    Label("停止", systemImage: "stop.fill")
                }
                .help("停止")
            case .idle:
                Button(action: start) {
                    Label("开始", systemImage: "play.fill")
                }
                .help("开始")
            }
        }
    }

    // MARK: - Actions

    private func stop() {
        Task {
            try await viewModel.stop()
        }
    }

    private func start() {
        Task {
            switch selection {
            case .recruit:
                try await viewModel.recognizeRecruit()
            case .depot:
                try await viewModel.recognizeDepot()
            case .oper:
                try await viewModel.recognizeOperBox()
            case .minigame:
                break
            case .video, .gacha:
                break
            case .none:
                break
            }
        }
    }
}

struct UtilityDetailContent_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            UtilityContent(selection: .constant(.recruit))
        }
    }
}

// MARK: - Utility Entry

enum UtilityEntry: Int, CaseIterable, Codable, Identifiable {
    var id: Self { self }
    case recruit
    case depot
    case oper
    case video
    case gacha
    case minigame
}

extension UtilityEntry: CustomStringConvertible {
    var description: String {
        switch self {
        case .recruit:
            return NSLocalizedString("公招词条", comment: "")
        case .depot:
            return NSLocalizedString("仓库材料", comment: "")
        case .oper:
            return NSLocalizedString("干员列表", comment: "")
        case .video:
            return NSLocalizedString("视频作业", comment: "")
        case .gacha:
            return NSLocalizedString("干员寻访", comment: "")
        case .minigame:
            return NSLocalizedString("小游戏", comment: "")
        }
    }

    var iconImage: String {
        switch self {
        case .recruit:
            return "person.text.rectangle"
        case .depot:
            return "house"
        case .oper:
            return "person.fill.checkmark"
        case .video:
            return "video"
        case .gacha:
            return "person.fill.viewfinder"
        case .minigame:
            return "gamecontroller.fill"
        }
    }

    var label: some View {
        Label(description, systemImage: iconImage)
    }
}
