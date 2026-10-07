import CoreGraphics
import Foundation

/// Only read-only MaaTools commands are issued here; no touch or terminate commands.
enum PlayCoverRuntimeChecks {
    static func inspect(
        address: String, mode: String, bundleID: String,
        idPrefix: String = "runtime", label: String = String(localized: "MAA 配置地址"),
        screenPermission: Bool? = nil
    ) async throws -> [PlayCoverDiagnosticItem] {
        try Task.checkCancellation()
        let make = PlayCoverStaticChecks.item
        guard let endpoint = MaaToolsEndpoint(address), var client = MaaToolsClient(to: address) else {
            return skippedRemaining(
                [], prefix: idPrefix, mode: mode, blockedBy: ["address-format"],
                reason: String(localized: "连接地址格式无效，未连接服务。"))
        }
        defer { client.cancel() }
        var result = [PlayCoverDiagnosticItem]()
        var phaseValue = address
        var phaseKey = "handshake"
        var phaseTitle = String(localized: "MaaTools 握手 · \(label)")
        do {
            let version = try await client.version()
            result.append(
                make(
                    "\(idPrefix)-handshake", .runtime, phaseTitle, .passed, address,
                    String(localized: "MaaTools 握手成功。"), ""))
            let knownMode = ["RGBA", "BGR", "MacSCK"].contains(mode)
            let minimum: UInt32 = knownMode && mode != "RGBA" ? 3 : 2
            result.append(
                make(
                    "\(idPrefix)-version", .runtime, String(localized: "MaaTools 协议"),
                    version >= minimum ? .passed : .error,
                    String(version),
                    knownMode
                        ? String(localized: "\(mode) 截图需要协议 ≥\(minimum)；基础尺寸读取需要 ≥2。")
                        : String(localized: "基础尺寸读取需要协议 ≥2；截图模式无效，不能判定截图兼容性。"),
                    version >= minimum ? "" : String(localized: "更新指定 PlayCover fork，随后重启游戏。")))
            guard version >= 2 else {
                return result
                    + skippedRemaining(
                        result, prefix: idPrefix, mode: mode,
                        blockedBy: ["\(idPrefix)-version"], reason: String(localized: "协议不支持基础读取，未检查游戏标识、尺寸或截图。"))
            }
            if version >= 3 {
                phaseKey = "identity"
                phaseTitle = String(localized: "游戏标识")
                let actualBundleID = try await client.bundleName()
                let matches = actualBundleID == bundleID
                result.append(
                    make(
                        "\(idPrefix)-identity", .runtime, phaseTitle, matches ? .passed : .error,
                        actualBundleID, String(localized: "MAA 当前客户端标识：\(bundleID)。"),
                        matches ? "" : String(localized: "检查 MAA 客户端选择和连接端口，确保连接到目标游戏。")))
                guard matches else {
                    return result
                        + skippedRemaining(
                            result, prefix: idPrefix, mode: mode,
                            blockedBy: ["\(idPrefix)-identity"], reason: String(localized: "服务属于其他游戏，未获取其尺寸或画面。"))
                }
            } else {
                result.append(
                    PlayCoverStaticChecks.skipped(
                        "\(idPrefix)-identity", .runtime, String(localized: "游戏标识"),
                        blockedBy: ["\(idPrefix)-version"],
                        reason: String(localized: "协议 v2 不提供游戏标识；RGBA 可继续验证尺寸与截图，但目标身份仍无法确认。")))
            }
            phaseKey = "size"
            phaseTitle = String(localized: "原始分辨率")
            let size = try await client.resolution()
            phaseValue = "\(size.width)×\(size.height)"
            guard size.width > 0, size.height > 0 else {
                throw MaaToolsError.invalidPayload
            }
            guard UInt64(size.width) * UInt64(size.height) * 4 <= MaaToolsClient.maximumImageBytes else {
                throw MaaToolsError.payloadTooLarge
            }
            result.append(
                make(
                    "\(idPrefix)-size", .runtime, phaseTitle, .passed, "\(size.width)×\(size.height)",
                    String(localized: "由运行中的游戏返回；比例、最低尺寸与截图一致性在图片判定时检查。"), ""))
            guard knownMode else {
                return result
                    + skippedRemaining(
                        result, prefix: idPrefix, mode: mode,
                        blockedBy: ["capture-mode"], reason: String(localized: "MAA 截图模式无效，未获取截图或对应窗口信息。"))
            }
            guard version >= minimum else {
                return result
                    + skippedRemaining(
                        result, prefix: idPrefix, mode: mode,
                        blockedBy: ["\(idPrefix)-version"], reason: String(localized: "当前协议不支持 \(mode) 截图及其窗口信息，已跳过。"))
            }
            phaseValue = address
            let image: CGImage
            switch mode {
            case "RGBA":
                phaseKey = "capture"
                phaseTitle = String(localized: "实际截图 · RGBA")
                image = try await MaaImageDiagnostics.rgba(client.rgbaScreenshot(), size: size)
            case "BGR":
                phaseKey = "window"
                phaseTitle = String(localized: "窗口与内容尺寸")
                let capture = try await MaaImageDiagnostics.captureBGR(client: &client, size: size) { window, content in
                    result.append(windowItem(prefix: idPrefix, window: window, content: content))
                    phaseKey = "capture"
                    phaseTitle = String(localized: "实际截图 · BGR")
                }
                image = capture.image
            case "MacSCK":
                phaseKey = "window"
                phaseTitle = String(localized: "窗口与内容尺寸")
                let rect = try await client.bounds()
                let window = windowItem(prefix: idPrefix, window: rect.window, content: rect.content)
                result.append(window)
                var blockers = [String]()
                if window.status != .passed { blockers.append(window.id) }
                if !(screenPermission ?? CGPreflightScreenCaptureAccess()) { blockers.append("screen-permission") }
                if !blockers.isEmpty {
                    return result
                        + skippedRemaining(
                            result, prefix: idPrefix, mode: mode, blockedBy: blockers,
                            reason: blockers.contains("screen-permission")
                                ? String(localized: "MacSCK 未获得录屏权限，未枚举窗口、启动截图流或获取画面。")
                                : String(localized: "窗口与内容尺寸无效，无法按 Core 规则裁剪 MacSCK 画面。"))
                }
                phaseKey = "capture"
                phaseTitle = String(localized: "实际截图 · MacSCK")
                image = try await ScreenCaptureProbe.capture(
                    bundleID: bundleID, port: endpoint.port, size: size, rect: rect)
            default: throw MaaToolsError.unsupportedVersion
            }
            try Task.checkCancellation()
            let diagnosis = MaaImageDiagnosis.evaluate(original: size, width: image.width, height: image.height)
            result.append(
                make(
                    "\(idPrefix)-capture", .runtime, phaseTitle, diagnosis == .passed ? .passed : .error,
                    "\(image.width)×\(image.height)", diagnosis.message,
                    diagnosis == .passed ? "" : String(localized: "按分辨率指南调整 PlayCover 图像设置，重启游戏后重新检测。")))
        } catch {
            try Task.checkCancellation()
            let id = "\(idPrefix)-\(phaseKey)"
            let status: PlayCoverDiagnosticStatus
            if case .payloadTooLarge? = error as? MaaToolsError { status = .unavailable } else { status = .error }
            result.append(
                make(
                    id, .runtime, phaseTitle, status, phaseValue, error.localizedDescription,
                    String(localized: "核对游戏状态、MaaTools 开关和端口；处理此检查项后重新检测。")))
            result += skippedRemaining(
                result, prefix: idPrefix, mode: mode, blockedBy: [id],
                reason: String(localized: "\(phaseTitle)失败，本次后续请求已跳过。"))
        }
        return result
    }

