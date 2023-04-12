//
//  MAADetail.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import SwiftUI

struct MAADetail: View {
    @Binding var sidebar: SidebarEntry?
    @Binding var selection: ContentEntry

    var body: some View {
        switch sidebar {
        case .daily:
            TaskDetail(id: selection.task)
        case .copilot:
            CopilotDetail(url: selection.copilot)
        case .recognition:
            RecognitionDetail(entry: selection.recognition)
        case .none:
            Text("请选择内容项目")
        }
    }
}

struct MAADetail_Previews: PreviewProvider {
    static var previews: some View {
        MAADetail(sidebar: .constant(nil), selection: .constant(.init()))
    }
}
