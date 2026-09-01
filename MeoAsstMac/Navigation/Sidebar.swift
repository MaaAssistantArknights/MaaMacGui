//
//  Sidebar.swift
//  MAA
//
//  Created by hguandl on 15/4/2023.
//

import SwiftUI

struct Sidebar: View {
    @Binding var selection: SidebarEntry?

    @Binding var showUpdate: Bool
    let onUpdate: () async throws -> Void

    @EnvironmentObject private var viewModel: MAAViewModel
    @State private var showStageTip = false

    @Environment(\.defaultMinListRowHeight) var rowHeight

    var body: some View {
        VStack(alignment: .leading) {
            List(SidebarEntry.allCases, selection: $selection) { entry in
                entry.label
            }

            VStack(alignment: .listRowSeparatorLeading, spacing: 12) {
                Link(destination: URL(string: "https://docs.maa.plus/zh-cn/mac.html")!) {
                    Label("帮助与公告…", systemImage: "questionmark.circle")
                }

                Button {
                    showStageTip.toggle()
                } label: {
                    Label("今日关卡…", systemImage: "calendar.day.timeline.left")
                }
                .popover(isPresented: $showStageTip, arrowEdge: .trailing) {
                    DailyStageTipView(channel: viewModel.clientChannel)
                }

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
            .buttonStyle(.plain)
            .padding()
        }
        .sheet(isPresented: $showUpdate) {
            ResourceUpdateView(onUpdate: onUpdate)
        }
        .frame(minWidth: 150)
    }
}

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            Sidebar(selection: .constant(.daily), showUpdate: .constant(false)) {
                print("Resource updated")
            }
            .environmentObject(MAAViewModel())
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
            return String(localized: "一键长草")
        case .copilot:
            return String(localized: "自动战斗")
        case .utility:
            return String(localized: "实用工具")
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
