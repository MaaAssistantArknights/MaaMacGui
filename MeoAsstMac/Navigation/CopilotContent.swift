//
//  CopilotsView.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import SwiftUI

struct CopilotContent: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var selection: URL?

    private func toggleCopilotList() {
        viewModel.useCopilotList.toggle()
        if viewModel.useCopilotList && viewModel.status == .idle {
            // 战斗列表模式，未运行默认展示全局设置
            viewModel.copilotDetailMode = .copilotConfig
        }
    }

    var body: some View {
        Group {
            if viewModel.useCopilotList {
                CopilotList()
            } else {
                RegularCopilotList(selection: $selection)
            }
        }
        .toolbar(content: listToolbar)
    }

    @ToolbarContentBuilder private func listToolbar() -> some ToolbarContent {
        ToolbarItemGroup {
            if !viewModel.useCopilotList {
                Button(action: deleteSelectedCopilot) {
                    Label("移除", systemImage: "trash")
                }
                .help("移除作业")
                .disabled(shouldDisableDeletion)
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }

        ToolbarItemGroup {
            Button(action: toggleCopilotList) {
                Label(
                    "战斗列表",
                    systemImage: viewModel.useCopilotList ? "list.bullet.rectangle.fill" : "list.bullet.rectangle"
                )
            }
            .help(viewModel.useCopilotList ? "切换回单个作业模式" : "切换到战斗列表模式")
        }

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
            viewModel.copilotDetailMode = .log
            try await viewModel.startCopilot()
        }
    }

    private func deleteSelectedCopilot() {
        guard let selection, let index = viewModel.copilots.urls.firstIndex(of: selection) else { return }

        viewModel.deleteCopilot(url: selection)

        let urls = viewModel.copilots.urls
        if index < urls.count {
            self.selection = urls[index]
        } else {
            self.selection = urls.last
        }
    }

    // MARK: - State Wrappers

    private var shouldDisableDeletion: Bool {
        selection == nil || isBundled(selection)
    }

    private func isBundled(_ url: URL?) -> Bool {
        return url?.path.starts(with: viewModel.bundledDirectory.path) ?? false
    }
}

#Preview {
    CopilotContent(selection: .constant(nil))
        .environmentObject(MAAViewModel())
}
