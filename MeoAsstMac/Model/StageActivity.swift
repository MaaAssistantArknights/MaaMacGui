//
//  StageActivity.swift
//  MAA
//
//  Created by hguandl on 2026/9/11.
//

import Foundation

struct StageActivityContext {
    let channel: MAAClientChannel
    let activities: MAAStageActivity?
}

extension StageActivityContext {
    func resourceCollectionStageIsOpen(at date: Date, in weekdays: [Int]?) -> Bool {
        if let weekdays, !weekdays.contains(channel.calendar.weekday(for: date)) {
            return false
        }
        return true
    }
}

extension StageActivityContext {
    enum MedicineWindow: Equatable {
        case inactive
        case unavailable
        case extended(days: Int)
    }

    func medicineWindow(at date: Date, enabled: Bool) -> MedicineWindow {
        guard enabled else { return .inactive }
        guard let groups = activities?.sideStoryStage else { return .unavailable }

        var activeEnds: [Date] = []
        var validGroups = 0
        for group in groups.values {
            // Only grouped SideStory stages are known to describe a farming
            // activity. Mini-games and resource-all-open periods are excluded.
            guard let stages = group.Stages, !stages.isEmpty,
                stages.allSatisfy({ !($0.Value ?? "").isEmpty }),
                let period = group.Activity, let range = period.interval
            else { continue }  // One malformed group must not hide valid peers.
            validGroups += 1
            if range.start <= date && date < range.end {
                activeEnds.append(range.end)
            }
        }
        // A non-empty payload whose groups all failed to parse means the
        // remote data is broken; an empty payload has no activity at all.
        if !groups.isEmpty, validGroups == 0 { return .unavailable }
        guard let end = activeEnds.min(), end.timeIntervalSince(date) < 48 * 3600 else { return .inactive }
        return .extended(days: channel.calendar.medicineExpiryDaysUntilWeekEnd(at: date))
    }
}

extension MAAStageActivity {
    struct SideStoryStage: Decodable, Hashable {
        let Activity: ActivityPeriod?
        let Stages: [SideStoryStageItem]?
    }

    struct SideStoryStageItem: Decodable, Hashable {
        let Value: String?
    }

    struct ActivityPeriod: Decodable, Hashable {
        let UtcStartTime: String?
        let UtcExpireTime: String?
        let TimeZone: Double?

        var interval: DateInterval? {
            guard let offset = TimeZone, offset.isFinite, (-12...14).contains(offset),
                let timeZone = Foundation.TimeZone(secondsFromGMT: Int(offset * 3600)),
                let startText = UtcStartTime, let endText = UtcExpireTime
            else { return nil }
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.calendar = Calendar(identifier: .gregorian)
            parser.timeZone = timeZone
            parser.dateFormat = "yyyy/MM/dd HH:mm:ss"
            parser.isLenient = false
            guard let start = parser.date(from: startText), let end = parser.date(from: endText),
                parser.string(from: start) == startText, parser.string(from: end) == endText, start < end
            else { return nil }
            return DateInterval(start: start, end: end)
        }
    }
}

extension MAAClientChannel {
    var stageActivityKey: String { self == .Bilibili ? MAAClientChannel.Official.rawValue : rawValue }
}
