//
//  RecruitConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct RecruitConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .Recruit }

    var refresh: Bool
    var select: [Int]
    var confirm: [Int]
    var first_tags: [String]
    var first_tags_enabled: Bool
    var preserve_tags: [String]
    var preserve_tags_enabled: Bool
    var extra_tags_mode: Int
    var times: Int
    var set_time: Bool
    var expedite: Bool
    var expedite_times: Int
    var skip_robot: Bool
    var recruitment_time: [String: Int]
    var report_to_penguin: Bool
    var penguin_id: String
    var report_to_yituliu: Bool
    var yituliu_id: String
    var server: String

    var title: String {
        type.description
    }

    var subtitle: String {
        if expedite {
            return String(localized: "加急")
        } else {
            return String(localized: "不加急")
        }
    }

    var summary: String {
        let levelString = confirm.map(String.init).joined(separator: ",")
        return "★\(levelString)"
    }

    var projectedTask: MAATask {
        .recruit(self)
    }

    struct Params: Encodable {
        var refresh: Bool
        var select: [Int]
        var confirm: [Int]
        var first_tags: [String]
        var preserve_tags: [String]
        var extra_tags_mode: Int
        var times: Int
        var set_time: Bool
        var expedite: Bool
        var expedite_times: Int
        var recruitment_time: [String: Int]
        var report_to_penguin: Bool
        var penguin_id: String
        var report_to_yituliu: Bool
        var yituliu_id: String
        var server: String
    }

    var params: Params { params(tagNames: [:]) }

    // Core matches first_tags against the active game's displayed tag names,
    // whereas preserve_tags takes canonical IDs. Persisted selections stay IDs.
    func params(tagNames: [String: String]) -> Params {
        .init(
            refresh: refresh, select: select, confirm: confirm,
            first_tags: first_tags_enabled ? Self.normalizedTags(first_tags).map { tagNames[$0] ?? $0 } : [],
            preserve_tags: preserve_tags_enabled ? Self.normalizedTags(preserve_tags) : [],
            extra_tags_mode: extra_tags_mode, times: times, set_time: set_time,
            expedite: expedite, expedite_times: expedite_times,
            recruitment_time: recruitment_time, report_to_penguin: report_to_penguin,
            penguin_id: penguin_id, report_to_yituliu: report_to_yituliu,
            yituliu_id: yituliu_id, server: server)
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { value in
            let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !tag.isEmpty && seen.insert(tag).inserted ? tag : nil
        }
    }

    static var recognition: RecruitConfiguration {
        .init(
            refresh: false, select: [4, 5, 6], confirm: [-1], first_tags: [],
            first_tags_enabled: false, preserve_tags: ["支援机械"], preserve_tags_enabled: true,
            extra_tags_mode: 0, times: 0, set_time: true, expedite: false,
            expedite_times: 0, skip_robot: true,
            recruitment_time: [
                "3": 540, "4": 540, "5": 540, "6": 540,
            ],
            report_to_penguin: false, penguin_id: "", report_to_yituliu: false,
            yituliu_id: "", server: "")
    }
}

extension RecruitConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.refresh = try container.decodeIfPresent(Bool.self, forKey: .refresh) ?? false
        self.select = try container.decodeIfPresent([Int].self, forKey: .select) ?? [4, 5]
        self.confirm = try container.decodeIfPresent([Int].self, forKey: .confirm) ?? [3, 4, 5]
        self.first_tags = Self.normalizedTags(try container.decodeIfPresent([String].self, forKey: .first_tags) ?? [])
        self.first_tags_enabled =
            try container.decodeIfPresent(Bool.self, forKey: .first_tags_enabled) ?? !first_tags.isEmpty
        self.extra_tags_mode = try container.decodeIfPresent(Int.self, forKey: .extra_tags_mode) ?? 0
        self.times = try container.decodeIfPresent(Int.self, forKey: .times) ?? 4
        self.set_time = try container.decodeIfPresent(Bool.self, forKey: .set_time) ?? true
        self.expedite = try container.decodeIfPresent(Bool.self, forKey: .expedite) ?? false
        self.expedite_times = try container.decodeIfPresent(Int.self, forKey: .expedite_times) ?? 999
        self.skip_robot = try container.decodeIfPresent(Bool.self, forKey: .skip_robot) ?? true
        if let tags = try container.decodeIfPresent([String].self, forKey: .preserve_tags) {
            self.preserve_tags = Self.normalizedTags(tags)
        } else {
            self.preserve_tags = skip_robot ? ["支援机械"] : []
        }
        self.preserve_tags_enabled =
            try container.decodeIfPresent(Bool.self, forKey: .preserve_tags_enabled) ?? !preserve_tags.isEmpty
        self.recruitment_time =
            try container.decodeIfPresent([String: Int].self, forKey: .recruitment_time) ?? [
                "3": 540, "4": 540, "5": 540, "6": 540,
            ]
        self.report_to_penguin = try container.decodeIfPresent(Bool.self, forKey: .report_to_penguin) ?? false
        self.penguin_id = try container.decodeIfPresent(String.self, forKey: .penguin_id) ?? ""
        self.report_to_yituliu = try container.decodeIfPresent(Bool.self, forKey: .report_to_yituliu) ?? false
        self.yituliu_id = try container.decodeIfPresent(String.self, forKey: .yituliu_id) ?? ""
        self.server = try container.decodeIfPresent(String.self, forKey: .server) ?? "CN"
    }
}

/// Canonical tag IDs and translations come from Core resources, never UI text.
struct RecruitTagCatalog: Sendable {
    let labels: [String: String]

    var tags: [String] { labels.keys.sorted() }

    func label(for tag: String) -> String { labels[tag] ?? tag }

    static func read(resourceDirectory: URL) -> Self? {
        struct Resource: Decodable { let tags: [String: String] }
        // Core loads the optional custom file after the base table, replacing it.
        for name in ["recruitment_custom.json", "recruitment.json"] {
            if let data = try? Data(contentsOf: resourceDirectory.appendingPathComponent(name)),
                let resource = try? JSONDecoder().decode(Resource.self, from: data)
            {
                return Self(labels: resource.tags)
            }
        }
        return nil
    }

    /// The tag table file Core reads first; its modification date detects
    /// in-place resource updates that keep the directory unchanged.
    static func effectiveTableFile(resourceDirectory: URL) -> URL? {
        for name in ["recruitment_custom.json", "recruitment.json"] {
            let file = resourceDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    static func load(resourceDirectory: URL?, languageCode: String) -> Self {
        guard let resourceDirectory, let canonical = read(resourceDirectory: resourceDirectory)
        else { return Self(labels: [:]) }
        let global: String?
        switch languageCode {
        case "en": global = "YoStarEN"
        case "ko": global = "YoStarKR"
        case "ja": global = "YoStarJP"
        default: global = nil
        }
        let translated =
            global.flatMap {
                read(resourceDirectory: resourceDirectory.appendingPathComponent("global/\($0)/resource"))?.labels
            } ?? [:]
        return Self(
            labels: canonical.labels.merging(
                translated.filter { canonical.labels[$0.key] != nil }, uniquingKeysWith: { _, translated in translated }
            ))
    }
}
