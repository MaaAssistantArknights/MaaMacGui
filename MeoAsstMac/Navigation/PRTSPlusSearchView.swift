//
//  PRTSPlusSearchView.swift
//  MAA
//

import SwiftUI

struct PRTSPlusSearchView: View {
    @Environment(NewViewModel.self) private var newModel
    @Environment(\.dismiss) private var dismiss

    @State private var stage = ""
    @State private var results = [PRTSPlusSearchResult]()
    @State private var searching = false
    @State private var importingIDs = Set<Int>()
    @State private var importedIDs = Set<Int>()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("关卡代号，例如 1-7 或 main_01-07", text: $stage)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button(action: search) {
                    if searching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                }
                .disabled(searching || normalizedStage.isEmpty)
            }
            .padding()

            Divider()

            Group {
                if searching && results.isEmpty {
                    ProgressView("正在搜索作业…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, results.isEmpty {
                    ContentUnavailableView(
                        "搜索失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "按关卡搜索作业",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("输入游戏内显示的关卡代号或作业中的 stage_name")
                    )
                } else {
                    List(results) { result in
                        resultRow(result)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .navigationTitle("搜索 PRTS.plus 作业")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") {
                    dismiss()
                }
            }
        }
        .alert("操作失败", isPresented: showErrorAlert) {
            Button("好") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder private func resultRow(_ result: PRTSPlusSearchResult) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    Label {
                        Text(verbatim: result.uploader)
                    } icon: {
                        Image(systemName: "person")
                    }
                    Label {
                        Text(verbatim: String(result.operatorCount))
                    } icon: {
                        Image(systemName: "person.2")
                    }
                    Label {
                        Text(verbatim: String(result.likes))
                    } icon: {
                        Image(systemName: "hand.thumbsup")
                    }
                    Label {
                        Text(verbatim: String(result.views))
                    } icon: {
                        Image(systemName: "eye")
                    }
                    Text(verbatim: "#\(result.id)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let details = result.details, !details.isEmpty {
                    Text(details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if importingIDs.contains(result.id) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 92, height: 56)
            } else if importedIDs.contains(result.id) {
                Label("已导入", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(width: 92, height: 56)
            } else {
                VStack(alignment: .trailing) {
                    Button {
                        importCopilot(result, addToList: false)
                    } label: {
                        Label("下载", systemImage: "arrow.down.doc")
                    }
                    Button {
                        importCopilot(result, addToList: true)
                    } label: {
                        Label("加入列表", systemImage: "text.badge.plus")
                    }
                    .disabled(newModel.copilot.copilotSet == nil)
                    .help(
                        newModel.copilot.copilotSet == nil
                            ? "需要先激活一个作业集"
                            : "加入列表"
                    )
                }
                .frame(width: 92)
            }
        }
        .padding(.vertical, 4)
    }

    private var normalizedStage: String {
        stage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { errorMessage != nil && !results.isEmpty },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func search() {
        guard !normalizedStage.isEmpty else { return }
        searching = true
        errorMessage = nil
        results = []
        Task {
            defer { searching = false }
            do {
                results = try await PRTSPlusSearchClient.search(stage: normalizedStage)
                if results.isEmpty {
                    errorMessage = String(localized: "没有找到该关卡的可用作业")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importCopilot(_ result: PRTSPlusSearchResult, addToList: Bool) {
        guard importingIDs.insert(result.id).inserted else { return }
        errorMessage = nil
        Task {
            defer { importingIDs.remove(result.id) }
            do {
                let url = try await MAACopilot.download(id: result.id, toDirectory: .externalCopilotDirectory)
                if addToList {
                    guard await newModel.copilot.appendCopilot(at: url) else {
                        throw PRTSPlusSearchError.incompatibleList
                    }
                } else {
                    newModel.lastImportedCopilot = url
                }
                importedIDs.insert(result.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        PRTSPlusSearchView()
    }
    .environment(NewViewModel(parent: MAAViewModel()))
}
