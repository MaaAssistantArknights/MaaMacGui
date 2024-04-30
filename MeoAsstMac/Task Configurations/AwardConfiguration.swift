//
//  AwardConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct AwardConfiguration: MAATaskConfiguration {
    var enable = true
    var award = true
    var mail = true
    var recruit = false
    var orundum = false
    var specialaccess = false

    var title: String {
        MAATask.TypeName.Award.description
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
        if specialaccess {
            awards.append(NSLocalizedString("专享月卡", comment: ""))
        }
        return awards.joined(separator: " ")
    }

    var summary: String { "" }
}

extension AwardConfiguration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enable = try container.decode(Bool.self, forKey: .enable)

        // Migration
        self.award = try container.decodeIfPresent(Bool.self, forKey: .award) ?? false
        self.mail = try container.decodeIfPresent(Bool.self, forKey: .mail) ?? false
        self.recruit = try container.decodeIfPresent(Bool.self, forKey: .recruit) ?? false
        self.orundum = try container.decodeIfPresent(Bool.self, forKey: .orundum) ?? false
        self.specialaccess = try container.decodeIfPresent(Bool.self, forKey: .specialaccess) ?? false
    }
}
