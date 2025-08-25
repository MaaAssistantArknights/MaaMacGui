//
//  ResourceUpdater.swift
//  MAA
//
//  Created by hguandl on 2025/2/5.
//

import Foundation

public enum MAAResourceChannel: String, CaseIterable {
    case github
    case mirrorChyan

    public enum Error: Swift.Error {
        case emptyURL
        case noNeedUpdate
        case forbidden
        case rateExceeded
    }
}

extension MAAResourceChannel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .github:
            return NSLocalizedString("GitHub", comment: "")
        case .mirrorChyan:
            return NSLocalizedString("MirrorChyan", comment: "")
        }
    }
}

extension MAAResourceChannel.Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyURL:
            return NSLocalizedString("无下载链接，请检查CDK", comment: "")
        case .noNeedUpdate:
            return NSLocalizedString("无需更新", comment: "")
        case .forbidden:
            return NSLocalizedString("访问被禁止，请检查IP或CDK", comment: "")
        case .rateExceeded:
            return NSLocalizedString("IP请求频率过快，请稍后再试", comment: "")
        }
    }
}

extension MAAResourceChannel {
    public func latestVersion() async throws -> String {
        let localVersion = try version().1.last_updated
        switch self {
        case .github:
            let (remoteVersion, _) = try await latest(currentVersion: localVersion)
            return remoteVersion
        case .mirrorChyan:
            let mirrorChyan = MirrorChyan(rid: "MaaResource", cdk: nil)
            let version = try await mirrorChyan.query(currentVersion: localVersion)
            return version.version_name
        }
    }

    public func latestURL() async throws -> URL {
        let localVersion = try version().1.last_updated
        let (remoteVersion, url) = try await latest(currentVersion: localVersion)
        guard remoteVersion > localVersion else { throw Error.noNeedUpdate }
        guard let url else { throw Error.emptyURL }
        return url
    }

    private func latest(currentVersion: String) async throws -> (String, URL?) {
        switch self {
        case .github:
            let github = GitHub(repo: "MaaAssistantArknights/MaaResource")
            let version = try await github.query()
            return (version.last_updated, github.archiveURL(ref: "heads/main"))
        case .mirrorChyan:
            let mirrorChyan = MirrorChyan(rid: "MaaResource")
            let version = try await mirrorChyan.query(currentVersion: currentVersion)
            return (version.version_name, version.url)
        }
    }
}

extension MAAResourceChannel {
    func version() throws -> (preferUser: Bool, MAAResourceVersion) {
        let bundledResourceVersion = try resourceVersion(of: Bundle.main.resourceURL!)

        #if DEBUG
        guard false else { return (false, bundledResourceVersion) }
        #endif

        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        if let userResourceVersion = try? resourceVersion(of: documentsDirectory),
            userResourceVersion.last_updated > bundledResourceVersion.last_updated
        {
            return (true, userResourceVersion)

        }
        return (false, bundledResourceVersion)
    }

    private func resourceVersion(of url: URL) throws -> MAAResourceVersion {
        let versionURL = url.appendingPathComponent("resource").appendingPathComponent("version.json")
        let data = try Data(contentsOf: versionURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(MAAResourceVersion.self, from: data)
    }
}
