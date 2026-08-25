//
//  PRTSPlusSearch.swift
//  MAA
//

import Foundation

struct PRTSPlusSearchResult: Identifiable, Hashable, Sendable {
    let id: Int
    let stageName: String
    let title: String
    let details: String?
    let uploader: String
    let views: Int
    let likes: Int
    let hotScore: Double
    let minimumRequired: String?
    let difficulty: Int?
    let operators: [OperatorRequirement]
    let groups: [OperatorGroup]

    var operatorCount: Int {
        operators.count + groups.count
    }

    func containsOperator(_ query: String) -> Bool {
        operators.contains { $0.name.localizedCaseInsensitiveContains(query) }
            || groups.contains { group in
                group.name.localizedCaseInsensitiveContains(query)
                    || group.operators.contains { $0.name.localizedCaseInsensitiveContains(query) }
            }
    }

    func match(ownedOperators: [MAAOperBox.OwnedOper]?) -> RosterMatch {
        guard let ownedOperators else {
            return .unknown
        }

        let ownedByName = Dictionary(ownedOperators.map { ($0.name, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        var missingSlots = [String]()
        var groupSelections = [String: String]()

        for requirement in operators {
            guard let owned = ownedByName[requirement.name], requirement.meets(owned) else {
                missingSlots.append(requirement.name)
                continue
            }
        }

        for group in groups {
            let matched = group.operators
                .compactMap { requirement -> (OperatorRequirement, MAAOperBox.OwnedOper)? in
                    guard let owned = ownedByName[requirement.name], requirement.meets(owned) else {
                        return nil
                    }
                    return (requirement, owned)
                }
                .sorted { $0.1 < $1.1 }
                .first?.0
            if let matched {
                groupSelections[group.name] = matched.name
            } else {
                missingSlots.append(group.name)
            }
        }

        return RosterMatch(
            state: missingSlots.isEmpty ? .matched : .missing,
            missingSlots: missingSlots,
            groupSelections: groupSelections
        )
    }

    struct OperatorRequirement: CustomStringConvertible, Hashable, Sendable {
        let name: String
        let skill: Int?
        let elite: Int?
        let level: Int?
        let skillLevel: Int?
        let module: Int?
        let moduleLevel: Int?
        let potential: Int?

        var summary: String {
            var parts = [String]()
            if let skill {
                parts.append("S\(skill)")
            }
            if let elite, elite > 0 {
                parts.append("精\(elite)")
            }
            if let level, level > 1 {
                parts.append("Lv.\(level)")
            }
            if let skillLevel {
                if skillLevel > 7 {
                    parts.append("专\(skillLevel - 7)")
                } else if skillLevel > 1 {
                    parts.append("技能\(skillLevel)")
                }
            }
            if let module, module > 0 {
                if let moduleLevel, moduleLevel > 0 {
                    parts.append("模组\(module) Lv.\(moduleLevel)")
                } else {
                    parts.append("模组\(module)")
                }
            }
            if let potential, potential > 1 {
                parts.append("潜能\(potential)")
            }
            return parts.joined(separator: " ")
        }

        var description: String {
            summary.isEmpty ? name : "\(name) \(summary)"
        }

        fileprivate func meets(_ owned: MAAOperBox.OwnedOper) -> Bool {
            if let elite, owned.elite < elite {
                return false
            }
            if let level, let elite {
                if owned.elite == elite && owned.level < level {
                    return false
                }
            } else if let level, owned.level < level {
                return false
            }
            if let potential, owned.potential < potential {
                return false
            }
            return true
        }
    }

    struct OperatorGroup: Hashable, Sendable {
        let name: String
        let operators: [OperatorRequirement]
    }

    struct RosterMatch {
        enum State: Int {
            case matched
            case unknown
            case missing
        }

        let state: State
        let missingSlots: [String]
        let groupSelections: [String: String]

        static let unknown = RosterMatch(state: .unknown, missingSlots: [], groupSelections: [:])
    }
}

enum PRTSPlusSearchClient {
    private static let endpoint = URL(string: "https://prts.maa.plus/copilot/query")!
    private static let pageSize = 50

    enum Error: LocalizedError {
        case emptyStage
        case httpStatus(Int)
        case invalidResponse
        case server(String)
        case incompatibleList

        var errorDescription: String? {
            switch self {
            case .emptyStage:
                String(localized: "请输入关卡代号")
            case .httpStatus(let status):
                String(localized: "PRTS.plus 请求失败（HTTP \(status)）")
            case .invalidResponse:
                String(localized: "PRTS.plus 返回了无法识别的数据")
            case .server(let message):
                message
            case .incompatibleList:
                String(localized: "当前作业与已激活的作业列表类型不一致")
            }
        }
    }

    static func search(stage input: String) async throws -> [PRTSPlusSearchResult] {
        let stage = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stage.isEmpty else {
            throw Error.emptyStage
        }

        let stageNames = resolveStageNames(stage)
        var summaries = [Summary]()
        var seenIDs = Set<Int>()

        for stageName in stageNames {
            var page = 1
            var fetchedCount = 0
            while true {
                let response = try await query(stageName: stageName, page: page)
                fetchedCount += response.data.count
                for summary in response.data where seenIDs.insert(summary.id).inserted {
                    summaries.append(summary)
                }
                guard response.has_next, !response.data.isEmpty, fetchedCount < response.total else { break }
                page += 1
            }
        }

        let normalizedStageNames = Set(stageNames.map { $0.lowercased() })
        return summaries.compactMap { summary in
            guard summary.available,
                summary.type == "PRTS",
                let content = try? JSONDecoder().decode(Content.self, from: Data(summary.content.utf8))
            else {
                return nil
            }

            let title = content.doc?.title ?? content.stage_name
            let matchesStageName = normalizedStageNames.contains(content.stage_name.lowercased())
            let matchesVisibleCode =
                title.caseInsensitiveCompare(stage) == .orderedSame
                || title.lowercased().hasPrefix(stage.lowercased() + " ")
            guard matchesStageName || matchesVisibleCode else { return nil }

            return PRTSPlusSearchResult(
                id: summary.id,
                stageName: content.stage_name,
                title: title,
                details: content.doc?.details,
                uploader: summary.uploader,
                views: summary.views,
                likes: summary.like,
                hotScore: summary.hot_score ?? 0,
                minimumRequired: content.minimum_required,
                difficulty: content.difficulty,
                operators: (content.opers ?? []).map(\.searchRequirement),
                groups: (content.groups ?? []).map { group in
                    PRTSPlusSearchResult.OperatorGroup(
                        name: group.name,
                        operators: group.opers.map(\.searchRequirement)
                    )
                }
            )
        }
        .sorted(by: defaultSort)
    }

    private static func defaultSort(_ lhs: PRTSPlusSearchResult, _ rhs: PRTSPlusSearchResult) -> Bool {
        if lhs.hotScore != rhs.hotScore {
            return lhs.hotScore > rhs.hotScore
        }
        if lhs.likes != rhs.likes {
            return lhs.likes > rhs.likes
        }
        return lhs.id > rhs.id
    }

    private static func query(stageName: String, page: Int) async throws -> QueryData {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "level_keyword", value: stageName),
            URLQueryItem(name: "order_by", value: "hot_score"),
            URLQueryItem(name: "desc", value: "true"),
            URLQueryItem(name: "type", value: "PRTS"),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw Error.httpStatus(response.statusCode)
        }

        let payload: QueryResponse
        do {
            payload = try JSONDecoder().decode(QueryResponse.self, from: data)
        } catch {
            throw Error.invalidResponse
        }
        guard payload.status_code == 200, let queryData = payload.data else {
            throw Error.server(payload.message ?? String(localized: "搜索作业失败"))
        }
        return queryData
    }

    private static func resolveStageNames(_ input: String) -> [String] {
        struct Stage: Decodable {
            let code: String
            let stageId: String
        }

        guard
            let url = Bundle.main.resourceURL?
                .appending(path: "resource/stages.json"),
            let data = try? Data(contentsOf: url),
            let stages = try? JSONDecoder().decode([Stage].self, from: data)
        else {
            return [input]
        }

        let matches = stages.compactMap { stage -> String? in
            if stage.code.caseInsensitiveCompare(input) == .orderedSame
                || stage.stageId.caseInsensitiveCompare(input) == .orderedSame
            {
                return stage.stageId
            }
            return nil
        }
        return matches.isEmpty ? [input] : Array(Set(matches)).sorted()
    }
}

extension PRTSPlusSearchClient {
    fileprivate struct QueryResponse: Decodable {
        let status_code: Int?
        let message: String?
        let data: QueryData?
    }

