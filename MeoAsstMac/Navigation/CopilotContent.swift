//
//  CopilotsView.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import SwiftUI

struct CopilotContent: View {
    @Environment(NewViewModel.self) var newModel

    struct Item: FileTreeItem {
        let url: URL
        let id: CopilotContext.ItemID

        init(url: URL) {
            self.url = url
            self.id = .init(url: url, isRaid: nil)
        }

        var children: [Item]?

        var name: String {
            url.deletingPathExtension().lastPathComponent
        }
    }

    @State private var bundledRoot = Item(url: .bundledCopilotDirectory)
    @State private var externalRoot = Item(url: .externalCopilotDirectory)

    enum Category: String, CaseIterable {
        case bundled
        case external
        case list
    }

    @AppStorage("CopilotContentCategory")
    private var category = Category.bundled

    @State private var tracker = FileTreeTracker()

    var body: some View {
        @Bindable var context = newModel.copilot
        List(selection: $context.selection) {
            switch category {
            case .bundled:
                FileTreeRoot(item: $bundledRoot, tracker: tracker) {
                    Text($0.name)
                } label: {
                    Text($0.name)
                }
            case .external:
                FileTreeRoot(item: $externalRoot, tracker: tracker) {
                    Text($0.name)
                } label: {
                    Text($0.name)
                }
            case .list:
                CopilotListContent(context: context)
            }
        }
        .contextMenu(forSelectionType: CopilotContext.ItemID.self) { _ in
            EmptyView()
        } primaryAction: { ids in
            if category == .list {
                context.selection = nil
                return
            }
            if let url = ids.first?.url {
                tracker.sendURLAction(of: url)
            }
        }
        .safeAreaInset(edge: .top) {
            CapsulePicker(Category.allCases, selection: $category, color: \.color) {
                Image(systemName: $0.systemImage)
            } text: {
                Text($0.title)
            } action: {
                context.selection = nil
            }
            .padding(.horizontal)
        }
        .toolbar {
            CopilotListToolbar(externalRoot: $externalRoot)
        }
        .task(id: category) {
            switch category {
            case .bundled:
                context.isListMode = false
                bundledRoot.children = (try? await bundledRoot.children()) ?? []
            case .external:
                context.isListMode = false
                externalRoot.children = (try? await externalRoot.children()) ?? []
            case .list:
                context.isListMode = true
            }
        }
        .onChange(of: context.isListMode, initial: true) {
            if context.isListMode, category != .list {
                category = .list
            }
        }
        .task(id: newModel.lastImportedCopilot) {
            guard let url = newModel.lastImportedCopilot else {
                return
            }
            context.selection = .init(url: url, isRaid: nil)
            if url.isDirectory {
                context.updateCopilotSet()
                category = .list
            } else {
                let children = try? await externalRoot.children()
                externalRoot.children = children ?? []
                category = .external
            }
        }
        .onDrop(of: [.fileURL], isTargeted: .none, perform: addCopilots)
    }

    // MARK: - Actions

    private func addCopilots(_ providers: [NSItemProvider]) -> Bool {
        let canLoadAll = providers.allSatisfy { $0.canLoadObject(ofClass: URL.self) }
        guard !providers.isEmpty, canLoadAll else { return false }

        let (stream, continuation) = AsyncStream<Result<URL, Error>>.makeStream()

        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let error {
                    continuation.yield(.failure(error))
                } else {
                    continuation.yield(.success(url!))
                }
            }
        }

        Task.detached { [total = providers.count] in
            var count = 0

            for await result in stream {
                count += 1
                if count == total {
                    continuation.finish()
                }

                do {
                    let url = try result.get()
                    try await addCopilot(url: url)
                } catch {
                    print(error)
                }
            }
        }

        return true
    }

    private nonisolated func addCopilot(url: URL) async throws {
        guard url.isFileURL, let type = url.contentType else {
            return
        }
        switch type {
        case _ where type.conforms(to: .json):
            let dest = try FileManager.default.copyCopilotToExternalDirectory(at: url)
            await MainActor.run {
                newModel.lastImportedCopilot = dest
            }
        case _ where type.conforms(to: .movie):
            try await newModel.recognizeVideo(url: url)
        default:
            break
        }
    }
}

