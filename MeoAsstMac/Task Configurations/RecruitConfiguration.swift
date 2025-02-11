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
            return NSLocalizedString("加急", comment: "")
        } else {
            return NSLocalizedString("不加急", comment: "")
        }
    }

    var summary: String {
        let levelString = confirm.map(String.init).joined(separator: ",")
        return "★\(levelString)"
    }

    var projectedTask: MAATask {
        .recruit(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }

    static var recognition: RecruitConfiguration {
        .init(
            refresh: false, select: [4, 5, 6], confirm: [], first_tags: [],
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
        self.first_tags = try container.decodeIfPresent([String].self, forKey: .first_tags) ?? []
        self.extra_tags_mode = try container.decodeIfPresent(Int.self, forKey: .extra_tags_mode) ?? 0
        self.times = try container.decodeIfPresent(Int.self, forKey: .times) ?? 4
        self.set_time = try container.decodeIfPresent(Bool.self, forKey: .set_time) ?? true
        self.expedite = try container.decodeIfPresent(Bool.self, forKey: .expedite) ?? false
        self.expedite_times = try container.decodeIfPresent(Int.self, forKey: .expedite_times) ?? 999
        self.skip_robot = try container.decodeIfPresent(Bool.self, forKey: .skip_robot) ?? true
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
