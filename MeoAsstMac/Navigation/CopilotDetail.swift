//
//  CopilotDetailView.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import SwiftUI

struct CopilotDetail: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @State private var showAdd = false
    @State private var prtsCode = ""
    let url: URL?

    var body: some View {
        VStack {
            if let url {
                CopilotView(url: url)
            } else {
                LogView()
            }
        }
        .padding()
        .toolbar(content: detailToolbar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private func detailToolbar() -> some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showAdd = true
            } label: {
                Label("添加", systemImage: "plus")
            }
            .help("添加作业")
            .popover(isPresented: $showAdd, arrowEdge: .bottom, content: addPopover)
        }

        ToolbarItemGroup {
            Button {
                viewModel.copilotDetailMode = .log
            } label: {
                Label("日志", systemImage: "note.text")
                    .foregroundColor(url == nil ? Color.accentColor : nil)
            }
            .help("运行日志")
        }
    }

    @ViewBuilder private func addPopover() -> some View {
        VStack {
            Text("神秘代码 [作业站链接](https://prts.plus)")
            TextField("maa://", text: $prtsCode)
            Spacer(minLength: 10)

            Button("下载作业") {
                viewModel.downloadCopilot = prtsCode.parsedID
            }
            .disabled(prtsCode.parsedID == nil)

            Button("选择本地文件…") {
                viewModel.showImportCopilot = true
            }
        }
        .padding()
    }
}

struct CopilotDetail_Previews: PreviewProvider {
    static let url = Bundle.main.resourceURL!
        .appendingPathComponent("resource")
        .appendingPathComponent("copilot")
        .appendingPathComponent("OF-1_credit_fight")
        .appendingPathExtension("json")

    static var previews: some View {
        CopilotDetail(url: url)
            .environmentObject(MAAViewModel())
    }
}

// MARK: - Value Extensions

private extension String {
    var parsedID: String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:maa:\/\/)?(\d+)"#,
                                                   options: .caseInsensitive)
        else {
            return nil
        }

        let range = NSRange(location: 0, length: utf16.count)
        guard let match = regex.firstMatch(in: self, range: range),
              let idRange = Range(match.range(at: 1), in: self)
        else {
            return nil
        }

        return String(self[idRange])
    }
}
