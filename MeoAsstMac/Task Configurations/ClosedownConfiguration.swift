//
//  ClosedownConfiguration.swift
//  MAA
//
//  Created by hguandl on 2024/7/22.
//

import Foundation

struct ClosedownConfiguration: MAATaskConfiguration {
    var enable = true

    // Requires migration, see `init(from:)`.

    var client_type = MAAClientChannel.default

    var title: String {
        MAATask.TypeName.CloseDown.description
    }

    var subtitle: String {
        NSLocalizedString("请确保这是最后一个任务", comment: "")
    }

    var summary: String {
        ""
    }

    var projectedTask: MAATask {
        .closedown(self)
    }
}

extension ClosedownConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enable = try container.decode(Bool.self, forKey: .enable)

        // Migration

        self.client_type = (try? container.decode(MAAClientChannel.self, forKey: .client_type)) ?? .default
    }
}
