//
//  VersionUpdate.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import Foundation
import ZIPFoundation

private let apiURL = URL(string: "https://api.github.com/repos/MaaAssistantArknights/MaaAssistantArknights/releases")!

struct VersionChecker {
    func lastestRelease(prerelease: Bool = false) async throws -> String {
        var request = URLRequest(url: apiURL)
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let data = try await URLSession.shared.data(for: request).0
        for release in try JSONDecoder().decode([GHReleaseResponse].self, from: data) {
            if release.prerelease == prerelease {
                return release.name
            }
        }
        return ""
    }

    func downloadResource(version: String, delegate: URLSessionTaskDelegate) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let url = resourceURL(version: version)
        let task = session.downloadTask(with: URLRequest(url: url))
        task.resume()
        return url
    }

    private func resourceURL(version: String) -> URL {
        URL(string: "https://github.com/MaaAssistantArknights/MaaAssistantArknights/releases/download/\(version)/MaaResource-\(version).zip")!
    }
}

struct GHReleaseResponse: Decodable {
    let name: String
    let prerelease: Bool
}

extension AppDelegate: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print("finished: \(location.path)")
        let outputURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        print(outputURL)
        do {
            try FileManager.default.unzipItem(at: location, to: outputURL)
        } catch {
            print("error \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        print("\(totalBytesWritten) / \(totalBytesExpectedToWrite)")
    }
}
