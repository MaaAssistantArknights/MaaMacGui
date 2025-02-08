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
        NavigationSplitViewWrapper {
            Sidebar(selection: $selectedSidebar, showUpdate: $viewModel.showResourceUpdate)
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

@available(macOS, introduced: 10.15, obsoleted: 13, renamed: "NavigationSplitView")
private struct NavigationSplitViewWrapper<Sidebar: View, Content: View, Detail: View>: View {
    private var sidebar: Sidebar
    private var content: Content
    private var detail: Detail

    init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
    }

    var body: some View {
        if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *) {
            NavigationSplitView {
                sidebar
            } content: {
                content
            } detail: {
                detail
            }
        } else {
            NavigationView {
                sidebar
                content
                detail
            }
            .navigationViewStyle(.columns)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(MAAViewModel())
    }
}
