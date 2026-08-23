//
//  CopilotsView.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import SwiftUI
import UniformTypeIdentifiers

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

    @State private var tracker = FileTreeTracker()

    var body: some View {
        @Bindable var context = newModel.copilot
        List(selection: $context.selection) {
            switch context.category {
            case .bundled:
                FileTreeRoot(item: $bundledRoot, tracker: tracker) {
                    Text($0.name)
                }
            case .external:
                FileTreeRoot(item: $externalRoot, tracker: tracker) {
                    Text($0.name)
                }
            case .list:
                CopilotListContent(context: context)
            }
        }
        .contextMenu(forSelectionType: CopilotContext.ItemID.self) { _ in
            EmptyView()
        } primaryAction: { ids in
            if context.category == .list {
                context.selection = nil
                return
            }
            if let url = ids.first?.url {
                tracker.sendURLAction(of: url)
            }
        }
        .safeAreaInset(edge: .top, spacing: 6) {
            CapsulePicker(CopilotCategory.allCases, selection: $context.category, color: \.color) {
                Image(systemName: $0.systemImage)
            } text: {
                Text($0.title)
            } action: {
                context.selection = nil
            }
            .padding(.horizontal)
            .padding(.top, 6)
            .background(.background)
        }
        .safeAreaInset(edge: .bottom) {
            if context.category == .list {
                CopilotListControls(context: context)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.background)
            }
        }
        .toolbar {
            CopilotListToolbar(externalRoot: $externalRoot)
        }
        .task(id: context.category) {
            switch context.category {
            case .bundled:
                await refreshItem(at: \.$bundledRoot)
            case .external:
                await refreshItem(at: \.$externalRoot)
            case .list:
                break
            }
        }
        .task(id: newModel.lastImportedCopilot) {
            guard let url = newModel.lastImportedCopilot else {
                return
            }
            defer {
                newModel.lastImportedCopilot = nil
            }
            context.selection = .init(url: url, isRaid: nil)
            if url.isDirectory {
                await context.updateSet(at: url)
                context.category = .list
            } else {
                await refreshItem(at: \.$externalRoot)
                context.category = .external
            }
        }
        .onChange(of: context.copilotList.isEmpty, initial: true) {
            if $1, context.category == .list {
                context.category = .external
                context.selection = nil
            }
        }
        .onDrop(of: [.json], isTargeted: .none, perform: addCopilots)
    }

    // MARK: - Actions

    private func refreshItem(at keyPath: KeyPath<Self, Binding<Item>>) async {
        let binding = self[keyPath: keyPath]
        let newChildren = try? await binding.wrappedValue.children()
        binding.wrappedValue.children = newChildren ?? []
    }

    private func addCopilots(_ providers: [NSItemProvider]) -> Bool {
        let canLoadAll = providers.allSatisfy {
            $0.hasItemConformingToTypeIdentifier(UTType.json.identifier)
        }
        guard !providers.isEmpty, canLoadAll else { return false }

        let (stream, continuation) = AsyncStream<Result<URL, Error>>.makeStream()

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.json.identifier) { item, error in
                if let error {
                    continuation.yield(.failure(error))
                } else if let url = item as? URL {
                    continuation.yield(.success(url))
                } else {
                    continuation.yield(.failure(CocoaError(.fileReadUnknown)))
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

    private func addCopilot(url: URL) async throws {
        guard url.isFileURL, let type = url.contentType else {
            return
        }
        switch type {
        case _ where type.conforms(to: .json):
            async let dest = try FileManager.default.copyCopilotToExternalDirectory(at: url)
            newModel.lastImportedCopilot = try await dest
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
                .disabled(!newModel.copilot.isReady)
            }
        }
    }

    private var canDeleteCopilot: Bool {
        if newModel.copilot.category == .list {
            return false
        }
        if let url = newModel.copilot.selection?.url {
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
        guard let selection = newModel.copilot.selection?.url else {
            return
        }

        let nextSelection = externalRoot.possibleSibling(of: selection)

        Task.detached {
            await deleteCopilot(url: selection)
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

    @concurrent private func deleteCopilot(url: URL) async {
        guard url.isManagedCopilot else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

extension CopilotCategory: Identifiable {
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

extension CopilotContext {
    var isReady: Bool {
        if category == .list {
            return copilotSet != nil && !copilotList.isEmpty
        }
        if case .copilot = content {
            return true
        }
        return false
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
        let dest = externalCopilotURL(for: url)
        try FileManager.default.copyItemOverwriting(at: url, to: dest)
        return dest
    }

    func moveCopilotToExternalDirectory(at url: URL) throws -> URL {
        let dest = externalCopilotURL(for: url)
        try FileManager.default.moveItemOverwriting(at: url, to: dest)
        return dest
    }

    private func externalCopilotURL(for url: URL) -> URL {
        let name = url.lastPathComponent
        return URL.externalCopilotDirectory.appending(path: name)
    }
}