    fileprivate struct QueryData: Decodable {
        let data: [Summary]
        let has_next: Bool
        let total: Int
    }

    fileprivate struct Summary: Decodable {
        let id: Int
        let type: String
        let uploader: String
        let views: Int
        let hot_score: Double?
        let available: Bool
        let content: String
        let like: Int
    }

    fileprivate struct Content: Decodable {
        let stage_name: String
        let doc: Documentation?
        let opers: [Operator]?
        let groups: [Group]?
        let minimum_required: String?
        let difficulty: Int?

        struct Documentation: Decodable {
            let title: String?
            let details: String?
        }

        struct Operator: Decodable {
            let name: String
            let skill: Int?
            let requirements: Requirements?

            struct Requirements: Decodable {
                let elite: Int?
                let level: Int?
                let skill_level: Int?
                let module: Int?
                let module_level: Int?
                let potential: Int?
            }

            var searchRequirement: PRTSPlusSearchResult.OperatorRequirement {
                PRTSPlusSearchResult.OperatorRequirement(
                    name: name,
                    skill: skill,
                    elite: requirements?.elite,
                    level: requirements?.level,
                    skillLevel: requirements?.skill_level,
                    module: requirements?.module,
                    moduleLevel: requirements?.module_level,
                    potential: requirements?.potential
                )
            }
        }

        struct Group: Decodable {
            let name: String
            let opers: [Operator]
        }
    }
}
