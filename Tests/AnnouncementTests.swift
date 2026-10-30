import Foundation

final class ResponseProtocol: URLProtocol {
    struct Fixture: Sendable {
        var status = 200
        var headers = [String: String]()
        var body = Data("# Community announcement\nHello".utf8)
        var error: URLError?
    }
    static let lock = NSLock()
    nonisolated(unsafe) static var fixture = Fixture()
    nonisolated(unsafe) static var lastETag: String?
    static func configure(_ value: Fixture) { lock.withLock { fixture = value } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let value = Self.lock.withLock {
            Self.lastETag = request.value(forHTTPHeaderField: "If-None-Match")
            return Self.fixture
        }
        if let error = value.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: value.status, httpVersion: "HTTP/1.1", headerFields: value.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: value.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

actor Fetcher {
    var calls = 0
    var content: String? = "# First\nAnnouncement"
    var failure = false
    var cancelled = false
    var delayed = false
    func configure(
        content: String? = "# First\nAnnouncement", failure: Bool = false, cancelled: Bool = false,
        delayed: Bool = false
    ) {
        self.content = content
        self.failure = failure
        self.cancelled = cancelled
        self.delayed = delayed
    }
    func fetch(_ source: AnnouncementSource, _ etag: String?) async throws -> AnnouncementResponse {
        calls += 1
        if delayed { try await Task.sleep(for: .milliseconds(50)) }
        if cancelled { throw URLError(.cancelled) }
        if failure { throw URLError(.notConnectedToInternet) }
        return AnnouncementResponse(content: content, etag: "fixture-etag")
    }
}

@main struct AnnouncementTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ value: Bool, _ name: String) {
            checks += 1
            if !value { fatalError("FAIL: \(name)") }
        }
        func rejects(_ name: String, _ operation: () async throws -> Void) async {
            do {
                try await operation()
                check(false, name)
            } catch { check(true, name) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maa-announcements-\(UUID())")
        let suite = "maa.announcement.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResponseProtocol.self]
        let service = AnnouncementService(session: URLSession(configuration: configuration))
        let source = AnnouncementSource.chinese
        check(AnnouncementSource.preferred(for: "zh-TW") == source, "Chinese family source")
        check(AnnouncementSource.preferred(for: "ko-KR") == .english, "Korean English fallback")
        check(AnnouncementSource.preferred(for: "en-US") == .english, "English source")
        let fixture = ResponseProtocol.Fixture()
        ResponseProtocol.configure(fixture)
        let response = try await service.fetch(source: source, etag: "old-etag")
        check(response.content == String(decoding: fixture.body, as: UTF8.self), "200 decodes complete fixture body")
        check(ResponseProtocol.lock.withLock { ResponseProtocol.lastETag } == "old-etag", "conditional request ETag")
        ResponseProtocol.configure(.init(status: 304, headers: ["ETag": "new-etag"], body: Data()))
        let unchanged = try await service.fetch(source: source, etag: "old-etag")
        check(unchanged.content == nil && unchanged.etag == "new-etag", "304 no content")
        ResponseProtocol.configure(.init(status: 404))
        await rejects("404") { _ = try await service.fetch(source: source, etag: nil) }
        ResponseProtocol.configure(.init(body: Data([0xFF])))
        await rejects("non UTF8") { _ = try await service.fetch(source: source, etag: nil) }
        ResponseProtocol.configure(.init(body: Data()))
        await rejects("empty text") { _ = try await service.fetch(source: source, etag: nil) }
        ResponseProtocol.configure(.init(body: Data([0x41, 0x00, 0x42])))
        await rejects("binary UTF8 control") { _ = try await service.fetch(source: source, etag: nil) }
        ResponseProtocol.configure(.init(headers: ["Content-Length": "262145"], body: Data()))
        await rejects("declared size ceiling") { _ = try await service.fetch(source: source, etag: nil) }
        ResponseProtocol.configure(.init(body: Data(repeating: 65, count: AnnouncementService.maximumBytes + 1)))
        await rejects("stream size ceiling") { _ = try await service.fetch(source: source, etag: nil) }
        ResponseProtocol.configure(.init(body: Data(repeating: 65, count: AnnouncementService.maximumBytes)))
        let maximum = try await service.fetch(source: source, etag: nil)
        check(maximum.content?.utf8.count == AnnouncementService.maximumBytes, "exact response ceiling")
        ResponseProtocol.configure(.init(error: URLError(.timedOut)))
        await rejects("timeout") { _ = try await service.fetch(source: source, etag: nil) }
        for bad in [
            "file:///tmp/a", "javascript:alert(1)", "data:text/plain,a", "https://user:pass@example.com",
            "mailto:a@example.com", "/local",
        ] {
            check(!AnnouncementService.safeWebURL(URL(string: bad)!), "unsafe link \(bad)")
        }
        check(AnnouncementService.safeWebURL(URL(string: "https://maa.plus/a")!), "HTTPS link")
        check(AnnouncementService.safeWebURL(URL(string: "http://example.com")!), "HTTP link")
        let fetcher = Fetcher()
        let store = AnnouncementStore(
            source: source, cacheDirectory: root, defaults: defaults, fetch: { try await fetcher.fetch($0, $1) })
        check(!store.automaticallyShow && store.announcement == nil, "default off, first-offline empty")
        let now = Date(timeIntervalSince1970: 1_792_800_000)
        await store.refresh(now: now)
        check(store.hasUnread && store.announcement != nil && !store.isRefreshing, "fetch unread")
        let hash = store.announcement!.hash
        store.markDisplayed(hash: "foreign-hash")
        check(store.hasUnread, "foreign content cannot mark seen")
        store.markDisplayed(hash: hash)
        check(!store.hasUnread, "matching hash marks seen in store")
        let restored = AnnouncementStore(source: source, cacheDirectory: root, defaults: defaults)
        check(restored.announcement == store.announcement && !restored.hasUnread, "restart cache/seen roundtrip")
        await store.refresh(now: now.addingTimeInterval(60))
        check(await fetcher.calls == 1, "24h automatic refresh interval")
        await store.refresh(force: true, now: now.addingTimeInterval(61))
        let repeatCalls = await fetcher.calls
        check(!store.hasUnread && repeatCalls == 2, "same content no repeat unread")
        await fetcher.configure(content: "# Changed\nNew content")
        await store.refresh(force: true, now: now.addingTimeInterval(62))
        check(store.hasUnread && store.announcement!.hash != hash, "changed content unread")
        store.markDisplayed(hash: store.announcement!.hash)
        await fetcher.configure(content: nil)
        await store.refresh(force: true, now: now.addingTimeInterval(63))
        check(
            !store.hasUnread && store.announcement!.fetchedAt == now.addingTimeInterval(63),
            "304 retains content/seen and updates fetched time")
        let english = AnnouncementStore(
            source: .english, cacheDirectory: root, defaults: defaults,
            fetch: { _, _ in AnnouncementResponse(content: "English", etag: nil) })
        check(english.announcement == nil, "source locale caches isolated")
        await english.refresh(now: now)
        check(english.hasUnread && !store.hasUnread, "per-source seen independent")
        await fetcher.configure(failure: true)
        let old = store.announcement
        await store.refresh(force: true, now: now.addingTimeInterval(90_000))
        check(store.announcement == old && store.error != nil, "offline keeps old cache and explicit error")
        let calls = await fetcher.calls
        await store.refresh(now: now.addingTimeInterval(90_001))
        check(await fetcher.calls == calls, "failure backoff")
        await fetcher.configure(content: "Retry")
        await store.refresh(force: true, now: now.addingTimeInterval(90_002))
        check(store.error == nil && store.announcement?.content == "Retry", "manual retry clears error")
        store.automaticallyShow = true
        check(
            AnnouncementStore(source: source, cacheDirectory: root, defaults: defaults).automaticallyShow,
            "auto prompt persisted")
        store.automaticallyShow = false
        let corruptURL = root.appendingPathComponent(source.cacheKey).appendingPathExtension("json")
        try Data("bad-json".utf8).write(to: corruptURL)
        let corrupt = AnnouncementStore(source: source, cacheDirectory: root, defaults: defaults)
        check(corrupt.announcement == nil && corrupt.error != nil, "corrupt cache ignored with explanation")
        var tampered = old!
        tampered.schemaVersion = 999
        try JSONEncoder().encode(tampered).write(to: corruptURL)
        check(
            AnnouncementStore(source: source, cacheDirectory: root, defaults: defaults).announcement == nil,
            "unknown schema ignored")
        let malformed = "A\u{0000}B"
        let badTextCache = CachedAnnouncement(
            sourceID: source.id, locale: source.locale, content: malformed, hash: AnnouncementService.hash(malformed),
            etag: nil, fetchedAt: now)
        try JSONEncoder().encode(badTextCache).write(to: corruptURL)
        check(
            AnnouncementStore(source: source, cacheDirectory: root, defaults: defaults).announcement == nil,
            "control characters in cache rejected")
        let badETagCache = CachedAnnouncement(
            sourceID: source.id, locale: source.locale, content: "Valid", hash: AnnouncementService.hash("Valid"),
            etag: String(repeating: "x", count: 513), fetchedAt: now)
        try JSONEncoder().encode(badETagCache).write(to: corruptURL)
        check(
            AnnouncementStore(source: source, cacheDirectory: root, defaults: defaults).announcement == nil,
            "oversized cached ETag rejected")
        let concurrentRoot = root.appendingPathComponent("concurrent")
        let concurrentFetcher = Fetcher()
        await concurrentFetcher.configure(delayed: true)
        let concurrent = AnnouncementStore(
            source: source, cacheDirectory: concurrentRoot, defaults: defaults,
            fetch: { try await concurrentFetcher.fetch($0, $1) })
        async let first: Void = concurrent.refresh(force: true, now: now)
        async let second: Void = concurrent.refresh(force: true, now: now)
        _ = await (first, second)
        check(await concurrentFetcher.calls == 1, "manual/startup one request in flight")
        let invalid304 = AnnouncementStore(
            source: source, cacheDirectory: root.appendingPathComponent("no-cache"), defaults: defaults,
            fetch: { _, _ in AnnouncementResponse(content: nil, etag: nil) })
        await invalid304.refresh(now: now)
        check(invalid304.announcement == nil && invalid304.error != nil, "304 without cache fails")
        let escapedRoot = root.appendingPathComponent("escaped-body")
        let escapedText = String(repeating: "\"\\", count: AnnouncementService.maximumBytes / 2)
        let escapedStore = AnnouncementStore(
            source: source, cacheDirectory: escapedRoot, defaults: defaults,
            fetch: { _, _ in AnnouncementResponse(content: escapedText, etag: nil) })
        await escapedStore.refresh(now: now)
        check(escapedStore.announcement?.content == escapedText, "maximum escaped body accepted")
        check(
            AnnouncementStore(source: source, cacheDirectory: escapedRoot, defaults: defaults).announcement?.content
                == escapedText, "JSON expansion cache roundtrip")
        let blocked = root.appendingPathComponent("file-is-not-directory")
        try Data().write(to: blocked)
        let badStorage = AnnouncementStore(
            source: source, cacheDirectory: blocked, defaults: defaults,
            fetch: { _, _ in AnnouncementResponse(content: "Valid", etag: nil) })
        await badStorage.refresh(now: now)
        check(badStorage.announcement == nil && badStorage.error != nil, "failed atomic save no false cache success")
        let cancelledFetcher = Fetcher()
        await cancelledFetcher.configure(cancelled: true)
        let cancelledStore = AnnouncementStore(
            source: source, cacheDirectory: root.appendingPathComponent("cancelled"), defaults: defaults,
            fetch: { try await cancelledFetcher.fetch($0, $1) })
        await cancelledStore.refresh(now: now)
        check(
            cancelledStore.announcement == nil && cancelledStore.error == nil,
            "cancelled refresh is not a failure")
        await cancelledStore.refresh(now: now)
        check(await cancelledFetcher.calls == 2, "cancelled refresh sets no backoff")
        print("Passed \(checks) production announcement assertions")
    }
}
