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
        validThemes.isEmpty ? "" : validThemes.joined(separator: " ")
    }

    var summary: String { "" }

    var projectedTask: MAATask {
        .switchTheme(self)
    }

    /// 去除空白项后的主题列表（对齐 WPF：同步配置时逐项 trim 并过滤空项）
    private var validThemes: [String] {
        themes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    @JSON.Builder var params: JSON {
        "themes" => validThemes
    }
}

extension SwitchThemeConfiguration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.themes = try container.decodeIfPresent([String].self, forKey: .themes) ?? []
    }
}
