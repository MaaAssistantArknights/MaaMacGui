import Foundation

enum PlayCoverDiagnosticStatus: String, Sendable {
    case passed, error, warning, unavailable

    var title: String {
        switch self {
        case .passed: String(localized: "通过")
        case .error: String(localized: "错误")
        case .warning: String(localized: "警告")
        case .unavailable: String(localized: "无法检测")
        }
    }
    var symbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle"
        }
    }
}

enum PlayCoverDiagnosticGroup: Int, CaseIterable, Identifiable, Sendable {
    case distribution, game, graphics, maa, runtime
    var id: Self { self }
    var title: String {
        switch self {
        case .distribution: String(localized: "PlayCover 版本")
        case .game: String(localized: "游戏设置")
        case .graphics: String(localized: "图像设置")
        case .maa: String(localized: "MAA 设置")
        case .runtime: String(localized: "运行链路")
        }
    }
}

struct PlayCoverDiagnosticItem: Identifiable, Sendable {
    let id: String
    let group: PlayCoverDiagnosticGroup
    let title: String
    let status: PlayCoverDiagnosticStatus
    let value: String
    let reason: String
    let remedy: String
    var blockedBy: [String] = []
}

struct PlayCoverDiagnosticSnapshot: Equatable, Sendable {
    let address: String
    let touchMode: String
    let screenshotMode: String
    let clientName: String
    let bundleID: String
    let guiVersion: String
    let coreVersion: String
}

struct PlayCoverDiagnosticReport: Sendable {
    let date: Date
    let snapshot: PlayCoverDiagnosticSnapshot
    var items: [PlayCoverDiagnosticItem]

    func text(homePath: String) -> String {
        var lines = [
            String(localized: "PlayCover 环境检测 · \(date.formatted())"),
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "MAA GUI: \(snapshot.guiVersion) · Core: \(snapshot.coreVersion)",
            String(localized: "客户端: \(snapshot.clientName) (\(snapshot.bundleID))"),
            "MAA: \(snapshot.touchMode) · \(snapshot.screenshotMode) · \(snapshot.address)",
        ]
        for group in PlayCoverDiagnosticGroup.allCases {
            lines.append("\n\(group.title)")
            for item in items where item.group == group {
                lines.append("[\(item.status.title)] \(item.title): \(item.value)")
                lines.append(item.reason)
                if !item.remedy.isEmpty { lines.append(String(localized: "处理: \(item.remedy)")) }
            }
        }
        return lines.joined(separator: "\n").replacingOccurrences(of: homePath, with: "~")
    }
}

struct PlayCoverStaticResult: Sendable {
    var items: [PlayCoverDiagnosticItem]
    var gameURL: URL?
    var port: Int?

    /// These are real service prerequisites. Version markers, recommended
    /// switches, graphics presets and MAA touch mode are independent findings.
    var runtimeBlockers: [PlayCoverDiagnosticItem] {
        let required = [
            ("data-location", String(localized: "数据目录")), ("game-install", String(localized: "游戏安装")),
            ("game-settings", String(localized: "游戏配置文件")), ("injected-tools", String(localized: "PlayTools 加载项")),
            ("maatools", "MaaTools"), ("game-port", String(localized: "MaaTools 端口")),
        ]
        return required.map { id, title in
            items.first { $0.id == id }
                ?? PlayCoverStaticChecks.item(
                    id, .game, title,
                    .unavailable, String(localized: "未完成"), String(localized: "缺少前置检查结果，不能判断服务可用。"),
                    String(localized: "重新检测。"))
        }.filter { $0.status != .passed }
    }
}
