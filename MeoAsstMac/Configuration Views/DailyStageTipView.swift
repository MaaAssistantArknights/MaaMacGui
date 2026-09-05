//
//  DailyStageTipView.swift
//  MAA
//
//  Created by zhangweijian on 5/9/2026.
//

import SwiftUI

// MARK: - Daily stage tip

/// 每日轮换资源关卡的开放提示。
///
/// 开放表与游戏内日历（yj 历）的换算参照 MaaWpfGui 的实现：
/// 各服务器按当地时区的凌晨 4 点作为一天的开始。
enum DailyStageTip {
    enum Weekday: Int, CaseIterable {
        case sunday = 1
        case monday, tuesday, wednesday, thursday, friday, saturday

        var localizedName: String {
            switch self {
            case .sunday: String(localized: "星期日")
            case .monday: String(localized: "星期一")
            case .tuesday: String(localized: "星期二")
            case .wednesday: String(localized: "星期三")
            case .thursday: String(localized: "星期四")
            case .friday: String(localized: "星期五")
            case .saturday: String(localized: "星期六")
            }
        }
    }

    struct Stage {
        let code: String
        let name: String
        let weekdays: Set<Weekday>
    }

    /// 每日轮换关卡的开放日（游戏事实数据，与 MAAUnified 的开放表保持一致）
    private static let stages: [Stage] = [
        Stage(code: "CE-6", name: String(localized: "龙门币"), weekdays: [.tuesday, .thursday, .saturday, .sunday]),
        Stage(code: "AP-5", name: String(localized: "红票"), weekdays: [.monday, .thursday, .saturday, .sunday]),
        Stage(code: "CA-5", name: String(localized: "技能"), weekdays: [.tuesday, .wednesday, .friday, .sunday]),
        Stage(code: "SK-5", name: String(localized: "碳"), weekdays: [.monday, .wednesday, .friday, .saturday]),
        Stage(code: "LS-6", name: String(localized: "经验"), weekdays: Set(Weekday.allCases)),
        Stage(code: "PR-A-1/2", name: String(localized: "奶&盾芯片"), weekdays: [.monday, .thursday, .friday, .sunday]),
        Stage(code: "PR-B-1/2", name: String(localized: "术&狙芯片"), weekdays: [.monday, .tuesday, .friday, .saturday]),
        Stage(code: "PR-C-1/2", name: String(localized: "先&辅芯片"), weekdays: [.wednesday, .thursday, .saturday, .sunday]),
        Stage(code: "PR-D-1/2", name: String(localized: "近&特芯片"), weekdays: [.tuesday, .wednesday, .saturday, .sunday]),
    ]

    /// 各服务器游戏历法对应的当地时区
    ///
    /// YoStarEN 服务器位于北美太平洋时区，实行夏令时（PDT UTC-7 / PST UTC-8），
    /// 按 IANA 时区规则随季节自动换算。
    private static func localTimeZone(channel: MAAClientChannel) -> TimeZone {
        switch channel {
        case .Official, .Bilibili, .txwy: TimeZone(identifier: "Asia/Shanghai")!
        case .YoStarEN: TimeZone(identifier: "America/Los_Angeles")!
        case .YoStarJP: TimeZone(identifier: "Asia/Tokyo")!
        case .YoStarKR: TimeZone(identifier: "Asia/Seoul")!
        }
    }

    /// 游戏内日历：当地时区、凌晨 4 点为一天的开始
    private static func yjCalendar(channel: MAAClientChannel) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = localTimeZone(channel: channel)
        return calendar
    }

    /// 游戏内日历（yj 历）下的今天星期几
    static func yjWeekday(channel: MAAClientChannel, date: Date = .now) -> Weekday {
        let calendar = yjCalendar(channel: channel)
        // 以当地挂钟时间 04:00 为日切：未过 04:00 仍算前一天
        var inGameDate = calendar.startOfDay(for: date)
        if calendar.component(.hour, from: date) < 4 {
            inGameDate = calendar.date(byAdding: .day, value: -1, to: inGameDate) ?? inGameDate
        }
        return Weekday(rawValue: calendar.component(.weekday, from: inGameDate)) ?? .sunday
    }

    /// 今日开放的每日轮换关卡
    static func openStages(channel: MAAClientChannel, date: Date = .now) -> [Stage] {
        let weekday = yjWeekday(channel: channel, date: date)
        return stages.filter { $0.weekdays.contains(weekday) }
    }
}

// MARK: - View

/// 内嵌于刷理智设置页底部的今日开放关卡展示。
struct DailyStageTipView: View {
    @AppStorage("MAAClientChannel") private var clientChannel = MAAClientChannel.Official

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("今日关卡小提示")
                    .font(.headline)
                Spacer()
                Text(String(localized: "游戏内历法：\(weekdayName)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(openStages, id: \.code) { stage in
                Text(verbatim: "\(stage.code): \(stage.name)")
                    .font(.callout)
            }
        }
    }

    private var openStages: [DailyStageTip.Stage] {
        DailyStageTip.openStages(channel: clientChannel)
    }

    private var weekdayName: String {
        DailyStageTip.yjWeekday(channel: clientChannel).localizedName
    }
}

struct DailyStageTipView_Previews: PreviewProvider {
    static var previews: some View {
        DailyStageTipView()
            .environment(\.locale, Locale(identifier: "zh-Hans"))
    }
}
