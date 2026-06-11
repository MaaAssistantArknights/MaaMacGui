//
//  CopilotListView.swift
//  MAA
//
//  UI for the Copilot List (作业集) feature: an ordered checklist of copilot
//  operations that run in sequence, with per-entry raid toggle and global options.
//

import SwiftUI

struct CopilotListView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var selection: CopilotEntry.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.copilotList.isEmpty {
                Text("作业集为空，请在右侧作业详情点击「加入作业集」")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                List(selection: $selection) {
                    ForEach($viewModel.copilotList) { $entry in
                        CopilotListRow(entry: $entry)
                            .tag(entry.id)
                    }
                    .onMove(perform: moveEntry)
                    .onDelete(perform: deleteEntry)
                }
            }

            Divider()

            optionsPanel
                .padding(8)
        }
    }

    // MARK: - Options

    @ViewBuilder private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("自动编队", isOn: $viewModel.copilotListOptions.formation)
                Toggle("信赖干员", isOn: $viewModel.copilotListOptions.addTrust)
            }

            Toggle("自动使用理智药", isOn: $viewModel.copilotListOptions.useSanityPotion)

            Picker("助战干员", selection: $viewModel.copilotListOptions.supportUnitUsage) {
                Text("不使用").tag(0)
                Text("仅在需要时").tag(1)
                Text("随机助战").tag(3)
            }
        }
        .font(.callout)
    }

    // MARK: - Actions

    private func moveEntry(from: IndexSet, to: Int) {
        viewModel.copilotList.move(fromOffsets: from, toOffset: to)
    }

    private func deleteEntry(at offsets: IndexSet) {
        viewModel.copilotList.remove(atOffsets: offsets)
    }
}

// MARK: - Row

private struct CopilotListRow: View {
    @Binding var entry: CopilotEntry

    /// Display title resolved from the copilot file's documentation, loaded once per file.
    @State private var title: String?

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $entry.isChecked)
                .labelsHidden()
                .toggleStyle(.checkbox)

            Text(displayName)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Toggle("突袭", isOn: $entry.isRaid)
                .toggleStyle(.button)
                .controlSize(.small)
        }
        .task(id: entry.filePath) {
            title = MAACopilot(url: URL(fileURLWithPath: entry.filePath))?.doc?.title
        }
    }

    /// Prefer the copilot's documentation title; fall back to the stage name, then file name.
    private var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        if !entry.name.isEmpty {
            return entry.name
        }
        return URL(fileURLWithPath: entry.filePath).lastPathComponent
    }
}

struct CopilotListView_Previews: PreviewProvider {
    static var previews: some View {
        CopilotListView(selection: .constant(nil))
            .environmentObject(MAAViewModel())
    }
}
