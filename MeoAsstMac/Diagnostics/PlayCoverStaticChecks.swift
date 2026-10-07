import CoreGraphics
import Foundation

enum PlayCoverInspectionError: Error, LocalizedError {
    case invalidGameInfo, invalidExecutable, oversizedFile, oversizedLoadCommands, emptyFramework

    var errorDescription: String? {
        switch self {
        case .invalidGameInfo: String(localized: "游戏 Info.plist 的客户端标识或可执行文件名无效。")
        case .invalidExecutable: String(localized: "游戏可执行文件的 arm64 Mach-O 头或加载项无效。")
        case .oversizedFile: String(localized: "配置文件超过 1 MiB，未继续解析。")
        case .oversizedLoadCommands: String(localized: "Mach-O 加载项超过 1 MiB，未继续解析。")
        case .emptyFramework: String(localized: "随附 PlayTools 文件为空。")
        }
    }
}

struct PlayCoverGameSettings: Sendable {
    let maaTools: Bool?
    let maaToolsPort: Int?
    let playChain: Bool?
    let bypass: Bool?
    let resolution: Int?
    let windowWidth: Int?
    let windowHeight: Int?
    let customScaler: Double?
    let displayRotation: Int?
}

enum PlayCoverStaticChecks {
    static func plist(at url: URL) throws -> [String: Any] {
        let data = try configurationData(at: url)
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return result
    }

