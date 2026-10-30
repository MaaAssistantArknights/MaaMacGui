import AppKit
import SwiftUI

@MainActor private final class AnnouncementViewTestDelegate: NSObject, NSApplicationDelegate {
    private var checks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await runTests()
            print("Passed \(checks) announcement view assertions")
            NSApplication.shared.terminate(nil)
        }
    }

    private func check(_ value: Bool, _ name: String) {
        checks += 1
        if !value { fatalError("FAIL: \(name)") }
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func runTests() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maa-announcement-view-\(UUID())")
        let suite = "maa.announcement.view.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = AnnouncementStore(
            source: .english, cacheDirectory: root, defaults: defaults,
            fetch: { _, etag in
                if etag == nil {
                    return AnnouncementResponse(content: "# First\nUnread until presented", etag: "first")
                }
                return AnnouncementResponse(content: "# Updated\nChanged while presented", etag: "updated")
            })
        await store.refresh()
        let firstHash = store.announcement!.hash
        check(store.hasUnread, "fetching without a view preserves unread state")

        let view = AnnouncementView(store: store)
        check(store.hasUnread, "constructing an unmounted view preserves unread state")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 580),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        defer { window.close() }

        check(await waitUntil { !store.hasUnread }, "presenting AnnouncementView marks its content read")
        check(store.announcement?.seenHash == firstHash, "presentation marks the displayed hash read")
        let restored = AnnouncementStore(source: .english, cacheDirectory: root, defaults: defaults)
        check(restored.announcement?.seenHash == firstHash && !restored.hasUnread, "view read state survives restart")

        await store.refresh(force: true)
        let updatedHash = AnnouncementService.hash("# Updated\nChanged while presented")
        check(store.announcement?.hash == updatedHash && updatedHash != firstHash, "refresh replaces displayed content")
        check(await waitUntil { !store.hasUnread }, "refreshing the mounted view marks updated content read")
        check(store.announcement?.seenHash == updatedHash, "updated presentation marks the matching hash read")

        // Start with an empty view so its own refresh must insert and display the content.
        let loadingStore = AnnouncementStore(
            source: .english, cacheDirectory: root.appendingPathComponent("loading"), defaults: defaults,
            fetch: { _, _ in
                try await Task.sleep(for: .milliseconds(50))
                return AnnouncementResponse(content: "# Loaded\nArrived after presentation", etag: nil)
            })
        window.contentView = NSHostingView(rootView: AnnouncementView(store: loadingStore))
        check(
            await waitUntil { loadingStore.announcement != nil && !loadingStore.hasUnread },
            "content loaded by the presented view is marked read")
        check(
            loadingStore.announcement?.seenHash == AnnouncementService.hash("# Loaded\nArrived after presentation"),
            "newly displayed content marks its own hash read")
    }
}

@main private struct AnnouncementViewTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AnnouncementViewTestDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
