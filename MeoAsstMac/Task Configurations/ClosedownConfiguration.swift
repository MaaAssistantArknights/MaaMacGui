//
//  ClosedownConfiguration.swift
//  MAA
//
//  Created by hguandl on 2024/7/22.
//

import Foundation

struct ClosedownConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .CloseDown }

    var client_type: MAAClientChannel

    var title: String {
        type.description
    }

    var subtitle: String {
        String(localized: "关闭当前客户端")
    }

    var summary: String {
        ""
    }

    var projectedTask: MAATask {
        .closedown(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }
}

extension ClosedownConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.client_type = try container.decodeIfPresent(MAAClientChannel.self, forKey: .client_type) ?? .Official
    }
}
