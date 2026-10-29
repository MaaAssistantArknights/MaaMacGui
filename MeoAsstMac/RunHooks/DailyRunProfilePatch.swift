import Foundation

/// Only fields produced by a successful task callback may change a saved run profile.
enum DailyTaskCallbackUpdate {
    case infrastructurePlanIndex(Int)
    case creditFightDate(Date)
    case friendVisitDate(Date)

    func applying(to current: MAATask, expecting original: MAATask) -> MAATask? {
        switch (self, current, original) {
        case (.infrastructurePlanIndex(let next), .infrast(var latest), .infrast(let expected)):
            guard latest.mode == .custom, expected.mode == .custom,
                  latest.filename == expected.filename, latest.plan_index == expected.plan_index else { return nil }
            latest.plan_index = next
            return .infrast(latest)
        case (.creditFightDate(let date), .mall(var latest), .mall(let expected)):
            guard latest.creditFightDate == expected.creditFightDate else { return nil }
            latest.creditFightDate = date
            return .mall(latest)
        case (.friendVisitDate(let date), .mall(var latest), .mall(let expected)):
            guard latest.friendVisitDate == expected.friendVisitDate else { return nil }
            latest.friendVisitDate = date
            return .mall(latest)
        default:
            return nil
        }
    }
}

enum DailyRunProfilePatchStore {
    /// Read the latest original profile, then compare-and-patch one field.
    /// UI edits are authoritative when that original profile is currently selected.
    static func apply(_ update: DailyTaskCallbackUpdate, taskID: UUID, expected: MAATask,
                      profileID: String, currentTasks: [DailyTask]?, directory: URL) throws -> [DailyTask]? {
        guard !profileID.isEmpty, ![".", ".."].contains(profileID),
              URL(fileURLWithPath: profileID).lastPathComponent == profileID else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let url = directory.appendingPathComponent(profileID).appendingPathExtension("plist")
        var latest: [DailyTask]
        if let currentTasks {
            latest = currentTasks
        } else {
            latest = try PropertyListDecoder().decode([DailyTask].self, from: Data(contentsOf: url))
        }
        guard let index = latest.firstIndex(where: { $0.id == taskID }),
              let patched = update.applying(to: latest[index].task, expecting: expected) else { return nil }
        latest[index] = DailyTask(id: taskID, task: patched, enabled: latest[index].enabled)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PropertyListEncoder().encode(latest).write(to: url, options: .atomic)
        return latest
    }
}