// MARK: - Toolbar

private struct CopilotListToolbar: ToolbarContent {
    @Environment(NewViewModel.self) private var newModel
    @Binding var externalRoot: CopilotContent.Item

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: deleteSelectedCopilot) {
                Label("移除", systemImage: "trash")
            }
            .help("移除作业")
            .disabled(!canDeleteCopilot)
            .keyboardShortcut(.delete, modifiers: [.command])
        }

        ToolbarItemGroup {
            switch newModel.status {
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

    private var canDeleteCopilot: Bool {
        if newModel.copilot.isListMode {
            return false
        }
        if let url = newModel.copilot.url {
            return url.isManagedCopilot
        } else {
            return false
        }
    }

    // MARK: - Actions

    private func stop() {
        Task {
            try await newModel.stop()
        }
    }

    private func start() {
        Task {
            try await newModel.startCopilot()
        }
    }

    private func deleteSelectedCopilot() {
        guard let selection = newModel.copilot.url else {
            return
        }

        let nextSelection = externalRoot.possibleSibling(of: selection)

        Task.detached {
            deleteCopilot(url: selection)
            let children = try? await externalRoot.children()
            await MainActor.run {
                externalRoot.children = children ?? []
                if let url = nextSelection?.url {
                    newModel.copilot.selection = .init(url: url, isRaid: nil)
                } else {
                    newModel.copilot.selection = nil
                }
            }
        }
    }

    private nonisolated func deleteCopilot(url: URL) {
        guard url.isManagedCopilot else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

extension CopilotContent.Category: Identifiable {
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bundled:
            String(localized: "内置")
        case .external:
            String(localized: "外部")
        case .list:
            String(localized: "列表")
        }
    }

    var systemImage: String {
        switch self {
        case .bundled:
            "house"
        case .external:
            "doc"
        case .list:
            "doc.on.doc"
        }
    }

    var color: Color {
        switch self {
        case .bundled:
            .copilotBlue
        case .external:
            .copilotGreen
        case .list:
            .copilotIndigo
        }
    }
}

struct CopilotContent_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            CopilotContent()
        }
        .frame(maxWidth: 300)
        .environment(NewViewModel(parent: MAAViewModel()))
    }
}

// MARK: - File Paths

extension URL {
    static let bundledCopilotDirectory = Bundle.main.resourceURL!
        .appending(path: "resource/")
        .appending(path: "copilot/")

    static let externalCopilotDirectory = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)
        .first!
        .appending(path: "copilot/")
}

// MARK: - State Wrappers

extension URL {
    fileprivate var isManagedCopilot: Bool {
        path.starts(with: URL.externalCopilotDirectory.path)
    }
}

// MARK: - Value Extensions

extension CopilotContent.Item {
    func possibleSibling(of url: URL) -> Self? {
        if self.url == url {
            return nil
        }
        var searchStack = [self]

        while !searchStack.isEmpty {
            let current = searchStack.removeLast()

            if let children = current.children {
                for index in children.indices {
                    let item = children[index]

                    if item.url == url {
                        let nextIndex = children.index(after: index)

                        if nextIndex != children.endIndex {
                            return children[nextIndex]
                        } else if index != children.startIndex {
                            let prevIndex = children.index(before: index)
                            return children[prevIndex]
                        }

                        return nil
                    }

                    if item.children != nil {
                        searchStack.append(item)
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - Convenience Methods

extension FileManager {
    func copyCopilotToExternalDirectory(at url: URL) throws -> URL {
        let dest = prepareDestination(for: url)
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    func moveCopilotToExternalDirectory(at url: URL) throws -> URL {
        let dest = prepareDestination(for: url)
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    private func prepareDestination(for url: URL) -> URL {
        let name = url.lastPathComponent
        let dest = URL.externalCopilotDirectory.appending(path: name)
        try? FileManager.default.removeItem(at: dest)
        return dest
    }
}
