//
//  OperBoxView.swift
//  MAA
//
//  Created by hguandl on 22/4/2023.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OperBoxView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack(spacing: 20) {
            List {
                Section {
                    ForEach(ownedOpers, id: \.id) { oper in
                        oper.label
                    }
                } header: {
                    Text("已拥有干员：\(ownedOpers.count)")
                }

                Section {
                    ForEach(unownedOpers, id: \.id) { oper in
                        Text(oper.name)
                    }
                } header: {
                    Text("未拥有干员：\(unownedOpers.count)")
                }
            }
            .animation(.default, value: viewModel.operBox)

            HStack(spacing: 20) {
                Spacer()
                Button {
                    copyJSONToPasteboard()
                } label: {
                    Label("复制 JSON", systemImage: "doc.on.doc")
                }
                .help("将干员列表 JSON 复制到剪贴板")

                Button {
                    exportJSONToFile()
                } label: {
                    Label("导出 JSON", systemImage: "square.and.arrow.up")
                }
                .help("将干员列表 JSON 导出为文件")
            }
            .disabled(viewModel.operBox?.done != true)
        }
        .padding()
    }

    var ownedOpers: [MAAOperBox.OwnedOper] {
        viewModel.operBox?.own_opers
            .sorted()
            ?? []
    }

    var unownedOpers: [MAAOperBox.Oper] {
        viewModel.operBox?.all_opers
            .filter { !$0.own }
            .filter { !excludedOperNames.contains($0.name) }
            ?? []
    }

    // TODO: use charId
    private let excludedOperNames = [
        "预备干员-近战",
        "预备干员-术师",
        "预备干员-后勤",
        "预备干员-狙击",
        "预备干员-重装",
        "郁金香",
        "Stormeye",
        "Touch",
        "Pith",
        "Sharp",
        "阿米娅-WARRIOR",
    ]

    // MARK: - Export

    private func copyJSONToPasteboard() {
        guard let box = viewModel.operBox,
              let jsonData = box.exportJSONData,
              let jsonText = String(data: jsonData, encoding: .utf8)
        else {
            viewModel.logError("导出 JSON 失败")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(jsonText, forType: .string) else {
            viewModel.logError("导出 JSON 失败")
            return
        }
        viewModel.logInfo("已复制到剪贴板")
    }

    private func exportJSONToFile() {
        guard let box = viewModel.operBox,
              let jsonData = box.exportJSONData
        else {
            viewModel.logError("导出 JSON 失败")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Arknights_OperBox_Export.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(jsonData)
        do {
            try data.write(to: url, options: .atomic)
            viewModel.logInfo("已导出到文件")
        }
        catch {
            viewModel.logError("导出 JSON 失败")
        }
    }
}

struct OperBoxView_Previews: PreviewProvider {
    static var previews: some View {
        OperBoxView()
            .environmentObject(MAAViewModel())
    }
}
