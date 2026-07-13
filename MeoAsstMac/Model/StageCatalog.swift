//
//  StageCatalog.swift
//  MAA
//

import Foundation

enum StageServer: Equatable {
    case official
    case bilibili
    case yoStarEN
    case yoStarJP
    case yoStarKR
    case txwy

    init(channelRawValue: String) {
        switch channelRawValue {
        case "Bilibili": self = .bilibili
        case "YoStarEN": self = .yoStarEN
        case "YoStarJP": self = .yoStarJP
        case "YoStarKR": self = .yoStarKR
        case "txwy": self = .txwy
        default: self = .official
        }
    }

    fileprivate var apiKey: String {
        switch self {
        case .official, .bilibili: "Official"
        case .yoStarEN: "YoStarEN"
        case .yoStarJP: "YoStarJP"
        case .yoStarKR: "YoStarKR"
        case .txwy: "txwy"
        }
    }

    fileprivate var timeZoneOffset: Int {
        switch self {
        case .official, .bilibili, .txwy: 8
        case .yoStarEN: -7
        case .yoStarJP, .yoStarKR: 9
        }
    }
}

enum StageKind: Equatable {
    case permanent
    case resource
    case chip
    case sideStory
}

struct StageActivity: Equatable {
    let start: Date
    let expire: Date
}

struct TodayStageActivity: Identifiable, Equatable {
    let name: String
    let expire: Date

    var id: String { "\(name)-\(expire.timeIntervalSince1970)" }
}

struct TodayStageSummary: Equatable {
    let localizedTipKeys: [String]
    let activities: [TodayStageActivity]
}

struct StageDescriptor: Identifiable, Equatable {
    let id: String
    let display: String
    let kind: StageKind
    let openWeekdays: Set<Int>?
    let activity: StageActivity?
    let activityName: String?
    let minimumRequired: String?
    let tipKey: String?

    init(
        id: String,
        display: String? = nil,
        kind: StageKind,
        openWeekdays: Set<Int>? = nil,
        activity: StageActivity? = nil,
        activityName: String? = nil,
        minimumRequired: String? = nil,
        tipKey: String? = nil
    ) {
        self.id = id
        self.display = display ?? id
        self.kind = kind
        self.openWeekdays = openWeekdays
        self.activity = activity
        self.activityName = activityName
        self.minimumRequired = minimumRequired
        self.tipKey = tipKey
    }
}

enum StageAvailability: Equatable {
    case open
    case closedForWeeklySchedule
    case activityNotStarted
    case activityExpired
    case unsupportedCoreVersion(required: String)

    var isOpen: Bool { self == .open }
}

struct StageCatalog {
    private let clients: [String: StageActivityClient]

    init() {
        clients = [:]
    }

    init(data: Data) throws {
        clients = try JSONDecoder().decode(StageActivityDocument.self, from: data).clients
    }

    func stages(for server: StageServer) -> [StageDescriptor] {
        var result = Self.builtInStages
        var knownValues = Set(result.map(\.id))

        guard let client = clients[server.apiKey] else { return result }
        for group in client.sideStories {
            for stage in group.stages {
                let activityPayload = stage.activity ?? group.activity
                guard let activity = activityPayload.flatMap(Self.parseActivity) else { continue }
                guard let value = stage.value, !value.isEmpty, knownValues.insert(value).inserted else { continue }
                result.append(
                    StageDescriptor(
                        id: value,
                        display: stage.display ?? value,
                        kind: .sideStory,
                        activity: activity,
                        activityName: activityPayload?.stageName ?? group.activity?.stageName,
                        minimumRequired: stage.minimumRequired ?? group.minimumRequired))
            }
        }
        return result
    }

    func todaySummary(for server: StageServer, now: Date, coreVersion: String?) -> TodayStageSummary {
        var localizedTipKeys: [String] = []
        switch serverWeekday(for: server, now: now) {
        case 1:
            localizedTipKeys.append("周日了，记得打剿灭哦~")
        case 2:
            localizedTipKeys.append("周一了，可以打剿灭了~")
        default:
            break
        }

        localizedTipKeys.append(
            contentsOf: stages(for: server).compactMap { stage in
                guard stage.kind == .resource || stage.kind == .chip,
                    availability(of: stage, server: server, now: now, coreVersion: coreVersion).isOpen
                else {
                    return nil
                }
                return stage.tipKey
            })

        var activities: [TodayStageActivity] = []
        var knownActivities = Set<String>()
        if let resourceCollection = clients[server.apiKey]?.resourceCollection,
            let name = resourceCollection.tip,
            !name.isEmpty,
            let activity = Self.parseActivity(resourceCollection),
            activity.start <= now,
            now <= activity.expire
        {
            activities.append(TodayStageActivity(name: name, expire: activity.expire))
            knownActivities.insert(name)
        }

        for stage in stages(for: server) where stage.kind == .sideStory {
            guard availability(of: stage, server: server, now: now, coreVersion: coreVersion).isOpen,
                let name = stage.activityName,
                !name.isEmpty,
                knownActivities.insert(name).inserted,
                let activity = stage.activity
            else {
                continue
            }
            activities.append(TodayStageActivity(name: name, expire: activity.expire))
        }

        return TodayStageSummary(localizedTipKeys: localizedTipKeys, activities: activities)
    }

