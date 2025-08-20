//
//  ResourceUpdateView.swift
//  MAA
//
//  Created by hguandl on 2024/11/9.
//

import SwiftUI
import ZIPFoundation

struct ResourceUpdateView: View {
    let onUpdate: () async throws -> Void

    @State private var progress: (String, Double)? = ("", 0)
    @State private var error: Error?
    @State private var shouldUpdate = true

    @Environment(\.dismiss) private var dismiss
    @AppStorage("ResourceUpdateChannel") var resourceChannel = MAAResourceChannel.github

    private var extractURL: URL {
        switch resourceChannel {
        case .github:
            tmpURL.appendingPathComponent("MaaResource-main", isDirectory: true)
        case .mirrorChyan:
            tmpURL.appendingPathComponent("resource", isDirectory: true)
        }
    }

    private var sourceURL: URL {
        switch resourceChannel {
        case .github:
            extractURL.appendingPathComponent("resource", isDirectory: true)
        case .mirrorChyan:
            extractURL
        }
    }

    var body: some View {
        VStack {
            if !shouldUpdate {
                Text("无需更新资源")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                Button("好") {
                    dismiss()
                }
            } else if let progress {
                if let error {
                    Text("更新失败：\(error.localizedDescription)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                } else {
                    ProgressView(progress.0, value: progress.1)
                }
                Button("取消") {
                    dismiss()
                }
            } else {
                Text("更新完成")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        dismiss()
                    }
            }
        }
        .animation(.smooth, value: progress?.0)
        .padding()
        .task {
            do {
                let url = try await resourceChannel.latestURL()
                try await downloadResource(from: url)
                try await extractResource()
                try await copyResource()
                try await onUpdate()
                progress = nil
            } catch MAAResourceChannel.Error.noNeedUpdate {
                self.shouldUpdate = false
            } catch {
                self.error = error
            }
            try? FileManager.default.removeItem(at: localURL)
            removeExtracts()
        }
    }

    private func downloadResource(from remoteURL: URL) async throws {
        try? FileManager.default.removeItem(at: localURL)
        for try await progress in URLSession.shared.downloadTo(localURL, from: remoteURL) {
            try Task.checkCancellation()
            self.progress = (NSLocalizedString("正在下载…", comment: ""), progress.fractionCompleted)
        }
    }

    private func extractResource() async throws {
        removeExtracts()
        for try await progress in FileManager.default.unzipItemAt(localURL, to: tmpURL) {
            try Task.checkCancellation()
            self.progress = (NSLocalizedString("正在解压…", comment: ""), progress.fractionCompleted)
        }
    }

    private func copyResource() async throws {
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)

        let directoryEnumerator = FileManager.default.enumerator(
            at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .producesRelativePathURLs])!

        while case let fileURL as URL = directoryEnumerator.nextObject() {
            try Task.checkCancellation()

            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                let isDirectory = resourceValues.isDirectory
            else {
                continue
            }

            let destination = targetURL.appendingPathComponent(fileURL.relativePath, isDirectory: isDirectory)

            if isDirectory {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: fileURL)
            }
        }
    }

    private func removeExtracts() {
        try? FileManager.default.removeItem(at: extractURL)
        try? FileManager.default.removeItem(at: changesURL)
    }
}

private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
private let tmpURL = FileManager.default.temporaryDirectory

private let targetURL = documentsURL.appendingPathComponent("resource", isDirectory: true)
private let localURL = tmpURL.appendingPathComponent("MaaResource.zip")
private let changesURL = tmpURL.appendingPathComponent("changes.json", isDirectory: false)

#Preview {
    ResourceUpdateView {}
}
