//
//  ContentView.swift
//  MAA
//
//  Created by hguandl on 13/4/2023.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    @State private var selectedSidebar: SidebarEntry? = .daily
    @State private var selectedContent = ContentEntry()

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selectedSidebar, showUpdate: $viewModel.showResourceUpdate) {
                try await viewModel.reloadResources(channel: viewModel.clientChannel)
            }
        } content: {
            MAAContent(sidebar: $selectedSidebar, selection: $selectedContent)
        } detail: {
            MAADetail(sidebar: $selectedSidebar, selection: $selectedContent)
        }
        .task {
            do {
                try await viewModel.initialize()
            } catch {
                viewModel.logError("初始化失败: \(error.localizedDescription)")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(MAAViewModel())
    }
}
