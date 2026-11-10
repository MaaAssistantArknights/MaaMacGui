import Combine
import Foundation
import ServiceManagement

@MainActor final class AchievementStore: ObservableObject {
    static let shared = AchievementStore()
    @Published private(set) var engine = AchievementEngine()
    @Published private(set) var message: String?
    @Published var latestUnlocks: [String] = []
    @Published var showUnlockHints: Bool {
        didSet {
            defaults.set(showUnlockHints, forKey: "Achievement.ShowUnlockHints")
            if !showUnlockHints { latestUnlocks = [] }
        }
    }
    private let url: URL
    private let defaults: UserDefaults
    private var readOnly = false
    private var observers = Set<AnyCancellable>()

    init(url: URL? = nil, defaults: UserDefaults = .standard, observeFeatures: Bool = true) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Achievements/progress.json")
        self.defaults = defaults
        showUnlockHints = defaults.object(forKey: "Achievement.ShowUnlockHints") as? Bool ?? true
        if FileManager.default.fileExists(atPath: self.url.path) {
            do {
                let state = try JSONDecoder().decode(AchievementState.self, from: Data(contentsOf: self.url))
                guard state.schemaVersion == 1 else {
                    readOnly = true
                    message = String(localized: "Achievement.FutureSchema")
                    return
                }
                guard state.progress.values.allSatisfy({ $0.value >= 0 }), state.runBattles.values.allSatisfy({ $0 >= 0 }) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                engine = AchievementEngine(state: state)
            } catch {
                do {
                    let backup = self.url.appendingPathExtension("corrupt-" + UUID().uuidString)
                    try FileManager.default.copyItem(at: self.url, to: backup)
                    message = String(localized: "Achievement.Recovered")
                } catch {
                    readOnly = true
                    message = String(localized: "Achievement.SaveFailed")
                    return
                }
            }
        }
        guard observeFeatures else { return }
        for (name, metric) in [("MAAPreviewFrameDisplayed", AchievementMetric.peep), ("MAAHotkeyCommandAccepted", .hotkey)] {
            NotificationCenter.default.publisher(for: Notification.Name(name))
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.record(.init(metric: metric, operation: .maximum)) }
                .store(in: &observers)
        }
    }

    func record(_ event: AchievementEvent) {
        guard !readOnly else { return }
        var candidate = engine
        let unlocked = candidate.consume(event)
        guard candidate.state != engine.state else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(candidate.state).write(to: url, options: .atomic)
            engine = candidate
            if showUnlockHints, !unlocked.isEmpty { latestUnlocks = unlocked }
        } catch { message = String(localized: "Achievement.SaveFailed") }
    }

    func recordLaunch() {
        record(.init(metric: .firstLaunch, operation: .maximum))
        if SMAppService.mainApp.status == .enabled { record(.init(metric: .startup, operation: .maximum)) }
    }

    /// Called only after an explicit confirmation. Backup precedes replacement.
    func resetWithBackup() {
        guard !readOnly else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.copyItem(at: url, to: url.appendingPathExtension("backup-" + UUID().uuidString))
            }
            let empty = AchievementEngine()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(empty.state).write(to: url, options: .atomic)
            engine = empty
            latestUnlocks = []
        } catch { message = String(localized: "Achievement.SaveFailed") }
    }
}