    private static func windowItem(
        prefix: String, window: MaaToolsClient.Rect,
        content: MaaToolsClient.Rect
    ) -> PlayCoverDiagnosticItem {
        let valid =
            window.size.width > 0 && window.size.height > 0
            && content.size.width > 0 && content.size.height > 0
        return PlayCoverStaticChecks.item(
            "\(prefix)-window", .runtime, String(localized: "窗口与内容尺寸"), valid ? .passed : .error,
            "\(window.size.width)×\(window.size.height) / \(content.size.width)×\(content.size.height)",
            String(localized: "与分辨率指南共用窗口信息采集；MacSCK 裁剪依赖有效窗口尺寸，BGR 的图片判定独立于窗口尺寸值。"),
            valid ? "" : String(localized: "确保游戏窗口可见并重新检测。"))
    }

    private static func skippedRemaining(
        _ items: [PlayCoverDiagnosticItem], prefix: String, mode: String,
        blockedBy: [String], reason: String
    ) -> [PlayCoverDiagnosticItem] {
        var stages = [
            ("handshake", String(localized: "MaaTools 握手")), ("version", String(localized: "MaaTools 协议")),
            ("identity", String(localized: "游戏标识")), ("size", String(localized: "原始分辨率")),
        ]
        if ["BGR", "MacSCK"].contains(mode) { stages.append(("window", String(localized: "窗口与内容尺寸"))) }
        stages.append(("capture", String(localized: "实际截图 · \(mode)")))
        return stages.filter { stage in !items.contains { $0.id == "\(prefix)-\(stage.0)" } }.map {
            PlayCoverStaticChecks.skipped("\(prefix)-\($0.0)", .runtime, $0.1, blockedBy: blockedBy, reason: reason)
        }
    }

    static func waitForService(address: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let client = MaaToolsClient(to: address) {
                do {
                    let remaining = ContinuousClock.now.duration(to: deadline).components
                    let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
                    guard seconds > 0 else { break }
                    _ = try await client.version(timeout: min(3, seconds))
                    client.cancel()
                    return
                } catch {
                    client.cancel()
                    try Task.checkCancellation()
                }
            }
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { break }
            try await Task.sleep(for: min(.milliseconds(500), remaining))
        }
        throw MaaToolsError.timedOut
    }
}
