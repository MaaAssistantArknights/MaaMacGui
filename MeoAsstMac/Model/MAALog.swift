//
//  MAALog.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation
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

extension Date {
    private func maaLogFormatted(dateFormat: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = dateFormat
        return formatter.string(from: self)
    }

    var maaGuiLogFormat: String {
        maaLogFormatted(dateFormat: "MM-dd HH:mm:ss")
    }

    var maaFileLogFormat: String {
        maaLogFormatted(dateFormat: "yyyy-MM-dd HH:mm:ss")
    }
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
