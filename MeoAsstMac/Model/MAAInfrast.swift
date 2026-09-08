//
//  MAAInfrast.swift
//  MAA
//
//  Created by hguandl on 20/4/2023.
//

import Foundation

struct MAAInfrast: Codable, Hashable, Sendable {
    let title: String?
    let description: String?
    let plans: [Plan]

    static let empty = MAAInfrast(title: nil, description: nil, plans: [])

    struct Plan: Codable, Hashable, Sendable {
        let name: String?
        let description: String?
        let description_post: String?
        let period: [Period]?
    }

    struct Period: Codable, Hashable, Sendable {
        let start: Double
        let end: Double
        private let times: [String]

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let times = try container.decode([String].self)
            guard times.count == 2,
                let start = Self.seconds(times[0]), let end = Self.seconds(times[1])
            else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "period must contain two valid times (HH:mm)")
            }
            self.times = times
            self.start = start
            self.end = end
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(times)
        }

        private static func seconds(_ time: String) -> Double? {
            let parts = time.trimmingCharacters(in: .whitespaces).split(
                separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count),
                let hour = Int(parts[0]), (0..<24).contains(hour),
                let minute = Int(parts[1]), (0..<60).contains(minute),
                parts[0].allSatisfy({ $0.isASCII && $0.isNumber }),
                parts[1].allSatisfy({ $0.isASCII && $0.isNumber })
            else { return nil }
            let second = parts.count == 3 ? Double(parts[2]) : 0
            guard let second, second >= 0, second < 60 else { return nil }
            return Double(hour * 3600 + minute * 60) + second
        }
    }
}

extension MAAInfrast {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        plans = container.contains(.plans) ? try container.decode([Plan].self, forKey: .plans) : []
    }

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        self = try JSONDecoder().decode(MAAInfrast.self, from: data)
    }

    var hasPeriods: Bool { plans.contains { !($0.period ?? []).isEmpty } }
    var hasMixedPeriods: Bool { hasPeriods && plans.contains { ($0.period ?? []).isEmpty } }
    var defaultSelection: Int { hasPeriods ? -1 : 0 }

    // Windows retains valid selections; a missing list item becomes time rotation,
    // even when the refreshed list contains no time-rotation item.
    func refreshedSelection(_ selection: Int) -> Int {
        plans.indices.contains(selection) || (selection == -1 && hasPeriods) ? selection : -1
    }

    struct Selection: Equatable, Sendable {
        let index: Int
        let usedFallback: Bool
    }

    enum SelectionError: LocalizedError {
        case outOfRange

        var errorDescription: String? { String(localized: "自定义基建配置选择超出索引") }
    }

    func select(_ selection: Int, at date: Date = .now, calendar: Calendar = .current) throws -> Selection {
        if selection != -1 {
            guard plans.indices.contains(selection) else { throw SelectionError.outOfRange }
            return Selection(index: selection, usedFallback: false)
        }
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let now =
            Double((time.hour ?? 0) * 3600 + (time.minute ?? 0) * 60 + (time.second ?? 0))
            + Double(time.nanosecond ?? 0) / 1_000_000_000
        let index = plans.firstIndex { plan in
            (plan.period ?? []).contains { $0.start <= now && now <= $0.end }
        }
        return Selection(index: index ?? 0, usedFallback: index == nil)
    }

    func nextSelection(after selection: Int) -> Int? {
        guard plans.indices.contains(selection) else { return nil }
        return (selection + 1) % plans.count
    }

    func name(at index: Int) -> String {
        guard plans.indices.contains(index) else { return "???" }
        return plans[index].name ?? "\(index)"
    }
}
