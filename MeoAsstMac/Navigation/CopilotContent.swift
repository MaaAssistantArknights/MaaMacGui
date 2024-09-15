//
//  CopilotsView.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import SwiftUI

struct CopilotContent: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var selection: URL?

    @State private var copilots = Set<URL>()
    @State private var downloading = false

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(bundledCopilots, id: \.self) { url in
                    Text(url.lastPathComponent)
                }
            } header: {
                Text(NSLocalizedString("内置作业", comment: ""))
            }

            Section {
                ForEach(copilots.urls, id: \.self) { url in
                    Text(url.lastPathComponent)
                }
            } header: {
                HStack {
                    Text(NSLocalizedString("外部作业（可拖入文件）", comment: ""))
                    if downloading {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .toolbar(content: listToolbar)
        .animation(.default, value: copilots)
        .animation(.default, value: downloading)
        .onAppear(perform: loadUserCopilots)
        .onDrop(of: [.fileURL], isTargeted: .none, perform: addCopilots)
        .onReceive(viewModel.$copilotDetailMode, perform: deselectCopilot)
        .onReceive(viewModel.$downloadCopilot, perform: downloadCopilot)
        .onReceive(viewModel.$videoRecoginition, perform: selectNewCopilot)
        .fileImporter(isPresented: $viewModel.showImportCopilot,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: true,
                      onCompletion: addCopilots)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private func listToolbar() -> some ToolbarContent {
        ToolbarItemGroup {
            Button(action: deleteSelectedCopilot) {
                Label(NSLocalizedString("移除", comment: ""), systemImage: "trash")
            }
            .help(NSLocalizedString("移除作业", comment: ""))
            .disabled(shouldDisableDeletion)
        }

        ToolbarItemGroup {
            switch viewModel.status {
            case .pending:
                Button(action: {}) {
                    ProgressView().controlSize(.small)
                }
                .disabled(true)
            case .busy:
                Button(action: stop) {
                    Label(NSLocalizedString(NSLocalizedString("停止", comment: ""), comment: ""), systemImage: "stop.fill")
                }
                .help(NSLocalizedString(NSLocalizedString("停止", comment: ""), comment: ""))
            case .idle:
                Button(action: start) {
                    Label(NSLocalizedString(NSLocalizedString("开始", comment: ""), comment: ""), systemImage: "play.fill")
                }
                .help(NSLocalizedString(NSLocalizedString("开始", comment: ""), comment: ""))
            }
        }
    }

    // MARK: - Actions

    private func stop() {
        Task {
            try await viewModel.stop()
        }
    }

    private func start() {
        Task {
            viewModel.copilotDetailMode = .log
            try await viewModel.startCopilot()
        }
    }

    private func loadUserCopilots() {
        copilots.formUnion(externalDirectory.copilots)
        copilots.formUnion(recordingDirectory.copilots)
    }

    private func addCopilots(_ providers: [NSItemProvider]) -> Bool {
        Task {
            for provider in providers {
                if let url = try? await provider.loadURL() {
                    let value = try? url.resourceValues(forKeys: [.contentTypeKey])
                    if value?.contentType == .json {
                        copilots.insert(url)
                    } else if value?.contentType?.conforms(to: .movie) == true {
                        try? await viewModel.recognizeVideo(video: url)
                    }
                }
            }
            self.selection = self.copilots.urls.last
        }

        return true
    }

    private func addCopilots(_ results: Result<[URL], Error>) {
        if case let .success(urls) = results {
            copilots.formUnion(urls)
            selection = copilots.urls.last
        }
    }

    private func downloadCopilot(id: String?) {
        guard let id else { return }

        let file = externalDirectory
            .appendingPathComponent(id)
            .appendingPathExtension("json")

        let url = URL(string: "https://prts.maa.plus/copilot/get/\(id)")!
        Task {
            self.downloading = true
            do {
                let data = try await URLSession.shared.data(from: url).0
                let response = try JSONDecoder().decode(CopilotResponse.self, from: data)
                try response.data.content.write(toFile: file.path, atomically: true, encoding: .utf8)
                copilots.insert(file)
                self.selection = file
            } catch {
                print(error)
            }
            self.downloading = false
        }
    }

    private func deleteSelectedCopilot() {
        guard let selection else { return }
        copilots.remove(selection)
        if canDelete(selection) {
            try? FileManager.default.removeItem(at: selection)
        }
    }

    private func deselectCopilot(_ viewMode: MAAViewModel.CopilotDetailMode) {
        if viewMode != .copilotConfig {
            selection = nil
        }
    }

    private func selectNewCopilot(url: URL?) {
        if let url {
            copilots.insert(url)
            selection = copilots.urls.last
        }
    }

    // MARK: - State Wrappers

    private var shouldDisableDeletion: Bool {
        selection == nil || isBundled(selection)
    }

    private func isBundled(_ url: URL?) -> Bool {
        return url?.path.starts(with: bundledDirectory.path) ?? false
    }

    private func canDelete(_ url: URL?) -> Bool {
        [externalDirectory, recordingDirectory]
            .compactMap { url?.path.starts(with: $0.path) }
            .first(where: { $0 })
            ?? false
    }

    // MARK: - File Paths

    private var bundledCopilots: [URL] { bundledDirectory.copilots }

    private var bundledDirectory: URL {
        Bundle.main.resourceURL!
            .appendingPathComponent("resource")
            .appendingPathComponent("copilot")
    }

    private var externalDirectory: URL {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("copilot")

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private var recordingDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("cache")
            .appendingPathComponent("CombatRecord")
    }
}

struct CopilotContent_Previews: PreviewProvider {
    static var previews: some View {
        CopilotContent(selection: .constant(nil))
            .environmentObject(MAAViewModel())
    }
}

// MARK: - Value Extensions

private extension URL {
    var copilots: [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: self,
            includingPropertiesForKeys: [.contentTypeKey],
            options: .skipsHiddenFiles)
        else { return [] }

        return urls.filter { url in
            let value = try? url.resourceValues(forKeys: [.contentTypeKey])
            return value?.contentType == .json
        }
    }
}

private extension Set where Element == URL {
    var urls: [URL] { sorted { $0.lastPathComponent < $1.lastPathComponent } }
}

// MARK: - Download Model

private struct CopilotResponse: Codable {
    let data: CopilotData

    struct CopilotData: Codable {
        let content: String
    }
}

// MARK: - Convenience Methods

private extension NSItemProvider {
    @MainActor func loadURL() async throws -> URL {
        let handle = ProgressActor()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let progress = loadObject(ofClass: URL.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let object else {
                        continuation.resume(throwing: MAAError.emptyItemObject)
                        return
                    }

                    continuation.resume(returning: object)
                }

                Task {
                    await handle.bind(progress: progress)
                }
            }
        } onCancel: {
            Task {
                await handle.cancel()
            }
        }
    }
}

private actor ProgressActor {
    private var progress: Progress?
    private var cancelled = false

    func bind(progress: Progress) {
        guard !cancelled else { return }
        self.progress = progress
        progress.resume()
    }

    func cancel() {
        cancelled = true
        progress?.cancel()
    }
}
