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
        switch sidebar {
        case .daily:
            TasksContent(selection: $selection.task)
        case .copilot:
            CopilotContent(selection: $selection.copilot)
        case .recognition:
            RecognitionContent(selection: $selection.recognition)
        case .none:
            Text("请从边栏选择功能")
        }
    }
}

struct MAAContent_Previews: PreviewProvider {
    static var previews: some View {
        MAAContent(sidebar: .constant(.daily),
                   selection: .constant(.init()))
    }
}

struct ContentEntry: Codable {
    var task: UUID?
    var copilot: URL?
    var recognition: RecognitionEntry?
}
