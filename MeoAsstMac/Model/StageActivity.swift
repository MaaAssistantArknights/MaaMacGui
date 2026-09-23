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
        if resourceCollectionIsOpen(at: date) {
            return true
        }
        if let weekdays, !weekdays.contains(channel.calendar.weekday(for: date)) {
            return false
        }
        return true
    }

    /// 资源全开放活动进行中（期间资源收集关卡无视周几全部开放）。
    func resourceCollectionIsOpen(at date: Date) -> Bool {
        guard let period = activities?.resourceCollection else { return false }
        return period.startDate <= date && date <= period.expireDate
    }

    /// 进行中的限时活动（SideStory 等），按结束时间升序。
    var ongoingSideStories: [(key: String, period: MAAStageActivity.ActivityPeriod, stages: [MAAStageActivity.SideStoryStageItem])] {
        guard let groups = activities?.sideStoryStage else { return [] }
        let now = Date.now
        return groups.compactMap { key, group in
            guard let period = group.Activity,
                period.startDate <= now, now <= period.expireDate
            else { return nil }
            return (key, period, group.Stages ?? [])
        }
        .sorted { $0.period.expireDate < $1.period.expireDate }
    }
}
