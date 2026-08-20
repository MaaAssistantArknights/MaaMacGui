//
//  MAALog.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation
import SwiftUI

struct MAALog: Identifiable, Hashable {
    enum LogColor: Hashable {
        // MARK: 基础语义色

        case trace
        case info
        case rare
        case warning
        case error
        case success
        case message
        case download

        /// 稀有干员 / 5★ 以上 / 肉鸽通关等高价值信息
        case rareOperator

        // MARK: 公招星级

        case star(Int, potentialFull: Bool)

        // MARK: 集成战略（I.S.）节点色

        case successIS
        case safehouseIS
        case traderIS
        case eventIS
        case truthIS
        case combatIS
        case emergencyIS
        case bossIS
        case explorationAbandonedIS

        // MARK: 岁园奇景（JieGarden）节点色

        case omissionsIS
        case legendIS
        case oldShopIS
        case schemeIS
        case playtimeIS
        case doubtsIS
    }

    /// 日志字体粗细（对齐 Windows 的 Regular / Bold）
    enum LogWeight: Hashable {
        case regular
        case bold

        var fontWeight: Font.Weight {
            switch self {
            case .regular:
                return .regular
            case .bold:
                return .bold
            }
        }
    }

    let id = UUID()

    let date: Date
    let content: String
    let color: LogColor
    var weight: LogWeight? = nil
    var toolTip: String? = nil
    var showTime: Bool = true
}

/// 日志卡片（详细模式下的分组单元，对应 Windows LogCardItemViewModel）
struct LogCardItem: Identifiable {
    let id = UUID()

    var items: [MAALog] = []
    /// 是否仅作为分隔标题展示（hc:Divider）
    var isDivider: Bool = false
    var header: String?
    /// 关卡截图缩略图
    var thumbnail: NSImage?

    var startTime: Date? { items.first?.date }
    var endTime: Date? { items.last?.date }
}

