//
//  AwardConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct AwardConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .Award }

    var award: Bool
    var mail: Bool
    var recruit: Bool
    var orundum: Bool
    var mining: Bool
    var specialaccess: Bool

    var title: String {
        type.description
    }

    var subtitle: String {
        var awards = [String]()
        if award {
            awards.append(NSLocalizedString("日常任务", comment: ""))
            awards.append(NSLocalizedString("周常任务", comment: ""))
        }
        if mail {
            awards.append(NSLocalizedString("邮件", comment: ""))
        }
        if recruit {
            awards.append(NSLocalizedString("免费单抽", comment: ""))
        }
        if orundum {
            awards.append(NSLocalizedString("幸运墙", comment: ""))
        }
        if mining {
            awards.append(NSLocalizedString("限时开采许可", comment: ""))
        }
        if specialaccess {
            awards.append(NSLocalizedString("专享月卡", comment: ""))
        }
        return awards.joined(separator: " ")
    }

    var summary: String { "" }

    var projectedTask: MAATask {
        .award(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }
}

extension AwardConfiguration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.award = try container.decodeIfPresent(Bool.self, forKey: .award) ?? true
        self.mail = try container.decodeIfPresent(Bool.self, forKey: .mail) ?? false
        self.recruit = try container.decodeIfPresent(Bool.self, forKey: .recruit) ?? false
        self.orundum = try container.decodeIfPresent(Bool.self, forKey: .orundum) ?? false
        self.mining = try container.decodeIfPresent(Bool.self, forKey: .mining) ?? false
        self.specialaccess = try container.decodeIfPresent(Bool.self, forKey: .specialaccess) ?? false
    }
}
