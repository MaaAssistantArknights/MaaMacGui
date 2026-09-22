//
//  UserDataUpdateConfiguration.swift
//  MAA
//
//  Created by zhangweijian on 22/9/2026.
//

import Foundation

struct UserDataUpdateConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .UserDataUpdate }

    var updateOperBox: Bool
    var updateDepot: Bool
    var triggerInterval: UserDataUpdateTriggerInterval

    var title: String {
        type.description
    }

    var subtitle: String {
        var items = [String]()
        if updateOperBox {
            items.append(String(localized: "干员识别"))
        }
        if updateDepot {
            items.append(String(localized: "仓库识别"))
        }
        return items.joined(separator: " ")
    }

    var summary: String {
        triggerInterval.description
    }

    var projectedTask: MAATask {
        .userdataupdate(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }
}

extension UserDataUpdateConfiguration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.updateOperBox = try container.decodeIfPresent(Bool.self, forKey: .updateOperBox) ?? true
        self.updateDepot = try container.decodeIfPresent(Bool.self, forKey: .updateDepot) ?? true
        self.triggerInterval =
            try container.decodeIfPresent(UserDataUpdateTriggerInterval.self, forKey: .triggerInterval)
            ?? .everyTime
    }
}

/// 「更新数据」的触发间隔
enum UserDataUpdateTriggerInterval: String, Codable, CaseIterable, CustomStringConvertible {
    /// 每次运行都同步
    case everyTime
    /// 每个游戏日（凌晨 4 点日界）同步一次
    case daily
    /// 每个 ISO 周同步一次
    case weekly

    var description: String {
        switch self {
        case .everyTime:
            return String(localized: "每次")
        case .daily:
            return String(localized: "每天")
        case .weekly:
            return String(localized: "每周")
        }
    }
}

extension UserDataUpdateTriggerInterval {
    /// 距离上次同步是否已达到触发间隔。
    ///
    /// 对齐 WPF 口径：按客户端时区的凌晨 4 点日界切分游戏日，`daily` 比较游戏日、
    /// `weekly` 比较 ISO 周；没有上次同步时间视为到期。
    func isDue(lastSyncTime: Date?, channel: MAAClientChannel) -> Bool {
        guard self != .everyTime, let lastSyncTime else {
            return true
        }

        let utcOffsetHours = channel.utcOffsetHours
        let now = Self.gameDay(of: .now, utcOffsetHours: utcOffsetHours)
        let last = Self.gameDay(of: lastSyncTime, utcOffsetHours: utcOffsetHours)

        switch self {
        case .everyTime:
            return true
        case .daily:
            return now > last
        case .weekly:
            let calendar = Self.calendar(identifier: .iso8601, utcOffsetHours: utcOffsetHours)
            return calendar.component(.yearForWeekOfYear, from: now)
                != calendar.component(.yearForWeekOfYear, from: last)
                || calendar.component(.weekOfYear, from: now) != calendar.component(.weekOfYear, from: last)
        }
    }

    /// 游戏日界：客户端所在时区的凌晨 4 点
    private static let gameDayStartHour = 4

    /// 取 `date` 所属游戏日的零点
    private static func gameDay(of date: Date, utcOffsetHours: Int) -> Date {
        let calendar = calendar(identifier: .gregorian, utcOffsetHours: utcOffsetHours)
        return calendar.startOfDay(for: date.addingTimeInterval(-Double(gameDayStartHour) * 3600))
    }

    private static func calendar(identifier: Calendar.Identifier, utcOffsetHours: Int) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffsetHours * 3600)!
        return calendar
    }
}

extension MAAClientChannel {
    /// 客户端所在时区（对齐 WPF `DateTimeExtension`；固定偏移，不含夏令时）
    var utcOffsetHours: Int {
        switch self {
        case .Official, .Bilibili, .txwy:
            return 8
        case .YoStarEN:
            return -7
        case .YoStarJP, .YoStarKR:
            return 9
        }
    }
}
