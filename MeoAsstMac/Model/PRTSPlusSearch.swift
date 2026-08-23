//
//  PRTSPlusSearch.swift
//  MAA
//

import Foundation

struct PRTSPlusSearchResult: Identifiable, Hashable {
    let id: Int
    let stageName: String
    let title: String
    let details: String?
    let uploader: String
    let views: Int
    let likes: Int
    let hotScore: Double
    let operatorCount: Int
}

enum PRTSPlusSearchError: LocalizedError {
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

enum PRTSPlusSearchClient {
    private static let endpoint = URL(string: "https://prts.maa.plus/copilot/query")!
    private static let pageSize = 50

    static func search(stage input: String) async throws -> [PRTSPlusSearchResult] {
        let stage = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stage.isEmpty else {
            throw PRTSPlusSearchError.emptyStage
        }

        let stageNames = resolveStageNames(stage)
        var summaries = [Summary]()
        var seenIDs = Set<Int>()

        for stageName in stageNames {
            let response = try await query(stageName: stageName)
            for summary in response where seenIDs.insert(summary.id).inserted {
                summaries.append(summary)
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

            let title = content.doc?.title ?? content.stageName
            let matchesStageName = normalizedStageNames.contains(content.stageName.lowercased())
            let matchesVisibleCode =
                title.caseInsensitiveCompare(stage) == .orderedSame
                || title.lowercased().hasPrefix(stage.lowercased() + " ")
            guard matchesStageName || matchesVisibleCode else { return nil }

            return PRTSPlusSearchResult(
                id: summary.id,
                stageName: content.stageName,
                title: title,
                details: content.doc?.details,
                uploader: summary.uploader,
                views: summary.views,
                likes: summary.likes,
                hotScore: summary.hotScore ?? 0,
                operatorCount: (content.opers?.count ?? 0) + (content.groups?.count ?? 0)
            )
        }
        .sorted {
            if $0.hotScore != $1.hotScore {
                return $0.hotScore > $1.hotScore
            }
            if $0.likes != $1.likes {
                return $0.likes > $1.likes
            }
            return $0.id > $1.id
        }
    }

    private static func query(stageName: String) async throws -> [Summary] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
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
            throw PRTSPlusSearchError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw PRTSPlusSearchError.httpStatus(response.statusCode)
        }

        let payload: QueryResponse
        do {
            payload = try JSONDecoder().decode(QueryResponse.self, from: data)
        } catch {
            throw PRTSPlusSearchError.invalidResponse
        }
        guard payload.statusCode == 200, let queryData = payload.data else {
            throw PRTSPlusSearchError.server(payload.message ?? String(localized: "搜索作业失败"))
        }
        return queryData.data
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
        let statusCode: Int?
        let message: String?
        let data: QueryData?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case message
            case data
        }
    }

    fileprivate struct QueryData: Decodable {
        let data: [Summary]
    }

    fileprivate struct Summary: Decodable {
        let id: Int
        let type: String
        let uploader: String
        let views: Int
        let hotScore: Double?
        let available: Bool
        let content: String
        let likes: Int

        enum CodingKeys: String, CodingKey {
            case id
            case type
            case uploader
            case views
            case hotScore = "hot_score"
            case available
            case content
            case likes = "like"
        }
    }

    fileprivate struct Content: Decodable {
        let stageName: String
        let doc: Documentation?
        let opers: [Operator]?
        let groups: [Group]?

        enum CodingKeys: String, CodingKey {
            case stageName = "stage_name"
            case doc
            case opers
            case groups
        }

        struct Documentation: Decodable {
            let title: String?
            let details: String?
        }

        struct Operator: Decodable {}
        struct Group: Decodable {}
    }
}
