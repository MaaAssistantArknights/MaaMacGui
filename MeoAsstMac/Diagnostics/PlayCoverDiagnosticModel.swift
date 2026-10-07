import AppKit
import CoreGraphics
import Foundation

@MainActor final class PlayCoverDiagnosticModel: ObservableObject {
    @Published private(set) var report: PlayCoverDiagnosticReport?
    @Published private(set) var isDetecting = false
    @Published private(set) var phase = ""
    @Published var needsRefresh = false
    private var task: Task<Void, Never>?
    private let isGameRunning: (String) -> Bool
    private let openGame: (URL) async throws -> Void
    private let waitForService: (String) async throws -> Void
    private let inspect:
        (PlayCoverDiagnosticSnapshot, String, String, String, Bool) async throws -> [PlayCoverDiagnosticItem]

    init(
        isGameRunning: @escaping (String) -> Bool = { bundleID in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
        },
        openGame: @escaping (URL) async throws -> Void = { url in
            let launcher = PlayCoverGameLauncher()
            try await launcher.wait { completion in
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in completion(error) }
            }
        },
        waitForService: @escaping (String) async throws -> Void = { address in
            try await PlayCoverRuntimeChecks.waitForService(address: address)
        },
        inspect:
            @escaping (PlayCoverDiagnosticSnapshot, String, String, String, Bool) async throws ->
            [PlayCoverDiagnosticItem] = { snapshot, address, prefix, label, permission in
                try await PlayCoverRuntimeChecks.inspect(
                    address: address, mode: snapshot.screenshotMode,
                    bundleID: snapshot.bundleID, idPrefix: prefix, label: label, screenPermission: permission)
            }
    ) {
        self.isGameRunning = isGameRunning
        self.openGame = openGame
        self.waitForService = waitForService
        self.inspect = inspect
    }

    func cancel(reason: String = String(localized: "检测已取消，未完成的项目不能视为通过。")) {
        guard isDetecting, task?.isCancelled != true else { return }
        task?.cancel()
        report?.items.append(
            PlayCoverStaticChecks.item(
                "cancelled", .runtime, String(localized: "检测中断"), .unavailable,
                String(localized: "已取消"), reason, String(localized: "重新检测以完成所有项目。")))
    }

    func start(
        snapshot: PlayCoverDiagnosticSnapshot, access: PlayCoverAccess, runtimeAllowed: Bool,
        launch: Bool = false
    ) {
        guard !isDetecting else { return }
        isDetecting = true
        needsRefresh = false
        report = .init(date: Date(), snapshot: snapshot, items: [])
        task = Task {
            defer { withExtendedLifetime(access) {} }
            defer {
                isDetecting = false
                phase = ""
                task = nil
            }
            guard !Task.isCancelled else { return }
            phase = String(localized: "检查版本与配置")
            let permission = CGPreflightScreenCaptureAccess()
            let result = await scan(snapshot: snapshot, access: access, screenPermission: permission)
            guard !Task.isCancelled else { return }
            report?.items = result.items
            report?.items.append(
                PlayCoverStaticChecks.item(
                    "maa-idle", .maa, String(localized: "MAA 任务状态"), runtimeAllowed ? .passed : .warning,
                    runtimeAllowed ? String(localized: "空闲") : String(localized: "正在执行任务"),
                    String(localized: "任务运行期间仅进行静态检查。"), runtimeAllowed ? "" : String(localized: "等待 MAA 空闲后重新检测。")))
            guard runtimeAllowed else {
                report?.items.append(
                    PlayCoverStaticChecks.skipped(
                        "runtime-skipped", .runtime, String(localized: "运行检查"), blockedBy: ["maa-idle"],
                        reason: String(localized: "MAA 正在执行任务，未启动游戏、连接服务或获取截图。")))
                return
            }
            await checkRuntime(snapshot: snapshot, result: result, launch: launch, permission: permission)
        }
    }

    private func scan(
        snapshot: PlayCoverDiagnosticSnapshot, access: PlayCoverAccess, screenPermission: Bool
    ) async -> PlayCoverStaticResult {
        let appURL = access.applicationURL
        let dataURL = access.dataURL
        let scan = Task.detached {
            PlayCoverStaticChecks.run(
                snapshot: snapshot, appURL: appURL, dataURL: dataURL, screenPermission: screenPermission)
        }
        return await withTaskCancellationHandler {
            await scan.value
        } onCancel: {
            scan.cancel()
        }
    }

    private func checkRuntime(
        snapshot: PlayCoverDiagnosticSnapshot, result: PlayCoverStaticResult, launch: Bool, permission: Bool
    ) async {
        var failureID = "launch-failure"
        var failureTitle = String(localized: "启动游戏")
        do {
            try Task.checkCancellation()
            // An explicit launch only requires a verified installation.
            // Service readiness is evaluated separately before waiting or probing.
            var launched = false
            if launch {
                guard let gameURL = result.gameURL else {
                    report?.items.append(
                        PlayCoverStaticChecks.skipped(
                            "launch-failure", .runtime, String(localized: "启动游戏"),
                            blockedBy: ["game-install"], reason: String(localized: "游戏安装未通过检查，未尝试启动游戏。")))
                    report?.items.append(PlayCoverStaticChecks.blockedRuntime(result.runtimeBlockers))
                    return
                }
                if !isGameRunning(snapshot.bundleID) {
                    phase = String(localized: "启动游戏")
                    try await openGame(gameURL)
                    try Task.checkCancellation()
                    launched = true
                    report?.items.append(
                        PlayCoverStaticChecks.item(
                            "game-launch", .runtime, String(localized: "启动游戏"), .passed,
                            snapshot.clientName, String(localized: "已按当前客户端请求启动游戏。"), ""))
                }
            }
            let blockers = result.runtimeBlockers
            guard blockers.isEmpty, let port = result.port else {
                report?.items.append(PlayCoverStaticChecks.blockedRuntime(blockers))
                return
            }
            if launched {
                phase = String(localized: "等待 MaaTools 服务")
                failureID = "service-wait"
                failureTitle = String(localized: "MaaTools 服务等待")
                try await waitForService("localhost:\(port)")
            }
            let running = isGameRunning(snapshot.bundleID)
            report?.items.append(
                PlayCoverStaticChecks.item(
                    "game-process", .runtime, String(localized: "游戏进程"), running ? .passed : .unavailable,
                    running ? String(localized: "运行中") : String(localized: "未运行"),
                    String(localized: "当前客户端：\(snapshot.clientName)。"),
                    running ? "" : String(localized: "点击“启动游戏并继续检测”，或手动启动后重新检测。")))
            guard running else {
                report?.items.append(
                    PlayCoverStaticChecks.skipped(
                        "runtime-skipped", .runtime, String(localized: "服务与截图"),
                        blockedBy: ["game-process"], reason: String(localized: "游戏未运行，未连接 MaaTools 或获取截图。")))
                return
            }
            phase = String(localized: "检查 MaaTools 与实际截图")
            failureID = "runtime-handshake"
            failureTitle = String(localized: "MAA 配置地址的运行检查")
            let endpoint = MaaToolsEndpoint(snapshot.address)
            if endpoint != nil {
                report?.items += try await inspect(
                    snapshot, snapshot.address, "runtime", String(localized: "MAA 配置地址"), permission)
            } else {
                report?.items.append(
                    PlayCoverStaticChecks.skipped(
                        "runtime-handshake", .runtime, String(localized: "MAA 配置地址"),
                        blockedBy: ["address-format"], reason: String(localized: "配置地址格式无效，未连接此地址；仍可独立探测游戏配置端口。")))
            }
            if endpoint?.matchesLocalPort(port) != true {
                try Task.checkCancellation()
                phase = String(localized: "检查游戏配置端口")
                failureID = "game-port-handshake"
                failureTitle = String(localized: "游戏配置端口的运行检查")
                report?.items += try await inspect(
                    snapshot, "localhost:\(port)", "game-port", String(localized: "游戏配置端口"), permission)
            }
        } catch is CancellationError {
            // `cancel` has already recorded why this run was interrupted.
        } catch {
            report?.items.append(
                PlayCoverStaticChecks.item(
                    failureID, .runtime, failureTitle, .error,
                    phase, error.localizedDescription, String(localized: "核对游戏、MaaTools 与端口后重新检测。")))
            report?.items.append(
                PlayCoverStaticChecks.skipped(
                    "runtime-skipped", .runtime, String(localized: "后续运行检查"),
                    blockedBy: [failureID], reason: String(localized: "\(failureTitle)失败，后续运行检查已跳过。")))
        }
    }
}

/// Bounds the system launch callback without trying to undo a requested launch.
@MainActor final class PlayCoverGameLauncher {
    private var completion: CheckedContinuation<Void, any Swift.Error>?
    private var finished = false
    private var timeoutTask: Task<Void, Never>?

    enum Error: Swift.Error, LocalizedError {
        case timedOut
        var errorDescription: String? { String(localized: "游戏启动请求超时，系统未完成启动回调。") }
    }

    func wait(timeout: TimeInterval = 20, start: (@escaping @Sendable ((any Swift.Error)?) -> Void) -> Void)
        async throws
    {
        guard completion == nil, !finished else { throw CocoaError(.featureUnsupported) }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                self.completion = continuation
                timeoutTask = Task {
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    finish(Error.timedOut)
                }
                start { error in Task { @MainActor in self.finish(error) } }
            }
        } onCancel: {
            Task { @MainActor in self.finish(CancellationError()) }
        }
    }

    private func finish(_ error: (any Swift.Error)?) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        if let error { completion?.resume(throwing: error) } else { completion?.resume() }
        completion = nil
    }
}
