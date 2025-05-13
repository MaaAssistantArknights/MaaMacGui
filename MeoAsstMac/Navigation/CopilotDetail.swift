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
            if viewModel.useCopilotList {
                switch viewModel.copilotDetailMode {
                case .copilotConfig:
                    CopilotListSettings()
                case .log:
                    LogView()
                }
            } else if let url {
                CopilotView(url: url)
            } else {
                LogView()
            }
        }
        .padding()
        .toolbar(content: detailToolbar)
    }

    private struct CopilotListSettings: View {
        @EnvironmentObject private var viewModel: MAAViewModel

        var body: some View {
            Form {
                Section("全局设置") {
                    Toggle("自动编队", isOn: $viewModel.copilotListConfig.formation)
                    Toggle("信赖干员", isOn: $viewModel.copilotListConfig.add_trust)
                    Toggle("允许使用理智药", isOn: $viewModel.copilotListConfig.use_sanity_potion)
                }
            }
        }
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
            HStack {
                Divider()

                if viewModel.useCopilotList {
                    CopilotDetailTabButton(
                        mode: .copilotConfig, icon: "gearshape", selection: $viewModel.copilotDetailMode)
                }
                CopilotDetailTabButton(mode: .log, icon: "note.text", selection: $viewModel.copilotDetailMode)
            }
        }
    }

    @ViewBuilder private func addPopover() -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("神秘代码 [作业站链接](https://prts.plus)")
                .font(.headline)

            HStack {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                TextField("maa://", text: $prtsCode)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            Button {
                viewModel.downloadCopilot(id: prtsCode.parsedID)
                showAdd = false
            } label: {
                Label("下载作业", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(prtsCode.parsedID == nil)

            Button {
                if let clipboardString = NSPasteboard.general.string(forType: .string),
                    let parsedID = clipboardString.parsedID
                {
                    prtsCode = clipboardString
                    viewModel.downloadCopilot(id: parsedID)
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
            .fileImporter(
                isPresented: $viewModel.showImportCopilot,
                allowedContentTypes: [.json],
                allowsMultipleSelection: true,
                onCompletion: viewModel.addCopilots)
        }
        .frame(width: 200)
        .padding()
    }
}

struct CopilotDetailTabButton: View {
    let mode: MAAViewModel.CopilotDetailMode
    let icon: String
    @Binding var selection: MAAViewModel.CopilotDetailMode

    var body: some View {
        Button {
            selection = mode
        } label: {
            Image(systemName: icon)
                .foregroundColor(mode == selection ? Color.accentColor : nil)
        }
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
