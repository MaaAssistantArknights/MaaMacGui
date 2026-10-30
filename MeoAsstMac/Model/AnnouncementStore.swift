import Combine
import Foundation

@MainActor final class AnnouncementStore: ObservableObject {
    @Published private(set) var announcement: CachedAnnouncement?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: String?
    @Published var automaticallyShow: Bool {
        didSet { defaults.set(automaticallyShow, forKey: "MAAAutomaticallyShowAnnouncements") }
    }
    let source: AnnouncementSource
    private let defaults: UserDefaults
    private let cacheDirectory: URL
    private let fetch: @Sendable (AnnouncementSource, String?) async throws -> AnnouncementResponse
    private var retryAfter: Date?
    var hasUnread: Bool { announcement?.isUnread == true }

    init(
        source: AnnouncementSource = .preferred(for: Bundle.main.preferredLocalizations.first ?? "en"),
        cacheDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Announcements", isDirectory: true),
        defaults: UserDefaults = .standard,
        fetch: (@Sendable (AnnouncementSource, String?) async throws -> AnnouncementResponse)? = nil
    ) {
        self.source = source
        self.cacheDirectory = cacheDirectory
        self.defaults = defaults
        self.fetch = fetch ?? { source, etag in try await AnnouncementService().fetch(source: source, etag: etag) }
        automaticallyShow = defaults.bool(forKey: "MAAAutomaticallyShowAnnouncements")
        do {
            let path = cacheURL
            guard FileManager.default.fileExists(atPath: path.path) else { return }
            let size = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= AnnouncementService.maximumBytes * 6 + 16 * 1024 else { throw AnnouncementError.invalidCache }
            // Bounded by the size guard above (~1.5MB worst case); mappedIfSafe avoids copying it on the main thread.
            let cached = try Data(contentsOf: path, options: .mappedIfSafe)
            let entry = try JSONDecoder().decode(CachedAnnouncement.self, from: cached)
            try entry.validate(for: source)
            announcement = entry
        } catch {
            self.error = String(localized: "Announcement.BadCache")
        }
    }

    private var cacheURL: URL { cacheDirectory.appendingPathComponent(source.cacheKey).appendingPathExtension("json") }

    func refresh(force: Bool = false, now: Date = Date()) async {
        guard !isRefreshing else { return }
        if !force {
            if let retryAfter, retryAfter > now { return }
            if let fetchedAt = announcement?.fetchedAt, now.timeIntervalSince(fetchedAt) >= 0,
                now.timeIntervalSince(fetchedAt) < 24 * 60 * 60
            {
                return
            }
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let response = try await fetch(source, announcement?.etag)
            try Task.checkCancellation()
            let entry: CachedAnnouncement
            if let content = response.content {
                _ = try AnnouncementService.decode(Data(content.utf8))
                entry = CachedAnnouncement(
                    sourceID: source.id, locale: source.locale, content: content,
                    hash: AnnouncementService.hash(content), etag: response.etag,
                    fetchedAt: now, seenHash: announcement?.seenHash)
            } else {
                guard var existing = announcement else { throw AnnouncementError.invalidResponse }
                existing.fetchedAt = now
                existing.etag = response.etag
                entry = existing
            }
            try entry.validate(for: source)
            try save(entry)
            announcement = entry
            retryAfter = nil
            error = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
            // URLSession async calls throw URLError.cancelled, not CancellationError, when the task ends.
        } catch {
            retryAfter = now.addingTimeInterval(5 * 60)
            self.error = String(localized: "Announcement.RefreshFailed")
        }
    }

    /// Called by the view only after the matching content is presented. Fetching alone never marks it read.
    func markDisplayed(hash: String) {
        guard var entry = announcement, entry.hash == hash, entry.isUnread else { return }
        entry.seenHash = hash
        do {
            try save(entry)
            announcement = entry
        } catch {
            self.error = String(localized: "Announcement.SaveFailed")
        }
    }

    private func save(_ entry: CachedAnnouncement) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: cacheURL, options: .atomic)
    }
}
