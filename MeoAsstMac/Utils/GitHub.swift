//
//  GitHub.swift
//  MAA
//
//  Created by hguandl on 2025/2/5.
//

import Foundation

public struct GitHub: Sendable {
    private let repo: String

    public init(repo: String) {
        self.repo = repo
    }

    public func rawURL(ref: String, path: String) -> URL? {
        URL(string: "https://github.com/\(repo)/raw/refs/\(ref)/\(path)")
    }

    public func archiveURL(ref: String) -> URL? {
        URL(string: "https://github.com/\(repo)/archive/refs/\(ref).zip")
    }

    public struct Version: Decodable {
        public let last_updated: String
    }
}

extension GitHub {
    public func query() async throws -> Version {
        let url = rawURL(ref: "heads/main", path: "resource/version.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let version = try JSONDecoder().decode(Version.self, from: data)
        return version
    }
}
