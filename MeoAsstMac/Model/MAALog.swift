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

extension Date {
    private static let guiLogDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    private static let fileLogDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var maaGuiLogFormat: String {
        Self.guiLogDateFormatter.string(from: self)
    }

    var maaFileLogFormat: String {
        Self.fileLogDateFormatter.string(from: self)
    }
}
