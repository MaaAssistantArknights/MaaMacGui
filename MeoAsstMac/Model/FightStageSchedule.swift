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
            self.stageWindows = Dictionary(
                stageWindows.map { (FightStageSchedule.normalizedStage($0.key), $0.value) },
                uniquingKeysWith: { first, _ in first })
        }

        func activeStageValues(at date: Date) -> [String] {
            stageWindows.compactMap { $0.value.contains(date) ? $0.key : nil }.sorted()
        }

        func hasActiveSideStory(at date: Date) -> Bool {
            stageWindows.values.contains { $0.contains(date) }
        }
    }

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

    static func normalizedStage(_ stage: String) -> String {
        stage.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    func isOpen(_ stage: String, server: Server, activities: ActivityData?, at date: Date = Date()) -> Bool {
        let stage = Self.normalizedStage(stage)
        if let window = activities?.stageWindows[stage] {
            return window.contains(date)
        }
        guard let openDays = Self.weeklyOpenDays[stage] else { return true }
        if activities?.resourceCollection?.contains(date) == true { return true }
        return openDays.contains(serverWeekday(server, at: date))
    }

    func serverWeekday(_ server: Server, at date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = server.timeZone
        let weekday = calendar.component(.weekday, from: date)
        guard calendar.component(.hour, from: date) < 4 else { return weekday }
        return weekday == 1 ? 7 : weekday - 1
    }
}

extension MAAClientChannel {
    var fightStageServer: FightStageSchedule.Server {
        switch self {
        case .Official, .Bilibili: .official
        case .YoStarEN: .yoStarEN
        case .YoStarJP: .yoStarJP
        case .YoStarKR: .yoStarKR
        case .txwy: .txwy
        }
    }
}

extension MAAStageActivity {
    var fightScheduleData: FightStageSchedule.ActivityData {
        var stageWindows = [String: FightStageSchedule.ActivityWindow]()
        if let sideStoryStage {
            for sideStory in sideStoryStage.values {
                guard let window = sideStory.activity.window else { continue }
                for stage in sideStory.stages { stageWindows[stage.value] = window }
            }
        }
        return .init(resourceCollection: resourceCollection?.window, stageWindows: stageWindows)
    }
}
