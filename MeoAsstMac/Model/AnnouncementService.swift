import CryptoKit
import Foundation

struct AnnouncementSource: Equatable, Sendable {
    let id: String
    let locale: String
    let url: URL

    // Endpoints mirror the upstream MaaWpfGui announcement sources (MaaUrls.MaaApi + announcements/wpf[_en].md);
    // keep them in sync if upstream moves its API domain or adds language variants.
    static let chinese = Self(
        id: "official-wpf-v1", locale: "zh-Hans",
        url: URL(string: "https://api.maa.plus/MaaAssistantArknights/api/announcements/wpf.md")!)
    static let english = Self(
        id: "official-wpf-v1", locale: "en",
        url: URL(string: "https://api.maa.plus/MaaAssistantArknights/api/announcements/wpf_en.md")!)
    static func preferred(for language: String) -> Self {
        language.lowercased().hasPrefix("zh") ? .chinese : .english
    }
    var cacheKey: String { id + "-" + locale }
}

enum AnnouncementError: Error {
    case invalidResponse
    case oversized
    case invalidText
    case invalidCache
}

struct CachedAnnouncement: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let sourceID: String
    let locale: String
    let content: String
    let hash: String
    var etag: String?
    var fetchedAt: Date
    var seenHash: String?

    var isUnread: Bool { seenHash != hash }

    func validate(for source: AnnouncementSource) throws {
        _ = try AnnouncementService.decode(Data(content.utf8))
        guard schemaVersion == 1, sourceID == source.id, locale == source.locale,
            hash == AnnouncementService.hash(content), (etag?.utf8.count ?? 0) <= 512,
            fetchedAt.timeIntervalSince1970.isFinite
        else {
            throw AnnouncementError.invalidCache
        }
    }
}

struct AnnouncementResponse: Sendable {
    let content: String?
    let etag: String?
}

struct AnnouncementService: Sendable {
    static let maximumBytes = 256 * 1024
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 10
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetch(source: AnnouncementSource, etag: String?) async throws -> AnnouncementResponse {
        var request = URLRequest(url: source.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse,
            response.url == source.url
        else { throw AnnouncementError.invalidResponse }
        let receivedETag = response.value(forHTTPHeaderField: "ETag").flatMap { $0.utf8.count <= 512 ? $0 : nil }
        if response.statusCode == 304 {
            return AnnouncementResponse(content: nil, etag: receivedETag ?? etag)
        }
        guard response.statusCode == 200 else { throw AnnouncementError.invalidResponse }
        guard response.expectedContentLength <= Int64(Self.maximumBytes) else { throw AnnouncementError.oversized }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumBytes else { throw AnnouncementError.oversized }
            data.append(byte)
        }
        return AnnouncementResponse(content: try Self.decode(data), etag: receivedETag)
    }

    static func decode(_ data: Data) throws -> String {
        guard data.count <= maximumBytes else { throw AnnouncementError.oversized }
        guard let content = String(data: data, encoding: .utf8),
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !content.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) })
        else {
            throw AnnouncementError.invalidText
        }
        return content
    }

    static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func safeWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false && url.user == nil
            && url.password == nil
    }
}
