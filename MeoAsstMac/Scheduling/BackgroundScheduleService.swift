import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor final class BackgroundScheduleService: ObservableObject {
    static let shared = BackgroundScheduleService()
    static let plistName = "com.hguandl.MeoAsstMac.ScheduleAgent.plist"

    /// Poll cadence. The 300 s delivery window makes a 5 s consumption delay
    /// immaterial while cutting idle-time XPC and disk traffic fivefold.
    private static let pollInterval: TimeInterval = 5
    /// Ledger expiry is bookkeeping for never-delivered intents; a 60 s cadence
    /// stays far inside the 300 s delivery window while avoiding a full locked
    /// ledger transaction on every poll.
    private static let intentExpiryInterval: TimeInterval = 60

    @Published private(set) var status = SMAppService.Status.notRegistered
    @Published private(set) var available = false
    @Published private(set) var failure: String?
    @AppStorage("MAABackgroundScheduleEnabled") private(set) var enabled = false
    private weak var model: MAAViewModel?
    private var files: BackgroundScheduleFiles?
    private var lastPublication: SchedulePublication?
    private var poll: Timer?
    private var lastIntentExpiry: Date?
    private let service = SMAppService.agent(plistName: plistName)

    /// Each source clears itself on its own success so one transient error can
    /// neither wipe the other's message nor stick around forever.
    private var publicationFailure: String? { didSet { failure = publicationFailure ?? inboxFailure } }
    private var inboxFailure: String? { didSet { failure = publicationFailure ?? inboxFailure } }

    private init() {}

    func attach(to model: MAAViewModel) {
        guard self.model !== model else { return }
        self.model = model
        refreshStatus()
        do {
            let directory = try ScheduleSigning.sharedDirectory()
            guard Bundle.main.url(forAuxiliaryExecutable: "MAAScheduleAgent") != nil,
                  FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchAgents/" + Self.plistName).path)
            else { throw BackgroundScheduleError.helperUnavailable }
            try TaskTimerManager.shared.configureSharedDirectory(directory)
            files = BackgroundScheduleFiles(directory: directory)
            available = true
            publishIfChanged()
        } catch {
            available = false
            failure = String(localized: "后台定时需要有效团队签名、共享容器和内嵌调度程序。")
            print("Background schedule unavailable: \(error)")
        }
        poll?.invalidate()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
                self?.publishIfChanged()
                self?.consumeIntents()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    func setEnabled(_ value: Bool) {
        guard !value || available else { return }
        do {
            if value {
                // Publish intent only after registration succeeds; approval is
                // reflected by the real system status rather than a fake toggle.
                try service.register()
                enabled = true
            } else {
                try service.unregister()
                enabled = false
            }
            failure = nil
            refreshStatus()
            publishIfChanged()
        } catch {
            failure = error.localizedDescription
            refreshStatus()
        }
    }

    func refreshStatus() { status = service.status }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func publishIfChanged() {
        guard let files, let model else { return }
        TaskTimerManager.shared.setBackgroundSchedulingEnabled(enabled)
        let publication = SchedulePublication(revision: UUID(), enabled: enabled,
            profileID: model.dailyTaskProfile, plans: model.scheduledDailyTaskTimers, publishedAt: .now)
        if let lastPublication, lastPublication.enabled == publication.enabled,
           lastPublication.profileID == publication.profileID, lastPublication.plans == publication.plans { return }
        do {
            try files.publish(publication)
            lastPublication = publication
            publicationFailure = nil
        } catch {
            publicationFailure = String(localized: "后台定时计划无法发布；本次不会触发。")
            print("Background schedule publication: \(error)")
        }
    }

    private func consumeIntents() {
        guard let files, let model, model.isCoreInitialized else { return }
        do {
            let expiryDue = lastIntentExpiry.map { Date().timeIntervalSince($0) >= Self.intentExpiryInterval } ?? true
            if expiryDue {
                try TaskTimerManager.shared.expireBackgroundIntents()
                lastIntentExpiry = .now
            }
            // Listing an empty inbox is the only idle-time work; the publication
            // read and the accept loop run only when an intent is waiting.
            let intents = try files.intents()
            guard !intents.isEmpty else {
                inboxFailure = nil
                return
            }
            let publication = try files.publication()
            for (url, intent) in intents {
                guard enabled, intent.isValid(in: publication, now: .now),
                      intent.profileID == model.dailyTaskProfile else {
                    try TaskTimerManager.shared.rejectBackgroundIntent(intent.occurrence, detail: "staleBackgroundIntent")
                    try FileManager.default.removeItem(at: url)
                    continue
                }
                try TaskTimerManager.shared.acceptBackgroundIntent(intent)
                try FileManager.default.removeItem(at: url)
            }
            inboxFailure = nil
        } catch {
            inboxFailure = String(localized: "后台定时交接记录无法读取；已暂停交接。")
            print("Background schedule inbox: \(error)")
        }
    }
}
