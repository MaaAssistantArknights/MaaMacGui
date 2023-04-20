//
//  ContentView.swift
//  MAA
//
//  Created by hguandl on 13/4/2023.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    @State private var selectedSidebar: SidebarEntry?
    @State private var selectedContent = ContentEntry()

    var body: some View {
        NavigationView {
            Sidebar(selection: selection)

            MAAContent(sidebar: selection, selection: $selectedContent)

            MAADetail(sidebar: selection, selection: $selectedContent)
        }
        .task {
            do {
                try await viewModel.initialize()
            } catch {
                print(error)
            }
        }
    }

    private var selection: Binding<SidebarEntry?> {
        Binding(get: { selectedSidebar ?? .daily }, set: { selectedSidebar = $0 })
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(MAAViewModel())
    }
}
