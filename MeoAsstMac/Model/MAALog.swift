//
//  MAALog.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import SwiftUI

struct MAALog: Identifiable, Hashable {
    enum LogColor {
        case trace
        case info
        case rare
        case warning
        case error
    }

    let id = UUID()

    let date: Date
    let content: String
    let color: LogColor
}

extension MAALog.LogColor {
    var textColor: Color {
        switch self {
        case .trace:
            return .primary
        case .info:
            return Color("log.color.info")
        case .rare:
            return .orange
        case .warning:
            return .purple
        case .error:
            return .red
        }
    }
}
