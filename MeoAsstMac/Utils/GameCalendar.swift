//
//  GameCalendar.swift
//  MAA
//
//  Game-server day calculation, ported from MaaWpfGui DateTimeExtension.
//  The in-game day rolls over at 04:00 server-local time (YjDayStartHour),
//  so "today" for stage scheduling is offset accordingly.
//

import Foundation

enum GameCalendar {
    /// The in-game day starts at 04:00 server-local time.
    private static let dayStartHour = 4

    /// Server timezone offset (hours from UTC) per client channel, matching the
    /// Windows `_clientTypeTimezone` table.
    static func timezoneOffset(for channel: MAAClientChannel) -> Int {
        switch channel {
        case .Official, .Bilibili, .txwy:
            return 8
        case .YoStarEN:
            return -7
        case .YoStarJP, .YoStarKR:
            return 9
        }
    }

    /// Converts a wall-clock instant to the "Yj" datetime used for day-rollover logic:
    /// `UTC + (serverTimezone - dayStartHour)`. The result's calendar fields (in UTC)
    /// represent the in-game date/time.
    static func yjDate(for date: Date = Date(), channel: MAAClientChannel) -> Date {
        let shiftHours = timezoneOffset(for: channel) - dayStartHour
        return date.addingTimeInterval(TimeInterval(shiftHours * 3600))
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// In-game weekday (1 = Sunday ... 7 = Saturday, matching `Calendar.weekday`).
    static func yjWeekday(for date: Date = Date(), channel: MAAClientChannel) -> Int {
        utcCalendar.component(.weekday, from: yjDate(for: date, channel: channel))
    }

    /// In-game calendar day, used to detect day rollover for hot updates.
    static func yjDay(for date: Date = Date(), channel: MAAClientChannel) -> DateComponents {
        utcCalendar.dateComponents([.year, .month, .day], from: yjDate(for: date, channel: channel))
    }

    /// In-game hour and minute, used to detect the 0:00 / 12:00 refresh points
    /// (server 04:00 / 16:00).
    static func yjHourMinute(for date: Date = Date(), channel: MAAClientChannel) -> (hour: Int, minute: Int) {
        let comps = utcCalendar.dateComponents([.hour, .minute], from: yjDate(for: date, channel: channel))
        return (comps.hour ?? 0, comps.minute ?? 0)
    }
}
