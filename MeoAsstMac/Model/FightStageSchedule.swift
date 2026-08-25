//
//  FightStageSchedule.swift
//  MAA
//

import Foundation

struct FightStageSchedule: Sendable {
    enum Server: Sendable {
        case official
        case yoStarEN
        case yoStarJP
        case yoStarKR
        case txwy

        fileprivate var timeZone: TimeZone {
            let identifier =
                switch self {
                case .official: "Asia/Shanghai"
                case .yoStarEN: "America/Los_Angeles"
                case .yoStarJP: "Asia/Tokyo"
                case .yoStarKR: "Asia/Seoul"
                case .txwy: "Asia/Taipei"
                }
            return TimeZone(identifier: identifier)!
        }
    }

    struct ActivityWindow: Hashable, Sendable {
        let start: Date
        let expire: Date

        func contains(_ date: Date) -> Bool {
            start <= date && date <= expire
        }
    }

    struct ActivityData: Hashable, Sendable {
        var resourceCollection: ActivityWindow?
        var stageWindows: [String: ActivityWindow]

        init(resourceCollection: ActivityWindow? = nil, stageWindows: [String: ActivityWindow] = [:]) {
            self.resourceCollection = resourceCollection
            self.stageWindows = stageWindows
        }

        func activeStageValues(at date: Date) -> [String] {
            stageWindows.compactMap { $0.value.contains(date) ? $0.key : nil }.sorted()
        }
    }

    // Calendar weekday: 1 = Sunday, 2 = Monday, ... 7 = Saturday.
    private static let weeklyOpenDays: [String: Set<Int>] = [
        "CE-6": [1, 3, 5, 7],
        "AP-5": [1, 2, 5, 7],
        "CA-5": [1, 3, 4, 6],
        "SK-5": [2, 4, 6, 7],
        "PR-A-1": [1, 2, 5, 6], "PR-A-2": [1, 2, 5, 6],
        "PR-B-1": [2, 3, 6, 7], "PR-B-2": [2, 3, 6, 7],
        "PR-C-1": [1, 4, 5, 7], "PR-C-2": [1, 4, 5, 7],
        "PR-D-1": [1, 3, 4, 7], "PR-D-2": [1, 3, 4, 7],
    ]

    private static let knownPermanentStages: Set<String> = [
        "", "1-7", "R8-11", "12-17-HARD", "LS-6", "Annihilation", "OF-1", "OF-F3",
    ]

    func isOpen(
        _ stage: String,
        server: Server,
        activities: ActivityData?,
        at date: Date = Date()
    ) -> Bool {
        if let window = activities?.stageWindows[stage] {
            return window.contains(date)
        }

        guard let openDays = Self.weeklyOpenDays[stage] else {
            return true
        }
        if activities?.resourceCollection?.contains(date) == true {
            return true
        }
        return openDays.contains(serverWeekday(server, at: date))
    }

    func firstOpenStage(
        in stages: [String],
        server: Server,
        activities: ActivityData?,
        at date: Date = Date()
    ) -> String? {
        stages.first { isOpen($0, server: server, activities: activities, at: date) }
    }

    func blocksFollowingStages(_ stage: String, activities: ActivityData?) -> Bool {
        Self.knownPermanentStages.contains(stage) && activities?.stageWindows[stage] == nil
    }

    func serverWeekday(_ server: Server, at date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = server.timeZone
        let weekday = calendar.component(.weekday, from: date)
        guard calendar.component(.hour, from: date) < 4 else { return weekday }
        return weekday == 1 ? 7 : weekday - 1
    }
}