    private static func configurationData(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let limit = 1024 * 1024
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw PlayCoverInspectionError.oversizedFile }
        return data
    }

    static func version(info: [String: Any]) -> PlayCoverDiagnosticItem {
        let version = (info["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = version?.lowercased().contains("maa") == true
        let hasVersion = version?.isEmpty == false
        return item(
            "fork", .distribution, String(localized: "MAA 版本"),
            known ? .passed : hasVersion ? .error : .unavailable,
            hasVersion ? version! : String(localized: "未知"),
            known
                ? String(localized: "版本号包含 maa（不区分大小写），符合 MAA 版本要求。")
                : hasVersion
                    ? String(localized: "版本号不包含 maa，需要使用 MAA 版本的 PlayCover。")
                    : String(localized: "无法读取有效的 PlayCover 版本号。"),
            known ? "" : String(localized: "从 hguandl/PlayCover Releases 安装 MAA 版本后重新检测。"))
    }

    static func graphics(_ settings: PlayCoverGameSettings, invalidFields: [String: String] = [:])
        -> [PlayCoverDiagnosticItem]
    {
        let modeNames = [
            0: String(localized: "关闭"), 1: String(localized: "自动"), 2: "1080p", 3: "1440p", 4: "4K",
            5: String(localized: "自定义"), 6: String(localized: "自由缩放"), 7: String(localized: "固定画布"),
        ]
        var result = [PlayCoverDiagnosticItem]()
        let mode = settings.resolution
        result.append(
            item(
                "resolution-mode", .graphics, String(localized: "分辨率模式"),
                mode == nil
                    ? .unavailable
                    : [1, 6].contains(mode!) ? .warning : modeNames[mode!] == nil ? .unavailable : .passed,
                mode.map { "\(modeNames[$0] ?? String(localized: "未知模式")) (\($0))" } ?? String(localized: "缺少字段"),
                String(localized: "自动或自由缩放模式需要结合运行中的实际分辨率验证。"),
                String(localized: "使用分辨率指南选择适合当前显示器的设置，修改后重启游戏。")))
        if let width = settings.windowWidth, let height = settings.windowHeight {
            result.append(
                item(
                    "configured-size", .graphics, String(localized: "配置宽高"), width > 0 && height > 0 ? .passed : .error,
                    "\(width)×\(height)", String(localized: "这里只验证配置尺寸有效；运行截图另行验证比例和最低分辨率。"),
                    width > 0 && height > 0 ? "" : String(localized: "在 PlayCover 图像设置中填写有效的宽度和高度。")))
        } else {
            result.append(
                item(
                    "configured-size", .graphics, String(localized: "配置宽高"), .unavailable, String(localized: "缺少字段"),
                    String(localized: "配置文件未包含完整的宽高。"), String(localized: "打开 PlayCover 游戏图像设置核对。")))
        }
        if let scale = settings.customScaler {
            result.append(
                item(
                    "scale", .graphics, String(localized: "分辨率缩放"), scale.isFinite && scale > 0 ? .passed : .error,
                    String(scale), String(localized: "缩放必须为有限正数，不强制设为 1.0。"),
                    scale.isFinite && scale > 0 ? "" : String(localized: "在 PlayCover 图像设置中填写正数缩放值。")))
        } else {
            result.append(
                item(
                    "scale", .graphics, String(localized: "分辨率缩放"), .unavailable, String(localized: "缺少字段"),
                    String(localized: "无法读取缩放值。"), String(localized: "核对 PlayCover 图像设置。")))
        }
        let rotation = settings.displayRotation
        result.append(
            item(
                "rotation", .graphics, String(localized: "显示旋转"),
                rotation == nil
                    ? .unavailable : rotation == 0 ? .passed : (1...4).contains(rotation!) ? .warning : .error,
                rotation.map(String.init) ?? String(localized: "缺少字段"), String(localized: "非默认旋转可能影响尺寸或触控坐标，需要结合运行验证。"),
                rotation == 0 ? "" : String(localized: "检查游戏是否保持横屏；必要时恢复默认旋转并重启游戏。")))
        return applyFieldErrors(
            result,
            fields: [
                "resolution-mode": ["resolution"],
                "configured-size": ["windowWidth", "windowHeight"], "scale": ["customScaler"],
                "rotation": ["displayRotation"],
            ], errors: invalidFields)
    }

    static func maa(_ snapshot: PlayCoverDiagnosticSnapshot, port: Int?, screenPermission: Bool)
        -> [PlayCoverDiagnosticItem]
    {
        var result = [
            item(
                "touch-mode", .maa, String(localized: "触控模式"), snapshot.touchMode == "MacPlayTools" ? .passed : .error,
                snapshot.touchMode, String(localized: "PlayCover 连接需要使用 MacPlayTools。"),
                snapshot.touchMode == "MacPlayTools" ? "" : String(localized: "在 MAA 连接设置中将触控模式改为 MacPlayTools。"))
        ]
        if let endpoint = MaaToolsEndpoint(snapshot.address) {
            result.append(
                item(
                    "address-format", .maa, String(localized: "连接地址格式"), .passed, snapshot.address,
                    String(localized: "包含有效主机及 1–65535 的端口。"), ""))
            let coreCompatible = !endpoint.host.contains(":")
            result.append(
                item(
                    "address-core", .maa, String(localized: "Core 地址兼容性"), coreCompatible ? .passed : .error,
                    snapshot.address, String(localized: "当前 Core 按 host:port 解析连接地址；IPv6 与本机回环可比较，但此格式不能用于 Core 连接。"),
                    coreCompatible ? "" : String(localized: "在 MAA 中使用 localhost 或 127.0.0.1，并保持游戏配置端口。")))
            if let port {
                let match = endpoint.matchesLocalPort(port)
                result.append(
                    item(
                        "address", .maa, String(localized: "连接地址与端口匹配"), match ? .passed : .error,
                        snapshot.address,
                        String(localized: "游戏配置端口：\(port)；localhost 与本机回环地址等价。"),
                        match ? "" : String(localized: "将 MAA 连接地址改为 localhost:\(port)，并核对游戏标题栏。")))
            } else {
                result.append(
                    skipped(
                        "address", .maa, String(localized: "连接地址与端口匹配"), blockedBy: ["game-port"],
                        reason: String(localized: "游戏配置端口未通过检查，无法比较 MAA 地址与游戏端口。")))
            }
        } else {
            result.append(
                item(
                    "address-format", .maa, String(localized: "连接地址格式"), .error, snapshot.address,
                    String(localized: "地址必须包含主机及 1–65535 的端口。"),
                    String(localized: "按游戏标题栏填写，例如 localhost:1717。")))
            result.append(
                skipped(
                    "address", .maa, String(localized: "连接地址与端口匹配"), blockedBy: ["address-format"],
                    reason: String(localized: "连接地址格式无效，未比较游戏端口。")))
        }
        let supportedMode = ["RGBA", "BGR", "MacSCK"].contains(snapshot.screenshotMode)
        result.append(
            item(
                "capture-mode", .maa, String(localized: "截图模式"), supportedMode ? .passed : .error,
                snapshot.screenshotMode, String(localized: "RGBA 需要 MaaTools ≥2，BGR 与 MacSCK 需要 ≥3；运行时核对协议版本。"),
                supportedMode ? "" : String(localized: "在 MAA 连接设置中选择有效截图模式。")))
        if snapshot.screenshotMode == "MacSCK" {
            result.append(
                item(
                    "screen-permission", .maa, String(localized: "屏幕录制权限"), screenPermission ? .passed : .error,
                    screenPermission ? String(localized: "已开启") : String(localized: "未开启"),
                    String(localized: "MacSCK 截图需要 MAA 的录屏权限。"),
                    screenPermission ? "" : String(localized: "在系统设置 → 隐私与安全性 → 录屏与系统录音中允许 MAA，必要时重启 MAA。")))
        }
        return result
    }

    static func run(snapshot: PlayCoverDiagnosticSnapshot, appURL: URL, dataURL: URL, screenPermission: Bool)
        -> PlayCoverStaticResult
    {
        var result = PlayCoverStaticResult(items: [], gameURL: nil, port: nil)
        guard !Task.isCancelled else { return result }
        result.items += checkApplication(at: appURL)
        guard !Task.isCancelled else { return result }
        let directory = checkDirectory(
            dataURL, id: "data-location", group: .game, title: String(localized: "PlayCover 数据目录"),
            reason: String(localized: "数据目录可读取；游戏安装与配置文件分别检查。"))
        result.items.append(directory)
        if directory.status == .passed {
            checkGame(at: dataURL, bundleID: snapshot.bundleID, result: &result)
            guard !Task.isCancelled else { return result }
            checkSettings(at: dataURL, bundleID: snapshot.bundleID, result: &result)
        } else {
            result.items.append(
                skipped(
                    "game-install", .game, String(localized: "游戏安装"), blockedBy: ["data-location"],
                    reason: String(localized: "数据目录未通过读取检查，未读取游戏安装信息。")))
            result.items += skippedGameInfo()
            result.items.append(
                skipped(
                    "game-settings", .game, String(localized: "游戏配置文件"), blockedBy: ["data-location"],
                    reason: String(localized: "数据目录未通过读取检查，未读取游戏配置。")))
            result.items += skippedSettings()
        }
        result.items += maa(snapshot, port: result.port, screenPermission: screenPermission)
        return result
    }

    private static func checkDirectory(
        _ url: URL, id: String, group: PlayCoverDiagnosticGroup, title: String, reason: String
    ) -> PlayCoverDiagnosticItem {
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            return item(id, group, title, .passed, url.path, reason, "")
        } catch {
            return readFailure(id, group, title, error, path: url)
        }
    }

    private static func checkApplication(at appURL: URL) -> [PlayCoverDiagnosticItem] {
        let directory = checkDirectory(
            appURL, id: "playcover-location", group: .distribution, title: String(localized: "PlayCover 应用目录"),
            reason: String(localized: "应用目录可读取；发行信息与框架分别检查。"))
        guard directory.status == .passed else { return [directory] + skippedDistribution() }
        var items = [directory]
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        do {
            let info = try plist(at: infoURL)
            items.append(version(info: info))
        } catch {
            items.append(
                readFailure("fork", .distribution, String(localized: "发行信息"), error, path: infoURL))
        }
        let framework = appURL.appendingPathComponent("Contents/Frameworks/PlayTools.framework/PlayTools")
        do {
            let handle = try FileHandle(forReadingFrom: framework)
            defer { try? handle.close() }
            guard try handle.read(upToCount: 1)?.isEmpty == false else {
                throw PlayCoverInspectionError.emptyFramework
            }
            items.append(
                item(
                    "bundled-tools", .distribution, String(localized: "随附 PlayTools"), .passed,
                    String(localized: "存在"),
                    String(localized: "PlayCover.app 内的 PlayTools.framework 可读取。"), ""))
        } catch {
            items.append(
                readFailure(
                    "bundled-tools", .distribution, String(localized: "随附 PlayTools"), error, path: framework))
        }
        return items
    }

    private static func checkGame(at dataURL: URL, bundleID: String, result: inout PlayCoverStaticResult) {
        let gameURL = dataURL.appendingPathComponent("Applications/\(bundleID).app")
        let infoURL = gameURL.appendingPathComponent("Info.plist")
        do {
            let info = try plist(at: infoURL)
            guard info["CFBundleIdentifier"] as? String == bundleID,
                let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty,
                !executable.contains("/"), executable != "..", executable != "."
            else { throw PlayCoverInspectionError.invalidGameInfo }
            result.gameURL = gameURL
            result.items.append(
                item(
                    "game-install", .game, String(localized: "游戏安装"), .passed, gameURL.path,
                    String(localized: "游戏标识符合当前 MAA 客户端。"), ""))
            let executableURL = gameURL.appendingPathComponent(executable)
            do {
                let libraries = try MachOLibraries.read(at: executableURL)
                let hasTools = libraries.contains {
                    $0.contains("PlayTools.framework/") && $0.hasSuffix("/PlayTools")
                }
                result.items.append(
                    item(
                        "injected-tools", .game, String(localized: "PlayTools 加载项"), hasTools ? .passed : .error,
                        hasTools ? String(localized: "已注入") : String(localized: "缺失"),
                        String(localized: "读取游戏可执行文件的动态库加载项。"),
                        hasTools ? "" : String(localized: "在指定 PlayCover fork 中启用 PlayTools 或重新安装游戏。")))
            } catch {
                result.items.append(
                    readFailure(
                        "injected-tools", .game, String(localized: "PlayTools 加载项"), error, path: executableURL))
            }
            let environment = info["LSEnvironment"] as? [String: Any]
            let paths = (environment?["DYLD_LIBRARY_PATH"] as? String ?? "").split(separator: ":")
            let hasIntrospection = paths.contains { $0 == "/usr/lib/system/introspection" }
            result.items.append(
                item(
                    "introspection", .game, String(localized: "内省库"), hasIntrospection ? .passed : .warning,
                    hasIntrospection ? String(localized: "已插入") : String(localized: "未插入"),
                    String(localized: "依据游戏 Info.plist 的 DYLD_LIBRARY_PATH。"),
                    hasIntrospection ? "" : String(localized: "PlayCover → 游戏设置 → 绕过 → 开启插入内省库，随后重启游戏。")))
        } catch {
            result.items.append(readFailure("game-install", .game, String(localized: "游戏安装"), error, path: infoURL))
            result.items += skippedGameInfo()
        }
    }

    private static func checkSettings(at dataURL: URL, bundleID: String, result: inout PlayCoverStaticResult) {
        let settingsURL = dataURL.appendingPathComponent("App Settings/\(bundleID).plist")
        do {
            let read = try readSettings(configurationData(at: settingsURL))
            result.items.append(
                item(
                    "game-settings", .game, String(localized: "游戏配置文件"), .passed, settingsURL.path,
                    String(localized: "配置文件可解析；每个字段独立判断。"), ""))
            result.items += settingsItems(read.settings, invalidFields: read.errors)
            if let port = read.settings.maaToolsPort, (1...65535).contains(port) { result.port = port }
            result.items += graphics(read.settings, invalidFields: read.errors)
        } catch {
            result.items.append(
                readFailure("game-settings", .game, String(localized: "游戏配置文件"), error, path: settingsURL))
            result.items += skippedSettings()
        }
    }

    private static func skippedDistribution() -> [PlayCoverDiagnosticItem] {
        [("fork", String(localized: "发行信息")), ("bundled-tools", String(localized: "随附 PlayTools"))].map {
            skipped(
                $0.0, .distribution, $0.1, blockedBy: ["playcover-location"],
                reason: String(localized: "PlayCover 应用目录未通过读取检查。"))
        }
    }

    private static func skippedGameInfo() -> [PlayCoverDiagnosticItem] {
        [("injected-tools", String(localized: "PlayTools 加载项")), ("introspection", String(localized: "内省库"))].map {
            skipped(
                $0.0, .game, $0.1, blockedBy: ["game-install"],
                reason: String(localized: "游戏安装信息未通过检查，未读取该游戏的加载项或环境变量。"))
        }
    }

    private static func skippedSettings() -> [PlayCoverDiagnosticItem] {
        let switches = [
            ("maatools", "MaaTools"), ("game-port", String(localized: "MaaTools 端口")), ("playchain", "PlayChain"),
            ("bypass", String(localized: "绕过越狱检测")),
        ]
        return switches.map {
            skipped($0.0, .game, $0.1, blockedBy: ["game-settings"], reason: String(localized: "游戏配置文件未通过读取或解析检查。"))
        } + [
            skipped(
                "graphics-settings", .graphics, String(localized: "图像设置"), blockedBy: ["game-settings"],
                reason: String(localized: "游戏配置文件未通过读取或解析检查，未检查分辨率、宽高、缩放与旋转。"))
        ]
    }

    static func settingsItems(_ settings: PlayCoverGameSettings, invalidFields: [String: String] = [:])
        -> [PlayCoverDiagnosticItem]
    {
        var result = [PlayCoverDiagnosticItem]()
        for (id, title, value, blocking) in [
            ("maatools", "MaaTools", settings.maaTools, true),
            ("playchain", "PlayChain", settings.playChain, false),
            ("bypass", String(localized: "绕过越狱检测"), settings.bypass, false),
        ] {
            result.append(
                item(
                    id, .game, title,
                    value == nil
                        ? (blocking ? .unavailable : .warning) : value == true ? .passed : blocking ? .error : .warning,
                    value.map { $0 ? String(localized: "开启") : String(localized: "关闭") } ?? String(localized: "缺少字段"),
                    blocking ? String(localized: "游戏必须启用 MaaTools 服务。") : String(localized: "MAA 使用指南建议开启此选项。"),
                    value == true ? "" : String(localized: "PlayCover → 游戏设置 → 绕过 → 开启 \(title)，随后重启游戏。")))
        }
        let port = settings.maaToolsPort
        result.append(
            item(
                "game-port", .game, String(localized: "MaaTools 端口"),
                port == nil ? .unavailable : (1...65535).contains(port!) ? .passed : .error,
                port.map(String.init) ?? String(localized: "缺少字段"), String(localized: "服务端口必须在 1–65535 范围内。"),
                port != nil && (1...65535).contains(port!) ? "" : String(localized: "在 PlayCover 中填写有效端口，并保持与 MAA 一致。"))
        )
        return applyFieldErrors(
            result,
            fields: [
                "maatools": ["maaTools"], "game-port": ["maaToolsPort"],
                "playchain": ["playChain"], "bypass": ["bypass"],
            ], errors: invalidFields)
    }

    /// Validate each known field independently, so an invalid graphics field
    /// cannot erase a valid MaaTools switch/port (and vice versa).
    static func readSettings(_ data: Data) throws -> (settings: PlayCoverGameSettings, errors: [String: String]) {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        var errors = [String: String]()
        func field<T>(_ key: String) -> T? {
            guard let value = plist[key] else { return nil }
            let isBoolean = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            guard isBoolean == (T.self == Bool.self), let value = value as? T else {
                errors[key] = String(localized: "配置字段类型无效")
                return nil
            }
            return value
        }
        let settings = PlayCoverGameSettings(
            maaTools: field("maaTools"), maaToolsPort: field("maaToolsPort"),
            playChain: field("playChain"), bypass: field("bypass"), resolution: field("resolution"),
            windowWidth: field("windowWidth"), windowHeight: field("windowHeight"),
            customScaler: field("customScaler"), displayRotation: field("displayRotation"))
        return (settings, errors)
    }

    private static func applyFieldErrors(
        _ items: [PlayCoverDiagnosticItem], fields: [String: [String]],
        errors: [String: String]
    ) -> [PlayCoverDiagnosticItem] {
        items.map { row in
            let invalid = (fields[row.id] ?? []).filter { errors[$0] != nil }
            guard !invalid.isEmpty else { return row }
            return item(
                row.id, row.group, row.title, .error, String(localized: "配置字段类型无效"),
                invalid.map { "\($0)：\(errors[$0]!)" }.joined(separator: "\n"),
                String(localized: "在 PlayCover 中核对该设置，修复后重新检测。"))
        }
    }

    static func skipped(
        _ id: String, _ group: PlayCoverDiagnosticGroup, _ title: String,
        blockedBy: [String], reason: String
    ) -> PlayCoverDiagnosticItem {
        .init(
            id: id, group: group, title: title, status: .unavailable, value: String(localized: "已跳过"),
            reason: reason, remedy: String(localized: "处理前置检查后重新检测。"), blockedBy: blockedBy)
    }

    static func blockedRuntime(_ blockers: [PlayCoverDiagnosticItem]) -> PlayCoverDiagnosticItem {
        let primary = blockers.filter { $0.blockedBy.isEmpty }
        return skipped(
            "runtime-skipped", .runtime, String(localized: "服务与截图"), blockedBy: blockers.map(\.id),
            reason: String(localized: "前置检查未通过：")
                + (primary.isEmpty ? blockers : primary).map { "\($0.title)（\($0.value)）" }.joined(separator: "、")
                + String(localized: "。未连接 MaaTools，也未获取截图。"))
    }

    static func item(
        _ id: String, _ group: PlayCoverDiagnosticGroup, _ title: String,
        _ status: PlayCoverDiagnosticStatus, _ value: String, _ reason: String, _ remedy: String
    ) -> PlayCoverDiagnosticItem {
        .init(id: id, group: group, title: title, status: status, value: value, reason: reason, remedy: remedy)
    }

    static func readFailure(
        _ id: String, _ group: PlayCoverDiagnosticGroup, _ title: String, _ error: any Error,
        path: URL? = nil
    ) -> PlayCoverDiagnosticItem {
        let overLimit: Bool
        switch error as? PlayCoverInspectionError {
        case .oversizedFile, .oversizedLoadCommands: overLimit = true
        default: overLimit = false
        }
        let invalidInspection = error is PlayCoverInspectionError && !overLimit
        let error = error as NSError
        let malformed =
            invalidInspection || error.domain == NSCocoaErrorDomain && error.code == NSPropertyListReadCorruptError
        let missing =
            error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
        let denied =
            error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError
            || error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code)
        return item(
            id, group, title, missing || malformed ? .error : .unavailable,
            overLimit
                ? String(localized: "超出读取上限")
                : missing
                    ? String(localized: "文件不存在")
                    : denied
                        ? String(localized: "访问被拒绝")
                        : malformed ? String(localized: "内容无效") : String(localized: "读取失败"),
            (path.map { String(localized: "检测路径：\($0.path)\n") } ?? "") + error.localizedDescription,
            overLimit
                ? String(localized: "文件超过诊断读取预算，内容尚未验证；核对文件大小后重新检测。")
                : missing
                    ? (group == .distribution
                        ? String(localized: "重新安装完整的指定 PlayCover fork；若使用自定义位置，请展开“检测路径”选择正确应用。")
                        : String(localized: "在 PlayCover 中安装当前客户端；若使用自定义位置，请展开“检测路径”选择正确目录。"))
                    : denied
                        ? String(localized: "在系统设置 → 隐私与安全性检查 MAA 的数据访问权限，允许后重新检测；也可在“检测路径”中手动选择目录授予只读访问。")
                        : String(localized: "核对检测路径与读取权限；若配置损坏，请在 PlayCover 中核对设置。"))
    }
}
