//
//  MAAStage.swift
//  MAA
//
//  Stage activity parsing and open-stage computation.
//  Ported from MaaWpfGui StageManager / StageInfo / StageActivityInfo.
//  Parses the V2 schema (gui/StageActivityV2.json).
//

import Foundation

// MARK: - Raw JSON Models (gui/StageActivityV2.json)

/// Top-level structure of `gui/StageActivityV2.json`, keyed by client channel.
struct StageActivityFile: Codable {
    let Official: StageActivityServer?
    let YoStarEN: StageActivityServer?
    let YoStarJP: StageActivityServer?
    let YoStarKR: StageActivityServer?
    let txwy: StageActivityServer?

    func server(for channel: MAAClientChannel) -> StageActivityServer? {
        switch channel {
        case .Official, .Bilibili:
            return Official
        case .YoStarEN:
            return YoStarEN
        case .YoStarJP:
            return YoStarJP
        case .YoStarKR:
            return YoStarKR
        case .txwy:
            return txwy
        }
    }
}

struct StageActivityServer: Codable {
    /// In V2 the side-story stages are grouped by activity name (e.g. "SSReopen", "TD").
    /// Each group shares one `Activity` (open window) and lists its `Stages`.
    let sideStoryStage: [String: StageActivityGroup]?
    let resourceCollection: StageActivityDetail?
    let miniGame: [MiniGameEntry]?
}

struct StageActivityGroup: Codable {
    let Activity: StageActivityDetail?
    let Stages: [StageActivityStage]?
    let MinimumRequired: String?
}

struct StageActivityStage: Codable {
    let Display: String
    let Value: String
    let Drop: String?
    let MinimumRequired: String?
}

struct StageActivityDetail: Codable {
    let Tip: String?
    let StageName: String?
    let UtcStartTime: String?
    let UtcExpireTime: String?
    let TimeZone: Int?
    let IsResourceCollection: Bool?
}

struct MiniGameEntry: Codable {
    let Display: String?
    let DisplayKey: String?
    let Value: String?
    let Tip: String?
    let TipKey: String?
    let UtcStartTime: String?
    let UtcExpireTime: String?
    let TimeZone: Int?
    let MinimumRequired: String?
}

// MARK: - Runtime Activity Info

/// Open/expire computation for an activity, mirroring `StageActivityInfo` on Windows.
struct StageActivityInfo: Equatable {
    var tip: String = ""
    var stageName: String = ""
    var startTime: Date
    var expireTime: Date
    var isResourceCollection = false

    /// Activity currently open: started and not yet expired.
    var beingOpen: Bool { status().beingOpen }

    var isExpired: Bool { status().isExpired }

    var notOpenYet: Bool { status().notOpenYet }

    /// Computes the open/expired flags at a single point in time. Capturing one `date`
    /// avoids inconsistencies near boundary times (each `Date()` call would otherwise
    /// differ by a few milliseconds).
    func status(at date: Date = Date()) -> (beingOpen: Bool, isExpired: Bool, notOpenYet: Bool) {
        let isExpired = date >= expireTime
        let notOpenYet = date <= startTime
        return (!notOpenYet && !isExpired, isExpired, notOpenYet)
    }

    init(
        tip: String = "", stageName: String = "", startTime: Date, expireTime: Date,
        isResourceCollection: Bool = false
    ) {
        self.tip = tip
        self.stageName = stageName
        self.startTime = startTime
        self.expireTime = expireTime
        self.isResourceCollection = isResourceCollection
    }

    /// Build from raw JSON detail. Times are parsed in the activity's own timezone.
    init?(detail: StageActivityDetail) {
        guard let start = Self.parseDate(detail.UtcStartTime, timeZone: detail.TimeZone),
            let expire = Self.parseDate(detail.UtcExpireTime, timeZone: detail.TimeZone)
        else {
            return nil
        }
        self.tip = detail.Tip ?? ""
        self.stageName = detail.StageName ?? ""
        self.startTime = start
        self.expireTime = expire
        self.isResourceCollection = detail.IsResourceCollection ?? false
    }

    /// Parses `"yyyy/MM/dd HH:mm:ss"` interpreted in the given timezone offset (hours).
    static func parseDate(_ string: String?, timeZone: Int?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: (timeZone ?? 8) * 3600)
        return formatter.date(from: string)
    }
}

// MARK: - Stage Info

/// A single stage entry, mirroring `StageInfo` on Windows.
struct MAAStageInfo: Identifiable, Equatable {
    var display: String
    var value: String
    var tip: String = ""
    var drop: String?

    /// Days of week (1 = Sunday ... 7 = Saturday, matching `Calendar` weekday) on which a
    /// resource stage is open. `nil`/empty means always open.
    var openDaysOfWeek: [Int]?

    var activity: StageActivityInfo?

    /// Hidden stages are still reachable via manual input but not listed.
    var isHidden = false

    var id: String { value }

    /// Whether the associated activity exists and has expired (used for strikethrough display).
    var isOutdated: Bool {
        guard let activity else { return false }
        return activity.isExpired && !activity.isResourceCollection
    }

    /// Whether the stage is open on the given weekday (1 = Sunday ... 7 = Saturday).
    func isStageOpen(weekday: Int) -> Bool {
        if let activity {
            let status = activity.status()
            if status.beingOpen {
                return true
            }
            // Expired non-resource activity is closed.
            if !activity.isResourceCollection {
                return false
            }
            // Expired resource activity falls through to weekly schedule.
        }

        if let openDaysOfWeek, !openDaysOfWeek.isEmpty {
            return openDaysOfWeek.contains(weekday)
        }

        return true
    }
}
