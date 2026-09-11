//
//  HGCalendar.swift
//  MAA
//
//  Created by hguandl on 2026/9/11.
//

import Foundation

public struct HGCalendar: Sendable {
    let calendar: Calendar
    let resetTime: DateComponents
    private let resetOffset: DateComponents

    private func shifted(_ date: Date) -> Date {
        calendar.date(byAdding: resetOffset, to: date)!
    }

    public func isDate(_ date1: Date, inSameDayAs date2: Date) -> Bool {
        calendar.isDate(shifted(date1), inSameDayAs: shifted(date2))
    }

    public func weekday(for date: Date) -> Int {
        calendar.component(.weekday, from: shifted(date)) - 1
    }

    public func weekdaySymbol(for date: Date) -> String {
        calendar.weekdaySymbols[weekday(for: date)]
    }

    public func nextReset(after date: Date) -> Date {
        calendar.nextDate(after: date, matching: resetTime, matchingPolicy: .nextTime)!
    }
}

extension MAAClientChannel {
    var calendar: HGCalendar {
        switch self {
        case .Official, .Bilibili, .txwy:
            HGCalendar(timeZone: .utc(hours: 8), resetTime: resetTime)
        case .YoStarEN:
            HGCalendar(timeZone: .utc(hours: -7), resetTime: resetTime)
        case .YoStarJP, .YoStarKR:
            HGCalendar(timeZone: .utc(hours: 9), resetTime: resetTime)
        }
    }
}

extension HGCalendar {
    fileprivate init(timeZone: TimeZone, resetTime: DateComponents) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.resetTime = resetTime
        resetOffset = .init(
            hour: -(resetTime.hour ?? 0),
            minute: -(resetTime.minute ?? 0),
            second: -(resetTime.second ?? 0))
    }
}

extension TimeZone {
    fileprivate static func utc(hours: Int) -> TimeZone {
        TimeZone(secondsFromGMT: hours * 3600)!
    }
}

private let resetTime = DateComponents(hour: 4, minute: 0, second: 0)
