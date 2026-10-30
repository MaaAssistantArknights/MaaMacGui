//
//  ContentView.swift
//  MAA
//
//  Created by hguandl on 13/4/2023.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @EnvironmentObject private var announcements: AnnouncementStore
    @Environment(\.openWindow) private var openWindow

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
        .toolbar { ToolbarItem { AnnouncementMenuButton(store: announcements) } }
        .task {
            do {
                try await viewModel.initialize()
                // Core initialization/errors own the first window. Announcements load afterward without blocking it.
                await announcements.refresh()
                if !Task.isCancelled, announcements.automaticallyShow, announcements.hasUnread,
                    viewModel.status == .idle
                {
                    openWindow(id: "community-announcements")
                }
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
            .environmentObject(AnnouncementStore())
    }
}
