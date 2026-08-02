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
                // In copilot-list mode the detail pane previews the selected entry
                // (documentation only) without touching the single-copilot run state.
                CopilotView(url: url, previewOnly: viewModel.useCopilotList)
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

            if let url {
                Button {
                    addCurrentToList(url: url)
                } label: {
                    Label("加入作业集", systemImage: "text.badge.plus")
                }
                .help("将当前作业加入作业集")
            }
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
        VStack(alignment: .leading, spacing: 9) {
            Text("神秘代码 [作业站链接](https://prts.plus)")
                .font(.headline)

            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("maa://", text: $prtsCode)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            Button {
                viewModel.downloadCopilot = prtsCode.parsedID
                showAdd = false
            } label: {
                Label("下载作业", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(prtsCode.parsedID == nil)

            Button {
                let setID = prtsCode.parsedID ?? prtsCode
                showAdd = false
                Task { await viewModel.importCopilotSet(id: setID) }
            } label: {
                Label("导入作业集", systemImage: "square.stack.3d.down.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(prtsCode.parsedID == nil)

            Button {
                if let clipboardString = NSPasteboard.general.string(forType: .string),
                    let parsedID = clipboardString.parsedID
                {
                    prtsCode = clipboardString
                    viewModel.downloadCopilot = parsedID
                    showAdd = false
                }
            } label: {
                Label("从剪贴板读取", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.showImportCopilot = true
            } label: {
                Label("选择本地文件…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .frame(width: 220)
        .padding()
    }

    // MARK: - Actions

    /// 将当前选中的作业加入作业集（导航代号由 addToCopilotList 自动解析）。
    private func addCurrentToList(url: URL) {
        viewModel.addToCopilotList(filePath: url.path)
        viewModel.useCopilotList = true
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

extension String {
    fileprivate var parsedID: String? {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?:maa:\/\/)?(\d+)"#,
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
