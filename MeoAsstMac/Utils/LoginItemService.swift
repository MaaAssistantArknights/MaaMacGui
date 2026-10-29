import Combine
import ServiceManagement

/// System status is authoritative; no separate enabled preference is persisted.
@MainActor protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
    func openSettings()
}

@MainActor struct MainAppLoginItem: LoginItemManaging {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() async throws {
        try await SMAppService.mainApp.unregister()
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
    private var failedRequest: Bool?

    convenience init() {
        self.init(manager: MainAppLoginItem())
    }

    init(manager: any LoginItemManaging) {
        self.manager = manager
        status = manager.status
    }

    func refresh() {
        status = manager.status
    }

    func openSettings() {
        manager.openSettings()
    }

    func retry() async {
        guard let failedRequest else { return }
        await setEnabled(failedRequest)
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer {
            refresh()
            isUpdating = false
        }
        errorMessage = nil
        failedRequest = nil
        refresh()
        do {
            if enabled {
                switch status {
                case .enabled:
                    return
                case .requiresApproval:
                    manager.openSettings()
                default:
                    try manager.register()
                }
            } else if status != .notRegistered {
                try await manager.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
            failedRequest = enabled
        }
    }
}