    func availability(
        of stage: StageDescriptor,
        server: StageServer,
        now: Date,
        coreVersion: String?
    ) -> StageAvailability {
        switch stage.kind {
        case .permanent:
            return .open

        case .resource, .chip:
            if resourceCollectionIsOpen(for: server, now: now) {
                return .open
            }
            guard let openWeekdays = stage.openWeekdays, !openWeekdays.isEmpty else { return .open }
            return openWeekdays.contains(serverWeekday(for: server, now: now))
                ? .open
                : .closedForWeeklySchedule

        case .sideStory:
            guard let activity = stage.activity else { return .activityExpired }
            if now < activity.start { return .activityNotStarted }
            if now > activity.expire { return .activityExpired }

            if let required = stage.minimumRequired {
                if coreVersion == "DEBUG_VERSION" { return .open }
                guard let requiredVersion = SemanticVersion(required),
                    let coreVersion,
                    let currentVersion = SemanticVersion(coreVersion),
                    currentVersion >= requiredVersion
                else {
                    return .unsupportedCoreVersion(required: required)
                }
            }
            return .open
        }
    }

    func normalizedStageID(
        _ stageID: String,
        server: StageServer,
        now: Date,
        coreVersion: String?
    ) -> String {
        guard let stage = stages(for: server).first(where: { $0.id == stageID }) else {
            return stageID
        }
        return availability(of: stage, server: server, now: now, coreVersion: coreVersion).isOpen ? stageID : ""
    }

    static func builtInDisplayName(for stageID: String) -> String? {
        builtInStages.first(where: { $0.id == stageID })?.display
    }

    func serverWeekday(for server: StageServer, now: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: server.timeZoneOffset * 3600)!
        return calendar.component(.weekday, from: now.addingTimeInterval(-4 * 3600))
    }

    private func resourceCollectionIsOpen(for server: StageServer, now: Date) -> Bool {
        guard let payload = clients[server.apiKey]?.resourceCollection,
            payload.isResourceCollection == true,
            let activity = Self.parseActivity(payload)
        else {
            return false
        }
        return activity.start <= now && now <= activity.expire
    }

    private static func parseActivity(_ payload: StageActivityPayload) -> StageActivity? {
        guard let start = payload.utcStartTime,
            let expire = payload.utcExpireTime,
            let offset = payload.timeZone,
            (-18...18).contains(offset)
        else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: offset * 3600)
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"

        guard let startDate = formatter.date(from: start), let expireDate = formatter.date(from: expire) else {
            return nil
        }
        return StageActivity(start: startDate, expire: expireDate)
    }

    private static let builtInStages: [StageDescriptor] = [
        StageDescriptor(id: "", display: "当前/上次", kind: .permanent),
        StageDescriptor(id: "1-7", kind: .permanent),
        StageDescriptor(id: "Annihilation", display: "剿灭模式", kind: .permanent),
        StageDescriptor(
            id: "CE-6", kind: .resource, openWeekdays: [1, 3, 5, 7], tipKey: "CE-6: 龙门币"),
        StageDescriptor(id: "AP-5", kind: .resource, openWeekdays: [1, 2, 5, 7], tipKey: "AP-5: 红票"),
        StageDescriptor(id: "CA-5", kind: .resource, openWeekdays: [1, 3, 4, 6], tipKey: "CA-5: 技能"),
        StageDescriptor(id: "LS-6", kind: .resource, tipKey: "LS-6: 经验"),
        StageDescriptor(id: "SK-5", kind: .resource, openWeekdays: [2, 4, 6, 7], tipKey: "SK-5: 碳"),
        StageDescriptor(
            id: "PR-A-1", display: "奶/盾芯片", kind: .chip, openWeekdays: [1, 2, 5, 6],
            tipKey: "PR-A-1/2: 奶/盾芯片"),
        StageDescriptor(id: "PR-A-2", display: "奶/盾芯片组", kind: .chip, openWeekdays: [1, 2, 5, 6]),
        StageDescriptor(
            id: "PR-B-1", display: "术/狙芯片", kind: .chip, openWeekdays: [2, 3, 6, 7],
            tipKey: "PR-B-1/2: 术/狙芯片"),
        StageDescriptor(id: "PR-B-2", display: "术/狙芯片组", kind: .chip, openWeekdays: [2, 3, 6, 7]),
        StageDescriptor(
            id: "PR-C-1", display: "先/辅芯片", kind: .chip, openWeekdays: [1, 4, 5, 7],
            tipKey: "PR-C-1/2: 先/辅芯片"),
        StageDescriptor(id: "PR-C-2", display: "先/辅芯片组", kind: .chip, openWeekdays: [1, 4, 5, 7]),
        StageDescriptor(
            id: "PR-D-1", display: "近/特芯片", kind: .chip, openWeekdays: [1, 3, 4, 7],
            tipKey: "PR-D-1/2: 近/特芯片"),
        StageDescriptor(id: "PR-D-2", display: "近/特芯片组", kind: .chip, openWeekdays: [1, 3, 4, 7]),
    ]
}

