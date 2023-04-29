//
//  Sidebar.swift
//  MAA
//
//  Created by hguandl on 15/4/2023.
//

import SwiftUI

struct Sidebar: View {
    @Binding var selection: SidebarEntry?

    var body: some View {
        VStack {
            List(SidebarEntry.allCases, selection: $selection) { entry in
                entry.label
            }

            Spacer()

            Button {
                showSettings()
            } label: {
                Label("设置", systemImage: "gear")
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    toggleSideBar()
                } label: {
                    Label("显示/隐藏边栏", systemImage: "sidebar.left")
                }
                .help("显示/隐藏边栏")
            }
        }
        .frame(minWidth: 150)
    }

    // MARK: - Actions

    private func toggleSideBar() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }

    private func showSettings() {
        if #available(macOS 13, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            Sidebar(selection: .constant(.daily))
        }
    }
}

// MARK: - Sidebar Entry

enum SidebarEntry: Int, CaseIterable, Identifiable {
    var id: Self { self }
    case daily
    case copilot
    case utility
}

extension SidebarEntry: CustomStringConvertible {
    var description: String {
        switch self {
        case .daily:
            return NSLocalizedString("一键长草", comment: "")
        case .copilot:
            return NSLocalizedString("自动战斗", comment: "")
        case .utility:
            return NSLocalizedString("实用工具", comment: "")
        }
    }

    var iconImage: String {
        switch self {
        case .daily:
            return "cup.and.saucer"
        case .copilot:
            return "play.rectangle"
        case .utility:
            return "wrench.and.screwdriver"
        }
    }

    var label: some View {
        Label(description, systemImage: iconImage)
    }
}
