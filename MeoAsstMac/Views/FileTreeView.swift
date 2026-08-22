//
//  FileTreeView.swift
//  MAA
//
//  Created by hguandl on 2026/8/7.
//

import SwiftUI

protocol FileTreeItem: Identifiable, Sendable {
    var url: URL { get }
    var children: [Self]? { get set }
    init(url: URL)
}

struct FileTreeRoot<Item: FileTreeItem, Label: View>: View {
    @Binding var item: Item
    let tracker: FileTreeTracker?

    let label: (Item) -> Label

    var body: some View {
        if item.url.isDirectory {
            if let $children = Binding($item.children) {
                ForEach($children) { $i in
                    FileTreeNode(item: $i, tracker: tracker, label: label)
                }
            }
        } else {
            label(item)
        }
    }
}

struct FileTreeNode<Item: FileTreeItem, Label: View>: View {
    @Binding var item: Item
    let tracker: FileTreeTracker?

    let label: (Item) -> Label

    @State private var isExpanded = false
    @State private var shouldRecalculate = true

    var body: some View {
        if item.url.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let $children = Binding($item.children) {
                    ForEach($children) { $i in
                        FileTreeNode(item: $i, tracker: tracker, label: label)
                    }
                }
            } label: {
                label(item)
            }
            .task(id: isExpanded) {
                if isExpanded {
                    await updateItemChildren()
                }
            }
            .task(id: item.children == nil) {
                if isExpanded, item.children == nil {
                    await updateItemChildren()
                }
            }
            .onChange(of: tracker?.urlActionEvent) {
                if $1?.url == item.url {
                    isExpanded.toggle()
                }
            }
        } else {
            label(item)
        }
    }

    private func updateItemChildren() async {
        do {
            item.children = try await item.children()
        } catch {
            print(error)
        }
    }
}

@Observable final class FileTreeTracker {
    fileprivate struct URLActionEvent: Hashable {
        fileprivate let id: UUID
        fileprivate let url: URL
    }

    fileprivate var urlActionEvent: URLActionEvent?

    func sendURLAction(of url: URL) {
        urlActionEvent = .init(id: UUID(), url: url)
    }
}

extension FileTreeItem {
    func children(fileManager: sending FileManager = .default) async throws -> [Self] {
        let (stream, continuation) = AsyncThrowingStream<[URL], Error>.makeStream()
        Task.detached {
            do {
                let urls = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.contentTypeKey],
                    options: .skipsHiddenFiles)
                continuation.yield(urls)
            } catch {
                continuation.yield(with: .failure(error))
            }
            continuation.finish()
        }
        var iterator = stream.makeAsyncIterator()
        guard let urls = try await iterator.next() else {
            throw CancellationError()
        }

        return urls.filter {
            guard let type = $0.contentType else { return false }
            return type.conforms(to: .directory) || type.conforms(to: .json)
        }.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory
            } else {
                return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        }.map {
            Self(url: $0)
        }
    }
}

#Preview {
    @Previewable @State var selection: URL?
    @Previewable @State var tracker = FileTreeTracker()
    @Previewable @State var item = CopilotContent.Item(url: .externalCopilotDirectory)

    List(selection: $selection) {
        FileTreeRoot(item: $item, tracker: tracker) {
            Text($0.url.lastPathComponent)
        }
    }
    .contextMenu(forSelectionType: URL.self) { _ in
        EmptyView()
    } primaryAction: { urls in
        if let url = urls.first {
            tracker.sendURLAction(of: url)
        }
    }
}
