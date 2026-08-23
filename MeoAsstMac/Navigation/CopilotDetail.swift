//
//  CopilotDetailView.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import SwiftUI

struct CopilotDetail: View {
    @Environment(NewViewModel.self) var newModel
    @State private var showInfo = false

    var body: some View {
        VStack {
            if showInfo {
                CopilotView(context: newModel.copilot)
            } else {
                LogView()
            }
        }
        .padding()
        .toolbar {
            DetailToolbar(showInfo: $showInfo)
        }
        .onChange(of: newModel.copilot.content, initial: true) {
            if $1 != nil {
                showInfo = true
            }
        }
    }
}

// MARK: - Toolbar

struct DetailToolbar: ToolbarContent {
    @Environment(NewViewModel.self) private var newModel
    @State private var showAdd = false
    @Binding var showInfo: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showAdd = true
            } label: {
                Label("添加", systemImage: "plus")
            }
            .help("添加作业")
            .popover(isPresented: $showAdd, arrowEdge: .bottom) {
                AddPopover(showAdd: $showAdd)
                    .frame(minWidth: 200)
                    .padding()
            }
        }

        ToolbarItem {
            Picker("详细内容", selection: $showInfo) {
                Label("info", systemImage: "info")
                    .tag(true)
                    .help("作业信息")
                Label("日志", systemImage: "note.text")
                    .tag(false)
                    .help("运行日志")
            }
            .pickerStyle(.segmented)
            .onChange(of: newModel.copilotStartToken) {
                if $1 != nil {
                    showInfo = false
                }
            }
        }
    }
}

private struct AddPopover: View {
    @Environment(NewViewModel.self) var newModel
    @Binding var showAdd: Bool
    @State private var showImportCopilot = false
    @State private var showSearchCopilot = false
    @State private var prtsCode = ""

    var body: some View {
        VStack {
            HStack {
                Text("**神秘代码**")
                Spacer()
                Text("[前往作业站…](https://prts.plus)")
            }

            let localCode = prtsCode.prtsCode

            HStack {
                TextField("prts://", text: $prtsCode)
                    .onSubmit {
                        if let localCode {
                            Task {
                                await newModel.downloadCopilot(code: localCode)
                            }
                        }
                    }
                PasteButton(payloadType: String.self) { texts in
                    let text = texts.first ?? ""
                    prtsCode = text
                    if let code = text.prtsCode {
                        Task {
                            await newModel.downloadCopilot(code: code)
                        }
                    }
                }
                .labelStyle(.iconOnly)
            }

            Divider()

            Button {
                if let localCode {
                    Task {
                        await newModel.downloadCopilot(code: localCode)
                    }
                }
            } label: {
                if let progress = newModel.copilotDownloadProgress {
                    ProgressView(progress).controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("下载作业", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
            }
            .animation(.default, value: newModel.copilotDownloadProgress)
            .buttonStyle(.borderedProminent)
            .disabled(localCode == nil)

            Button {
                showImportCopilot = true
            } label: {
                Label("选择本地文件…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showSearchCopilot = true
            } label: {
                Label("按关卡搜索…", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .disabled(newModel.copilotDownloadProgress != nil)
        .fileImporter(
            isPresented: $showImportCopilot,
            allowedContentTypes: [.json],
            allowsMultipleSelection: true,
            onCompletion: addCopilots
        )
        .sheet(isPresented: $showSearchCopilot) {
            NavigationStack {
                PRTSPlusSearchView()
            }
        }
    }

    private func addCopilots(_ results: Result<[URL], Error>) {
        do {
            let urls = try results.get()
            var lastURL: URL?
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else {
                    print("Failed to access \(url.path(percentEncoded: false))")
                    continue
                }
                defer {
                    url.stopAccessingSecurityScopedResource()
                }
                lastURL = try FileManager.default.copyCopilotToExternalDirectory(at: url)
            }
            newModel.lastImportedCopilot = lastURL
        } catch {
            print(error)
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
        let viewModel = MAAViewModel()
        CopilotDetail()
            .environmentObject(viewModel)
            .environment(NewViewModel(parent: viewModel))
    }
}

struct AddPopover_Previews: PreviewProvider {
    static var previews: some View {
        AddPopover(showAdd: .constant(true))
            .frame(width: 200)
            .padding()
            .environment(NewViewModel(parent: MAAViewModel()))
    }
}

// MARK: - Value Extensions

enum PRTSCode: Hashable {
    case copilot(Int)
    case set(Int)
}

extension StringProtocol {
    fileprivate var prtsCode: PRTSCode? {
        let string = trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("prts://")

        if string.starts(with: "s") {
            if let s = string.trimmingPrefix("s").digits {
                return .set(Int(s)!)
            }
        } else if let s = string.digits {
            return .copilot(Int(s)!)
        }

        return nil
    }

    private var digits: Self? {
        guard !isEmpty else {
            return nil
        }
        let predicate = allSatisfy { char in
            char.isASCII && char.isNumber
        }
        return predicate ? self : nil
    }
}