extension LogCardItem: Equatable {
    /// 手动实现 Equatable：thumbnail（NSImage）不可比较，id 每次新建恒不同。
    /// 相等性只看卡片内容是否变化，用于 onChange/动画判断。
    static func == (lhs: LogCardItem, rhs: LogCardItem) -> Bool {
        lhs.items == rhs.items && lhs.isDivider == rhs.isDivider && lhs.header == rhs.header
    }
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

// MARK: - 动态颜色（浅色 / 深色外观）

extension Color {
    /// 用浅色 / 深色两套十六进制颜色创建随系统外观自适应的颜色。
    init(light: UInt, dark: UInt) {
        self.init(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    /// 支持 24 位（RRGGBB）与 32 位（AARRGGBB）两种写法。
    convenience init(hex: UInt) {
        let alpha: CGFloat
        let rgb: UInt
        if hex > 0xFFFFFF {
            alpha = CGFloat((hex >> 24) & 0xFF) / 255.0
            rgb = hex & 0xFFFFFF
        } else {
            alpha = 1.0
            rgb = hex
        }
        self.init(
            calibratedRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha)
    }
}

extension Color {
    init(hex: UInt) {
        self.init(NSColor(hex: hex))
    }
}

extension MAALog.LogColor {
    /// 颜色值对齐 Windows 版 `Dark.xaml` / `Light.xaml` 的日志刷子。
    var textColor: Color {
        switch self {
        case .trace:
            return Color(light: 0x6E6E6E, dark: 0xA9A9A9)
        case .info:
            return Color(light: 0x008080, dark: 0x00C8C8)
        case .rare, .rareOperator:
            return Color(light: 0xD2691E, dark: 0xFFA500)
        case .warning:
            return Color(light: 0xB8860B, dark: 0xDAA520)
        case .error:
            return .red
        case .success:
            return Color(light: 0x228B22, dark: 0x90EE90)
        case .message:
            return Color(light: 0x404040, dark: 0xE6E6E6)
        case .download:
            return Color(light: 0x8B008B, dark: 0xEE82EE)
        case .star(let level, let potentialFull):
            let base = Self.starColor(level)
            return potentialFull ? base.opacity(0.4) : base
        // 集成战略：浅色用原始亮色，深色用日志柔和色
        case .successIS:
            return Color(light: 0x32CD32, dark: 0x91B091)
        case .safehouseIS:
            return Color(light: 0x1E90FF, dark: 0x8DA4BA)
        case .traderIS:
            return Color(light: 0x3CB371, dark: 0x93AB9E)
        case .eventIS:
            return Color(light: 0x87CEFA, dark: 0xA2B0B9)
        case .truthIS:
            return Color(light: 0x8D701C, dark: 0xA39E8D)
        case .combatIS:
            return Color(light: 0xFF8C00, dark: 0xBAA387)
        case .emergencyIS:
            return Color(light: 0xC71585, dark: 0xAF8BA2)
        case .bossIS:
            return Color(light: 0xB22222, dark: 0xAB8E8E)
        case .explorationAbandonedIS:
            return Color(light: 0x708090, dark: 0x9EA1A4)
        // 岁园奇景：浅色用原始亮色，深色用日志柔和色
        case .omissionsIS:
            return Color(light: 0x98D8C8, dark: 0x9AB8B0)
        case .legendIS:
            return Color(light: 0x00CED1, dark: 0x8DB5B6)
        case .oldShopIS:
            return Color(light: 0xFFB347, dark: 0xBAAA91)
        case .schemeIS:
            return Color(light: 0x9370DB, dark: 0xA79BB5)
        case .playtimeIS:
            return Color(light: 0xFFB6C1, dark: 0xBAABB0)
        case .doubtsIS:
            return Color(light: 0xF0E68C, dark: 0xB5B09A)
        }
    }

    /// 公招星级色（对齐 Windows Star1-6OperatorLogBrush）
    private static func starColor(_ level: Int) -> Color {
        switch level {
        case 1:
            return Color(light: 0x808080, dark: 0xE6E6E6)
        case 2:
            return Color(light: 0x4F8A10, dark: 0x88BB44)
        case 3:
            return Color(light: 0x1E90FF, dark: 0x66CCFF)
        case 4:
            return Color(light: 0x8A2BE2, dark: 0xBB88FF)
        case 5:
            return Color(light: 0xDAA520, dark: 0xEED694)
        case 6:
            return Color(light: 0xFF8C00, dark: 0xFFA500)
        default:
            return .primary
        }
    }
}

// MARK: - Log 写入与卡片维护

/// 日志卡片拆分模式（对齐 Windows `TaskQueueViewModel.LogCardSplitMode`）
enum LogCardSplitMode {
    case none
    case before
    case after
    case both
}

extension MAAViewModel {
    /// 通用写日志入口，对齐 Windows `AddLog` 的 color/weight/toolTip/splitMode/updateCardImage。
    func log(
        _ key: String.LocalizationValue,
        color: MAALog.LogColor,
        weight: MAALog.LogWeight? = nil,
        toolTip: String? = nil,
        splitMode: LogCardSplitMode = .none,
        updateCardImage: Bool = false,
        comment: StaticString? = nil
    ) {
        writeLog(
            String(localized: key, comment: comment),
            color: color,
            weight: weight,
            toolTip: toolTip,
            splitMode: splitMode,
            updateCardImage: updateCardImage)
    }

    /// 写日志并同步维护卡片列表（对齐 Windows `AddLog` 的卡片逻辑）。
    func writeLog(
        _ content: String,
        color: MAALog.LogColor,
        weight: MAALog.LogWeight? = nil,
        toolTip: String? = nil,
        showTime: Bool = true,
        splitMode: LogCardSplitMode = .none,
        updateCardImage: Bool = false
    ) {
        let entry = MAALog(
            date: Date(),
            content: content,
            color: color,
            weight: weight,
            toolTip: toolTip,
            showTime: showTime)
        logs.append(entry)
        fileLogger.write(entry)

        let needsBeforeSplit = splitMode == .before || splitMode == .both
        let needsAfterSplit = splitMode == .after || splitMode == .both

        if needsBeforeSplit {
            createNewCard()
        }
        if logCards.isEmpty {
            createNewCard()
        }
        if !logCards.isEmpty {
            let lastIndex = logCards.count - 1
            logCards[lastIndex].items.append(entry)
            if updateCardImage {
                attachThumbnail(toCardAt: lastIndex)
            }
        }
        if needsAfterSplit {
            createNewCard()
        }
    }

    /// 创建新卡片；若当前最后一张为空普通卡片则复用（对齐 Windows `createNewCard`）。
    func createNewCard() {
        if let last = logCards.last, last.items.isEmpty, !last.isDivider {
            return
        }
        logCards.append(LogCardItem())
    }

    /// 为卡片异步附加截图缩略图（对齐 Windows `AttachThumbnailToCardAsync`）。
    func attachThumbnail(toCardAt index: Int) {
        guard logCards.indices.contains(index) else { return }
        Task { @MainActor in
            guard logCards.indices.contains(index) else { return }
            if let image = try? await screenshot() {
                logCards[index].thumbnail = image
            }
        }
    }
}
