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
    @State private var expanded = false
    @State private var copilotSetExpanded = true

    var body: some View {
        List(selection: $selection) {
            DisclosureGroup(isExpanded: $copilotSetExpanded) {
                ForEach(viewModel.copilotSetEntries) { entry in
                    CopilotListRow(
                        title: entry.displayName,
                        onSelect: { selectCopilot(url: URL(fileURLWithPath: entry.filename)) },
                        removalTitle: "移出作业集",
                        onRemove: { removeCopilotSetEntry(entry) })
                }
            } label: {
                Text("作业集")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            copilotSetExpanded.toggle()
                        }
                    }
            }

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
                ForEach(copilots.urls, id: \.self) { url in
                    Text(url.lastPathComponent)
                }
            } header: {
                HStack {
                    Text("外部作业（可拖入文件）")
                    if downloading {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .toolbar(content: listToolbar)
        .animation(.default, value: copilots)
        .animation(.default, value: viewModel.copilotSetEntries)
        .animation(.default, value: viewModel.useCopilotSet)
        .animation(.default, value: downloading)
        .onAppear(perform: loadUserCopilots)
        .onDrop(of: [.fileURL], isTargeted: .none, perform: addCopilots)
        .onReceive(viewModel.$copilotDetailMode, perform: deselectCopilot)
        .onReceive(viewModel.$downloadCopilot, perform: downloadCopilot)
        .onReceive(viewModel.$downloadCopilotSet, perform: downloadCopilotSet)
        .onReceive(viewModel.$videoRecoginition, perform: selectNewCopilot)
        .fileImporter(
            isPresented: $viewModel.showImportCopilot,
            allowedContentTypes: [.json],
            allowsMultipleSelection: true,
            onCompletion: addCopilots)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private func listToolbar() -> some ToolbarContent {
        ToolbarItemGroup {
            Button(action: deleteSelectedCopilot) {
                Label("移除", systemImage: "trash")
            }
            .help("移除作业")
            .disabled(shouldDisableDeletion)
            .keyboardShortcut(.delete, modifiers: [.command])
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
                    Label("停止", systemImage: "stop.fill")
                }
                .help("停止")
            case .idle:
                Button(action: start) {
                    Label("开始", systemImage: "play.fill")
                }
                .help("开始")
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
            if viewModel.useCopilotSet {
                guard !viewModel.copilotSetEntries.isEmpty else { return }
                viewModel.copilot = .regularList(makeCopilotListConfiguration())
            }
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

        Task {
            self.downloading = true
            do {
                let file = externalDirectory.appendingPathComponent(id).appendingPathExtension("json")
                let content = try await requestCopilotContent(id: id)
                try content.write(toFile: file.path, atomically: true, encoding: .utf8)
                copilots.insert(file)
                self.selection = file
            } catch {
                viewModel.logError("下载作业失败: \(id)")
                viewModel.logError("\(error.localizedDescription)")
            }
            self.downloading = false
        }
    }

    private func downloadCopilotSet(id: String?) {
        guard let id else { return }

        Task {
            self.downloading = true
            do {
                let response = try await requestCopilotSet(id: id)
                guard response.statusCode == 200 else {
                    if let message = response.message {
                        viewModel.logError("\(message)")
                    } else {
                        viewModel.logError("作业集不存在: \(id)")
                    }
                    self.downloading = false
                    return
                }

                guard let copilotIds = response.data?.copilotIds, !copilotIds.isEmpty else {
                    viewModel.logError("作业集为空: \(id)")
                    self.downloading = false
                    return
                }

                var importedFiles = [URL]()
                var copilotSetEntries = [CopilotSetTaskEntry]()
                let fileNames = copilotSetImportFileNames(copilotIDs: copilotIds)

                for (copilotId, fileName) in zip(copilotIds, fileNames) {
                    do {
                        let file = externalDirectory.appendingPathComponent(fileName)
                        let content = try await requestCopilotContent(id: String(copilotId))
                        try content.write(toFile: file.path, atomically: true, encoding: .utf8)
                        copilots.insert(file)
                        importedFiles.append(file)
                        if let entries = makeCopilotSetEntries(file: file, content: content, copilotID: copilotId) {
                            copilotSetEntries.append(contentsOf: entries)
                        }
                    } catch {
                        viewModel.logError("下载作业集条目失败: \(copilotId)")
                    }
                }

                if importedFiles.isEmpty {
                    viewModel.logError("作业集导入失败: \(id)")
                } else {
                    viewModel.copilotSetEntries = copilotSetEntries
                    viewModel.useCopilotSet = !copilotSetEntries.isEmpty
                    self.selection = importedFiles.first
                }
            } catch {
                viewModel.logError("下载作业集失败: \(id)")
                viewModel.logError("\(error.localizedDescription)")
            }
            self.downloading = false
        }
    }

    private func deleteCopilot(url: URL) {
        copilots.remove(url)
        removeCopilotSetEntries(filename: url.path)
        guard canDelete(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func deleteSelectedCopilot() {
        guard let selection, let index = copilots.urls.firstIndex(of: selection) else { return }

        deleteCopilot(url: selection)
        selectCopilotAfterDeletion(deletedIndex: index)
    }

    private func deleteCopilotAndSelectNext(url: URL) {
        guard let index = copilots.urls.firstIndex(of: url) else {
            deleteCopilot(url: url)
            if selection == url {
                selectCopilot(url: nil)
            }
            return
        }

        deleteCopilot(url: url)
        if selection == url {
            selectCopilotAfterDeletion(deletedIndex: index)
        }
    }

    private func selectCopilotAfterDeletion(deletedIndex index: Int) {

        let urls = copilots.urls
        if index < urls.count {
            selectCopilot(url: urls[index])
        } else {
            selectCopilot(url: urls.last)
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
            selectCopilot(url: copilots.urls.last)
        }
    }

    private func selectCopilot(url: URL?) {
        selection = url
        if url != nil {
            viewModel.copilotDetailMode = .copilotConfig
        }
    }

    private func removeCopilotSetEntry(_ entry: CopilotSetTaskEntry) {
        viewModel.copilotSetEntries.removeAll { $0.id == entry.id }
        if viewModel.copilotSetEntries.isEmpty {
            viewModel.useCopilotSet = false
        }
    }

    private func removeCopilotSetEntries(filename: String) {
        viewModel.copilotSetEntries.removeAll { $0.filename == filename }
        if viewModel.copilotSetEntries.isEmpty {
            viewModel.useCopilotSet = false
        }
    }

    private func makeCopilotListConfiguration() -> RegularCopilotListConfiguration {
        let list = viewModel.copilotSetEntries.map {
            CopilotListItem(filename: $0.filename, stage_name: $0.stageName, is_raid: $0.isRaid)
        }
        let regularConfig: RegularCopilotConfiguration? = {
            if case .regular(let config) = viewModel.copilot {
                return config
            }
            return nil
        }()

        return .init(
            copilot_list: list,
            formation: regularConfig?.formation ?? false,
            add_trust: regularConfig?.add_trust ?? false)
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

    private func requestCopilotContent(id: String) async throws -> String {
        let url = URL(string: "https://prts.maa.plus/copilot/get/\(id)")!
        let data = try await URLSession.shared.data(from: url).0
        let response = try JSONDecoder().decode(CopilotResponse.self, from: data)
        return response.data.content
    }

    private func requestCopilotSet(id: String) async throws -> CopilotSetResponse {
        let url = URL(string: "https://prts.maa.plus/set/get?id=\(id)")!
        let data = try await URLSession.shared.data(from: url).0
        return try JSONDecoder().decode(CopilotSetResponse.self, from: data)
    }

    private func makeCopilotSetEntries(file: URL, content: String, copilotID: Int) -> [CopilotSetTaskEntry]? {
        guard
            let data = content.data(using: .utf8),
            let copilot = try? JSONDecoder().decode(MAACopilot.self, from: data)
        else {
            viewModel.logError("作业集条目解析失败: \(copilotID)")
            return nil
        }

        guard copilot.type != "SSS" else {
            viewModel.logWarn("作业集列表暂不支持保全作业: \(copilotID)")
            return nil
        }

        let stageName = StageNavigationNameResolver.resolve(
            stageName: copilot.stage_name,
            title: copilot.doc?.title)
        return copilotSetTaskEntries(filename: file.path, stageName: stageName, difficulty: copilot.difficulty)
    }
}

struct CopilotSetTaskEntry: Equatable, Identifiable {
    let id = UUID()
    var filename: String
    var stageName: String
    var isRaid: Bool

    var displayName: String {
        isRaid ? "\(stageName)-Adverse" : stageName
    }
}

struct CopilotContent_Previews: PreviewProvider {
    static var previews: some View {
        CopilotContent(selection: .constant(nil))
            .environmentObject(MAAViewModel())
    }
}

private struct CopilotListRow: View {
    let title: String
    var onSelect: () -> Void
    var removalTitle: String?
    var onRemove: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            Text(title)
                .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let removalTitle, let onRemove {
                Button(removalTitle, action: onRemove)
            }
        }
    }
}

// MARK: - Value Extensions

private func copilotSetImportFileNames(copilotIDs: [Int]) -> [String] {
    let width = max(2, String(copilotIDs.count).count)
    return copilotIDs.enumerated().map { index, copilotID in
        "\(String(format: "%0*d", width, index + 1))_\(copilotID).json"
    }
}

private func copilotSetTaskEntries(filename: String, stageName: String, difficulty: Int?) -> [CopilotSetTaskEntry] {
    let difficulty = difficulty ?? 0
    let supportsNormal = difficulty == 0 || difficulty & 1 != 0
    let supportsRaid = difficulty & 2 != 0

    var entries = [CopilotSetTaskEntry]()
    if supportsNormal {
        entries.append(.init(filename: filename, stageName: stageName, isRaid: false))
    }
    if supportsRaid {
        entries.append(.init(filename: filename, stageName: stageName, isRaid: true))
    }
    return entries
}

private enum StageNavigationNameResolver {
    private static let stageCodeByIdentifier: [String: String] = {
        let url = Bundle.main.resourceURL?
            .appendingPathComponent("resource")
            .appendingPathComponent("Arknights-Tile-Pos")
            .appendingPathComponent("overview")
            .appendingPathExtension("json")

        guard
            let url,
            let data = try? Data(contentsOf: url),
            let overview = try? JSONDecoder().decode([String: StageOverview].self, from: data)
        else { return [:] }

        var result = [String: String]()
        for (_, stage) in overview {
            guard let code = stage.code else { continue }
            for identifier in [stage.code, stage.name, stage.stageId, stage.levelId].compactMap({ $0 }) {
                result[identifier] = code
            }
        }
        return result
    }()

    static func resolve(stageName: String, title: String?) -> String {
        if let code = stageCodeByIdentifier[stageName] {
            return code
        }

        if let title, let code = extractStageCode(from: title) {
            return code
        }

        return stageName
    }

    private static func extractStageCode(from title: String) -> String? {
        let pattern = #"(?:[A-Za-z]{0,3})(?:\d{0,2})-(?:(?:A|B|C|D|EX|S|TR|MO)-?)?(?:\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        guard
            let match = regex.firstMatch(in: title, range: range),
            let matchRange = Range(match.range, in: title)
        else { return nil }

        return String(title[matchRange])
    }

    private struct StageOverview: Decodable {
        let code: String?
        let name: String?
        let stageId: String?
        let levelId: String?
    }
}

extension URL {
    fileprivate var copilots: [URL] {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: self,
                includingPropertiesForKeys: [.contentTypeKey],
                options: .skipsHiddenFiles)
        else { return [] }

        return urls.filter { url in
            let value = try? url.resourceValues(forKeys: [.contentTypeKey])
            return value?.contentType == .json
        }
        .sorted { lhs, rhs in
            lhs.lastPathComponent < rhs.lastPathComponent
        }
    }
}

extension Set where Element == URL {
    fileprivate var urls: [URL] { sorted { $0.lastPathComponent < $1.lastPathComponent } }
}

// MARK: - Download Model

private struct CopilotResponse: Codable {
    let data: CopilotData

    struct CopilotData: Codable {
        let content: String
    }
}

private struct CopilotSetResponse: Codable {
    let statusCode: Int
    let message: String?
    let data: CopilotSetData?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case message
        case data
    }

    struct CopilotSetData: Codable {
        let copilotIds: [Int]

        enum CodingKeys: String, CodingKey {
            case copilotIds = "copilot_ids"
        }
    }
}

// MARK: - Convenience Methods

extension NSItemProvider {
    @MainActor fileprivate func loadURL() async throws -> URL {
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
