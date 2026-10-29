import Foundation
import ServiceManagement

@MainActor private final class FakeLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var registrations = 0
    var cancellations = 0
    var settingsOpened = 0
    var failure: Error?
    var registrationResult: SMAppService.Status = .enabled
    var cancellation: CheckedContinuation<Void, Never>?
    var suspendCancellation = false

    func register() throws {
        registrations += 1
        if let failure { throw failure }
        status = registrationResult
    }
    func unregister() async throws {
        cancellations += 1
        if suspendCancellation {
            await withCheckedContinuation { cancellation = $0 }
        }
        if let failure { throw failure }
        status = .notRegistered
    }
    func openSettings() { settingsOpened += 1 }
}

@main private struct LoginItemServiceTests {
    @MainActor static func main() async {
        let fake = FakeLoginItem()
        let service = LoginItemService(manager: fake)
        precondition(fake.registrations == 0, "Initialization must never register")
        for state in [SMAppService.Status.notRegistered, .enabled, .requiresApproval, .notFound] {
            fake.status = state
            service.refresh()
            precondition(service.status == state)
        }
        precondition(fake.registrations == 0, "Refresh must never register")
        fake.status = .notRegistered
        await service.setEnabled(true)
        precondition(service.status == .enabled && fake.registrations == 1)
        await service.setEnabled(true)
        precondition(fake.registrations == 1, "Repeated enabled request must be idempotent")
        await service.setEnabled(false)
        precondition(service.status == .notRegistered && fake.cancellations == 1)
        await service.setEnabled(false)
        precondition(fake.cancellations == 1)
        fake.registrationResult = .requiresApproval
        await service.setEnabled(true)
        precondition(service.status == .requiresApproval)
        await service.setEnabled(true)
        precondition(fake.registrations == 2 && fake.settingsOpened == 1)
        await service.setEnabled(false)
        precondition(service.status == .notRegistered)
        fake.failure = NSError(
            domain: "LoginItemTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration failed"])
        await service.setEnabled(true)
        precondition(service.status == .notRegistered && service.errorMessage == "Registration failed")
        fake.failure = nil
        fake.registrationResult = .enabled
        await service.retry()
        precondition(service.status == .enabled && service.errorMessage == nil)
        fake.failure = NSError(domain: "LoginItemTest", code: 2)
        await service.setEnabled(false)
        precondition(service.status == .enabled && service.errorMessage != nil)
        fake.failure = nil
        await service.retry()
        precondition(service.status == .notRegistered && service.errorMessage == nil)
        fake.status = .enabled
        service.refresh()
        fake.status = .requiresApproval  // System Settings disabled the item.
        let registrations = fake.registrations
        service.refresh()
        precondition(service.status == .requiresApproval && fake.registrations == registrations)
        fake.status = .notFound
        service.refresh()
        await service.setEnabled(true)
        precondition(service.status == .enabled)
        fake.suspendCancellation = true
        let cancellation = Task { await service.setEnabled(false) }
        while fake.cancellation == nil { await Task.yield() }
        precondition(service.isUpdating)
        await service.setEnabled(true)
        precondition(fake.registrations == registrations + 1, "Concurrent request must not re-register")
        fake.cancellation?.resume()
        await cancellation.value
        precondition(service.status == .notRegistered && !service.isUpdating)
        print(
            "PASS: four statuses, opt-in registration, external changes, pending approval, retry, cancellation and concurrent requests"
        )
    }
}
