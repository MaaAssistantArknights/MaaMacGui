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
                    Label(NSLocalizedString(NSLocalizedString("停止", comment: ""), comment: ""), systemImage: "stop.fill")
                }
                .help(NSLocalizedString(NSLocalizedString("停止", comment: ""), comment: ""))
            case .idle:
                Button(action: start) {
                    Label(NSLocalizedString(NSLocalizedString("开始", comment: ""), comment: ""), systemImage: "play.fill")
                }
                .help(NSLocalizedString(NSLocalizedString("开始", comment: ""), comment: ""))
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
        }
    }

    var label: some View {
        Label(description, systemImage: iconImage)
    }
}
