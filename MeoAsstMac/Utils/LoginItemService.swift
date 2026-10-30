import Combine
import ServiceManagement

/// System status is authoritative; no separate enabled preference is persisted.
@MainActor protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() async throws
    func unregister() async throws
    func openSettings()
}

@MainActor struct MainAppLoginItem: LoginItemManaging {
    private let readStatus: @MainActor () -> SMAppService.Status
    private let registerOperation: @Sendable () throws -> Void
    private let unregisterOperation: @Sendable () async throws -> Void

    init(
        readStatus: @escaping @MainActor () -> SMAppService.Status = { SMAppService.mainApp.status },
        registerOperation: @escaping @Sendable () throws -> Void = { try SMAppService.mainApp.register() },
        unregisterOperation: @escaping @Sendable () async throws -> Void = {
            try await SMAppService.mainApp.unregister()
        }
    ) {
        self.readStatus = readStatus
        self.registerOperation = registerOperation
        self.unregisterOperation = unregisterOperation
    }

    var status: SMAppService.Status { readStatus() }

    // Explicit executor hop: a synchronous ServiceManagement call must not block settings.
    @concurrent func register() async throws {
        try registerOperation()
    }

    @concurrent func unregister() async throws {
        try await unregisterOperation()
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor final class LoginItemService: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?
    private let manager: any LoginItemManaging
    private let operationTimeout: Duration
    private var failedRequest: Bool?
    @Published private var pendingRequest: Bool?
    private var waiter: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    var hasPendingOperation: Bool { pendingRequest != nil }

    convenience init() {
        self.init(manager: MainAppLoginItem())
    }

    init(manager: any LoginItemManaging, operationTimeout: Duration = .seconds(10)) {
        self.manager = manager
        self.operationTimeout = operationTimeout
        status = manager.status
    }

    func refresh() {
        status = manager.status
    }

    func openSettings() {
        manager.openSettings()
    }

    func retry() async {
        guard !isUpdating else { return }
        if hasPendingOperation {
            // SMAppService has no cancellation API. Rejoin the existing request rather
            // than launching overlapping writes whose eventual order is unknown.
            await waitForPendingOperation()
            return
        }
        guard let failedRequest else { return }
        await setEnabled(failedRequest)
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating, !hasPendingOperation else { return }
        errorMessage = nil
        failedRequest = nil
        refresh()
        if enabled {
            switch status {
            case .enabled:
                return
            case .requiresApproval:
                manager.openSettings()
                return
            default:
                break
            }
        } else if status == .notRegistered {
            return
        }
        pendingRequest = enabled
        // Unstructured work deliberately outlives the UI deadline: cancellation
        // cannot stop the underlying OS request. Observe its eventual result.
        Task { [weak self, manager] in
            let result: Result<Void, Error>
            do {
                if enabled {
                    try await manager.register()
                } else {
                    try await manager.unregister()
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.complete(result, enabled: enabled)
        }
        await waitForPendingOperation()
    }

    private func waitForPendingOperation() async {
        guard hasPendingOperation else { return }
        isUpdating = true
        errorMessage = nil
        await withCheckedContinuation { continuation in
            waiter = continuation
            timeoutTask = Task { [weak self, operationTimeout] in
                do {
                    try await Task.sleep(for: operationTimeout)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.errorMessage = String(localized: "登录项操作超时，系统可能仍在处理。可重试等待结果，或打开系统登录项设置检查。")
                self.finishWaiting()
            }
        }
    }

    private func complete(_ result: Result<Void, Error>, enabled: Bool) {
        pendingRequest = nil
        refresh()
        switch result {
        case .success:
            errorMessage = nil
            failedRequest = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
            failedRequest = enabled
        }
        finishWaiting()
    }

    private func finishWaiting() {
        timeoutTask?.cancel()
        timeoutTask = nil
        isUpdating = false
        let continuation = waiter
        waiter = nil
        continuation?.resume()
    }
}
