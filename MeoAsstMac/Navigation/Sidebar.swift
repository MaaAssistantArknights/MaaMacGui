//
//  Sidebar.swift
//  MAA
//
//  Created by hguandl on 15/4/2023.
//

import SwiftUI

struct Sidebar: View {
    @Binding var selection: SidebarEntry?

    @State private var showUpdate = false

    @Environment(\.defaultMinListRowHeight) var rowHeight

    var body: some View {
        VStack {
            List(SidebarEntry.allCases, selection: $selection) { entry in
                entry.label
            }

            List {
                Button {
                    showUpdate.toggle()
                } label: {
                    Label("资源更新…", systemImage: "arrow.up.circle")
                }

                Button {
                    OpenLogFileView.revealLogInFinder()
                } label: {
                    Label("查找日志…", systemImage: "doc.text.magnifyingglass")
                }

                SettingsLink {
                    Label("设置", systemImage: "gear")
                }
            }
            .buttonStyle(.borderless)
            .frame(maxHeight: rowHeight * 4.2)
        }
        .withSidebarButton()
        .sheet(isPresented: $showUpdate) {
            ResourceUpdateView()
        }
        .frame(minWidth: 150)
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

@available(macOS, introduced: 10.15, obsoleted: 14)
private struct SettingsLink<Label: View>: View {
    private let label: Label

    init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    var body: some View {
        if #available(macOS 14.0, *) {
            SwiftUI.SettingsLink {
                label
            }
        } else {
            Button {
                showSettings()
            } label: {
                label
            }
        }
    }

    private func showSettings() {
        if #available(macOS 13, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

@available(macOS, introduced: 10.15, obsoleted: 13)
private struct SidebarButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *) {
            content
        } else {
            content.toolbar {
                ToolbarItemGroup {
                    Button {
                        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar), to: nil, from: nil)
                    } label: {
                        Label("显示/隐藏边栏", systemImage: "sidebar.left")
                    }
                    .help("显示/隐藏边栏")
                }
            }
        }
    }
}

extension View {
    @available(macOS, introduced: 10.15, obsoleted: 13)
    fileprivate func withSidebarButton() -> some View {
        modifier(SidebarButtonModifier())
    }
}
