//
//  SwitchThemeConfiguration.swift
//  MAA
//
//  Created by zhangweijian on 10/9/2026.
//

import Foundation
import JBird

struct SwitchThemeConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .SwitchTheme }

    var themes: [String]

    var title: String {
        type.description
    }

    var subtitle: String {
        themes.isEmpty ? "" : themes.joined(separator: " ")
    }

    var summary: String { "" }

    var projectedTask: MAATask {
        .switchtheme(self)
    }

    @JSON.Builder var params: JSON {
        "themes" => themes
    }
}

extension SwitchThemeConfiguration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.themes = try container.decodeIfPresent([String].self, forKey: .themes) ?? []
    }
}
