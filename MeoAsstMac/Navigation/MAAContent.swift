//
//  MAAContent.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import SwiftUI

struct MAAContent: View {
    @Binding var sidebar: SidebarEntry?
    @Binding var selection: ContentEntry

    var body: some View {
        Group {
            switch sidebar {
            case .daily:
                TasksContent(selection: $selection.task)
            case .copilot:
                CopilotContent(selection: $selection.copilot)
            case .utility:
                UtilityContent(selection: $selection.utility)
            case .none:
                Text("请从边栏选择功能")
            }
        }
        .frame(minWidth: 290)
    }
}

struct MAAContent_Previews: PreviewProvider {
    static var previews: some View {
        MAAContent(
            sidebar: .constant(.daily),
            selection: .constant(.init())
        )
        .environmentObject(MAAViewModel())
    }
}

struct ContentEntry: Codable {
    var task: UUID?
    var copilot: URL?
    var utility: UtilityEntry?
}
