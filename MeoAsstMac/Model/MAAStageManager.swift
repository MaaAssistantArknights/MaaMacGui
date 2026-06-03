//
//  MAAStageManager.swift
//  MAA
//
//  Loads stage activity data and merges permanent resource stages.
//  Ported from MaaWpfGui StageManager.
//

import Foundation

/// Stateless helper that builds the stage list. The resulting `[MAAStageInfo]` is held
/// as `@Published` state on `MAAViewModel` so SwiftUI views observe it directly.
enum MAAStageManager {
    /// Cache file written by the OTA service (documentDirectory/cache/gui/StageActivityV2.json).
    private static var cacheURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("cache")
            .appendingPathComponent("gui")
            .appendingPathComponent("StageActivityV2.json")
    }

    /// Build the stage list for the given channel. Safe to call when the cache is missing;
    /// in that case only the permanent stages are produced.
    static func loadStages(channel: MAAClientChannel) -> [MAAStageInfo] {
        let server = loadServer(channel: channel)
        var result: [MAAStageInfo] = []

        let resourceCollection: StageActivityInfo? = server?.resourceCollection.flatMap {
            var info = StageActivityInfo(detail: $0)
            info?.isResourceCollection = true
            return info
        }

        // Activity (side story) stages. In V2 each named group shares one Activity window,
        // applied to every stage in that group.
        for group in (server?.sideStoryStage ?? [:]).values {
            let activity = group.Activity.flatMap(StageActivityInfo.init(detail:))
            for stage in group.Stages ?? [] {
                result.append(
                    MAAStageInfo(
                        display: stage.Display,
                        value: stage.Value,
                        tip: activity?.tip ?? "",
                        drop: stage.Drop,
                        openDaysOfWeek: nil,
                        activity: activity))
            }
        }

        // Permanent stages (main story, resource stages, chip stages, annihilation).
        let existing = Set(result.map(\.value))
        for stage in permanentStages(resourceCollection: resourceCollection) where !existing.contains(stage.value) {
            result.append(stage)
        }

        return result
    }

    // MARK: - Loading

    private static func loadServer(channel: MAAClientChannel) -> StageActivityServer? {
        guard let data = try? Data(contentsOf: cacheURL),
            let file = try? JSONDecoder().decode(StageActivityFile.self, from: data)
        else {
            return nil
        }
        return file.server(for: channel)
    }

    // MARK: - Permanent Stages

    /// Weekday constants matching `Calendar.component(.weekday)` (Sunday = 1 ... Saturday = 7).
    private enum Weekday {
        static let sunday = 1
        static let monday = 2
        static let tuesday = 3
        static let wednesday = 4
        static let thursday = 5
        static let friday = 6
        static let saturday = 7
    }

    /// Permanent stages with weekly open schedules, ported from `StageManager.AddPermanentStages`.
    private static func permanentStages(resourceCollection: StageActivityInfo?) -> [MAAStageInfo] {
        typealias W = Weekday
        func resource(
            _ value: String, tip: String, days: [Int], drop: String? = nil
        ) -> MAAStageInfo {
            MAAStageInfo(
                display: value, value: value, tip: tip, drop: drop,
                openDaysOfWeek: days, activity: resourceCollection)
        }

        return [
            // 主线关卡
            MAAStageInfo(display: "1-7", value: "1-7"),
            MAAStageInfo(display: "R8-11", value: "R8-11"),
            MAAStageInfo(display: "12-17-HARD", value: "12-17-HARD"),

            // 资源本（开放日仅由 days 维护一处；tip 只放材料名，对齐 Windows 的 CETip 等文案，
            // 关卡是否开放通过下拉中的变灰/隐藏体现，不在 tip 里重复描述星期）
            resource(
                "CE-6", tip: String(localized: "CE-6: 龙门币"),
                days: [W.tuesday, W.thursday, W.saturday, W.sunday]),
            resource(
                "AP-5", tip: String(localized: "AP-5: 红票"),
                days: [W.monday, W.thursday, W.saturday, W.sunday]),
            resource(
                "CA-5", tip: String(localized: "CA-5: 技能书"),
                days: [W.tuesday, W.wednesday, W.friday, W.sunday]),
            resource("LS-6", tip: String(localized: "LS-6: 经验书"), days: []),
            resource(
                "SK-5", tip: String(localized: "SK-5: 碳条"),
                days: [W.monday, W.wednesday, W.friday, W.saturday]),

            // 剿灭模式
            MAAStageInfo(display: String(localized: "剿灭模式"), value: "Annihilation"),

            // 芯片本（PR-X-1 与 PR-X-2 掉落同类芯片，仅效率不同）
            resource(
                "PR-A-1", tip: String(localized: "PR-A-1/2: 重装、医疗芯片"),
                days: [W.monday, W.thursday, W.friday, W.sunday]),
            resource(
                "PR-A-2", tip: String(localized: "PR-A-1/2: 重装、医疗芯片"),
                days: [W.monday, W.thursday, W.friday, W.sunday]),
            resource(
                "PR-B-1", tip: String(localized: "PR-B-1/2: 狙击、术师芯片"),
                days: [W.monday, W.tuesday, W.friday, W.saturday]),
            resource(
                "PR-B-2", tip: String(localized: "PR-B-1/2: 狙击、术师芯片"),
                days: [W.monday, W.tuesday, W.friday, W.saturday]),
            resource(
                "PR-C-1", tip: String(localized: "PR-C-1/2: 先锋、辅助芯片"),
                days: [W.wednesday, W.thursday, W.saturday, W.sunday]),
            resource(
                "PR-C-2", tip: String(localized: "PR-C-1/2: 先锋、辅助芯片"),
                days: [W.wednesday, W.thursday, W.saturday, W.sunday]),
            resource(
                "PR-D-1", tip: String(localized: "PR-D-1/2: 近卫、特种芯片"),
                days: [W.tuesday, W.wednesday, W.saturday, W.sunday]),
            resource(
                "PR-D-2", tip: String(localized: "PR-D-1/2: 近卫、特种芯片"),
                days: [W.tuesday, W.wednesday, W.saturday, W.sunday]),

            // 常驻活动关，隐藏但仍可通过手动输入访问
            MAAStageInfo(display: "OF-1", value: "OF-1", isHidden: true),
            MAAStageInfo(display: "OF-F3", value: "OF-F3", isHidden: true),
        ]
    }
}

// MARK: - Filtering Helpers

extension Array where Element == MAAStageInfo {
    /// Stages visible in the picker for the given weekday, optionally hiding closed ones.
    func listedStages(hideClosed: Bool, weekday: Int) -> [MAAStageInfo] {
        filter { stage in
            guard !stage.isHidden else { return false }
            if hideClosed {
                return stage.isStageOpen(weekday: weekday)
            }
            return true
        }
    }

    func stageInfo(for value: String) -> MAAStageInfo? {
        first { $0.value == value }
    }
}
