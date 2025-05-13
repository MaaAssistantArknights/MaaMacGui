//
//  RegularCopilotList.swift
//  MAA
//
//  Created by ninekirin on 2025/5/6.
//

import SwiftUI

struct RegularCopilotList: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var selection: URL?

    @State private var expanded = false

    private var bundledCopilots: [URL] { viewModel.bundledDirectory.copilots }

    var body: some View {
        List(selection: $selection) {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(bundledCopilots, id: \.self) { url in
                    Text(url.lastPathComponent)
                }
            } label: {
                Text("内置作业")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            expanded.toggle()
                        }
                    }
            }

            Section {
                ForEach(viewModel.copilots.urls, id: \.self) { url in
                    Text(url.lastPathComponent)
                }
            } header: {
                HStack {
                    Text("外部作业（可拖入文件）")
                    if viewModel.downloading {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .animation(.default, value: viewModel.copilots)
        .animation(.default, value: viewModel.downloading)
        .onDrop(of: [.fileURL], isTargeted: .none, perform: viewModel.addCopilots)
        .onReceive(viewModel.$copilotDetailMode, perform: deselectCopilot)
        .onReceive(viewModel.$videoRecoginition, perform: selectNewCopilot)
        // 这里我不太会处理双向数据绑定，先用这种方式
        .onChange(of: selection) { newValue in
            viewModel.selectedCopilotURL = newValue
            viewModel.copilotDetailMode = newValue == nil ? .log : .copilotConfig
        }
        .onChange(of: viewModel.selectedCopilotURL) { newValue in
            selection = newValue
        }
    }

    private func deselectCopilot(_ viewMode: MAAViewModel.CopilotDetailMode) {
        if viewMode != .copilotConfig {
            selection = nil
        }
    }

    private func selectNewCopilot(url: URL?) {
        if let url {
            viewModel.copilots.insert(url)
            selection = viewModel.copilots.urls.last
        }
    }
}

#Preview {
    RegularCopilotList(selection: .constant(nil))
        .environmentObject(MAAViewModel())
}
