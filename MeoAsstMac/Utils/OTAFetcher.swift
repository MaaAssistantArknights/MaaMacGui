//
//  OTAFetcher.swift
//  MAA
//
//  Created by hguandl on 2025/6/9.
//

import Foundation

struct OTAFetcher: Sendable {
    private let session: URLSession

    private let baseURL = URL(string: "https://api.maa.plus/MaaAssistantArknights/api/")!

    private let cacheURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("cache")

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(path: String, name: String) async throws {
        let destination = cacheURL.appendingPathComponent(name, isDirectory: false)
        let source = baseURL.appendingPathComponent(path, isDirectory: false)

        let eTag = await cachedETag(path: path, at: destination)
        var request = URLRequest(url: source)
        request.setValue(eTag, forHTTPHeaderField: "If-None-Match")

        let (url, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        switch response.statusCode {
        case 304:
            return
        case 200..<300:
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destination)
            await cacheETag(path, response.value(forHTTPHeaderField: "etag"))
        default:
            throw URLError(.resourceUnavailable)
        }
    }

    private func cachedETag(path: String, at url: URL) async -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let eTags = await MainActor.run {
            UserDefaults.standard.dictionary(forKey: "OTAETags")
        }
        return eTags?[path] as? String
    }

    private func cacheETag(_ path: String, _ eTag: String?) async {
        guard let eTag else { return }
        await MainActor.run {
            var eTags = UserDefaults.standard.dictionary(forKey: "OTAETags") ?? [:]
            eTags[path] = eTag
            UserDefaults.standard.set(eTags, forKey: "OTAETags")
        }
    }
}
