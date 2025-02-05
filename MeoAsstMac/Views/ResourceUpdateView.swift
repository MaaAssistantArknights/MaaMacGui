//
//  ResourceUpdateView.swift
//  MAA
//
//  Created by hguandl on 2024/11/9.
//

import SwiftUI
import ZIPFoundation

struct ResourceUpdateView: View {
    @State private var progress: (String, Double)? = ("", 0)
    @State private var error: Error?
    @State private var shouldUpdate = true

    @Environment(\.dismiss) private var dismiss
    @AppStorage("ResourceUpdateChannel") var resourceChannel = MAAResourceChannel.github

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
                Text("更新完成，请重新启动应用")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                Button("退出") {
                    dismiss()
                    NSApplication.shared.terminate(nil)
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
                progress = nil
            } catch MAAResourceChannel.Error.noNeedUpdate {
                self.shouldUpdate = false
            } catch {
                self.error = error
            }
            try? FileManager.default.removeItem(at: localURL)
            try? FileManager.default.removeItem(at: extractURL)
        }
    }

    private func downloadResource(from remoteURL: URL) async throws {
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: localURL)
        for try await progress in URLSession.shared.downloadTo(localURL, from: remoteURL) {
            self.progress = (NSLocalizedString("正在下载…", comment: ""), progress.fractionCompleted)
        }
    }

    private func extractResource() async throws {
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: extractURL)
        for try await progress in FileManager.default.unzipItemAt(localURL, to: tmpURL) {
            self.progress = (NSLocalizedString("正在解压…", comment: ""), progress.fractionCompleted)
        }
    }

    private func copyResource() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for subDirectory in ["cache", "resource"] {
                try Task.checkCancellation()
                let source = extractURL.appendingPathComponent(subDirectory)
                let destination = documentsURL.appendingPathComponent(subDirectory)

                group.addTask(priority: .userInitiated) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
                }
            }
            try await group.waitForAll()
        }
    }
}

private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
private let tmpURL = FileManager.default.temporaryDirectory

private let localURL = tmpURL.appendingPathComponent("MaaResource.zip")
private let extractURL = tmpURL.appendingPathComponent("MaaResource-main")

#Preview {
    ResourceUpdateView()
}