private struct StageActivityDocument: Decodable {
    let clients: [String: StageActivityClient]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var clients: [String: StageActivityClient] = [:]
        for key in container.allKeys {
            if let client = try? container.decode(StageActivityClient.self, forKey: key) {
                clients[key.stringValue] = client
            }
        }
        self.clients = clients
    }
}

private struct StageActivityClient: Decodable {
    let sideStories: [StageActivityGroup]
    let resourceCollection: StageActivityPayload?

    private enum CodingKeys: String, CodingKey {
        case sideStoryStage
        case resourceCollection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resourceCollection = try? container.decode(StageActivityPayload.self, forKey: .resourceCollection)

        guard
            let sideStoryContainer = try? container.nestedContainer(
                keyedBy: DynamicCodingKey.self, forKey: .sideStoryStage)
        else {
            sideStories = []
            return
        }

        sideStories = sideStoryContainer.allKeys.compactMap {
            try? sideStoryContainer.decode(StageActivityGroup.self, forKey: $0)
        }
    }
}

private struct StageActivityGroup: Decodable {
    let minimumRequired: String?
    let activity: StageActivityPayload?
    let stages: [StageActivityStagePayload]

    private enum CodingKeys: String, CodingKey {
        case minimumRequired = "MinimumRequired"
        case activity = "Activity"
        case stages = "Stages"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumRequired = try? container.decode(String.self, forKey: .minimumRequired)
        activity = try? container.decode(StageActivityPayload.self, forKey: .activity)
        stages = (try? container.decode([StageActivityStagePayload].self, forKey: .stages)) ?? []
    }
}

private struct StageActivityStagePayload: Decodable {
    let display: String?
    let value: String?
    let minimumRequired: String?
    let activity: StageActivityPayload?

    private enum CodingKeys: String, CodingKey {
        case display = "Display"
        case value = "Value"
        case minimumRequired = "MinimumRequired"
        case activity = "Activity"
    }
}

private struct StageActivityPayload: Decodable {
    let utcStartTime: String?
    let utcExpireTime: String?
    let timeZone: Int?
    let isResourceCollection: Bool?
    let tip: String?
    let stageName: String?

    private enum CodingKeys: String, CodingKey {
        case utcStartTime = "UtcStartTime"
        case utcExpireTime = "UtcExpireTime"
        case timeZone = "TimeZone"
        case isResourceCollection = "IsResourceCollection"
        case tip = "Tip"
        case stageName = "StageName"
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
    }
}

private struct SemanticVersion: Comparable {
    let core: [Int]
    private let prerelease: [Identifier]?

    init?(_ rawValue: String) {
        let value = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let parts = value.split(separator: "-", maxSplits: 1).map(String.init)
        let coreParts = parts[0].split(separator: ".")
        guard coreParts.count >= 2, coreParts.allSatisfy({ Int($0) != nil }) else { return nil }

        core = coreParts.map { Int($0)! }
        prerelease =
            parts.count == 2
            ? parts[1].split(separator: ".").map { Identifier(String($0)) }
            : nil
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let length = max(lhs.core.count, rhs.core.count)
        for index in 0..<length {
            let left = index < lhs.core.count ? lhs.core[index] : 0
            let right = index < rhs.core.count ? rhs.core[index] : 0
            if left != right { return left < right }
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case (.some(let left), .some(let right)):
            for index in 0..<max(left.count, right.count) {
                guard index < left.count else { return true }
                guard index < right.count else { return false }
                if left[index] != right[index] { return left[index] < right[index] }
            }
            return false
        }
    }

    private enum Identifier: Comparable {
        case number(Int)
        case text(String)

        init(_ value: String) {
            self = Int(value).map(Self.number) ?? .text(value)
        }

        static func < (lhs: Identifier, rhs: Identifier) -> Bool {
            switch (lhs, rhs) {
            case (.number(let left), .number(let right)): left < right
            case (.number, .text): true
            case (.text, .number): false
            case (.text(let left), .text(let right)): left < right
            }
        }
    }
}
