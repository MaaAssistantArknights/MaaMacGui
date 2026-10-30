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
    var registration: CheckedContinuation<Void, Never>?
    var suspendRegistration = false

    func register() async throws {
        registrations += 1
        if suspendRegistration {
            await withCheckedContinuation { registration = $0 }
        }
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

/// A non-cooperative system call: cancellation cannot release this gate.
private final class BlockingLoginOperation: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var started = false

    var hasStarted: Bool { lock.withLock { started } }

    func run() {
        precondition(!Thread.isMainThread, "System mutation must run off the UI thread")
        lock.withLock { started = true }
        gate.wait()
    }

    func release() { gate.signal() }
}

@main private struct LoginItemServiceTests {
    @MainActor private static func eventually(_ message: String, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        precondition(condition(), message)
    }

    @MainActor static func main() async {
        let watchdog = Task.detached {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            fatalError("Login-item tests stalled, possibly blocking the main actor")
        }
        defer { watchdog.cancel() }
        let fake = FakeLoginItem()
        let service = LoginItemService(manager: fake, operationTimeout: .milliseconds(50))
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
        await eventually("Removal must start") { fake.cancellation != nil }
        precondition(service.isUpdating)
        await service.setEnabled(true)
        precondition(fake.registrations == registrations + 1, "Concurrent request must not re-register")
        fake.cancellation?.resume()
        await cancellation.value
        precondition(service.status == .notRegistered && !service.isUpdating)
        fake.status = .enabled
        fake.cancellation = nil
        let stalled = Task { await service.setEnabled(false) }
        await eventually("Stalled removal must start") { fake.cancellation != nil }
        await eventually("Stalled removal must time out") { !service.isUpdating }
        await stalled.value
        precondition(
            !service.isUpdating && service.errorMessage != nil,
            "A stalled removal must leave updating state within the deadline")
        precondition(service.hasPendingOperation, "Timeout cannot cancel the OS request")
        let removals = fake.cancellations
        let registrationsBeforeTimeout = fake.registrations
        await service.setEnabled(true)
        await service.setEnabled(false)
        precondition(
            fake.cancellations == removals && fake.registrations == registrationsBeforeTimeout,
            "Timeout must not permit overlapping mutations")
        service.openSettings()
        precondition(fake.settingsOpened == 2, "System Settings must stay reachable after timeout")
        let retry = Task { await service.retry() }
        await eventually("Retry must wait on the existing removal") { service.isUpdating }
        await service.retry()
        precondition(fake.cancellations == removals, "Retry must not duplicate the pending request")
        fake.cancellation?.resume()
        await retry.value
        precondition(
            service.status == .notRegistered && !service.hasPendingOperation && service.errorMessage == nil,
            "Late success must reconcile authoritative status and clear timeout")

        fake.suspendRegistration = true
        let registering = Task { await service.setEnabled(true) }
        await eventually("Stalled registration must start") { fake.registration != nil }
        await eventually("Stalled registration must time out") { !service.isUpdating }
        await registering.value
        precondition(service.hasPendingOperation && service.errorMessage != nil)
        await service.retry()
        precondition(
            service.hasPendingOperation && !service.isUpdating && service.errorMessage != nil,
            "Retry on a non-returning request must also be bounded")
        fake.failure = NSError(
            domain: "LoginItemTest", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Late registration failure"])
        fake.registration?.resume()
        await eventually("Late failure must finish the pending request") { !service.hasPendingOperation }
        precondition(service.status == .notRegistered && service.errorMessage == "Late registration failure")
        fake.failure = nil
        fake.suspendRegistration = false
        await service.retry()
        precondition(
            service.status == .enabled && service.errorMessage == nil,
            "A completed late failure must allow a fresh retry")

        // A timed-out request the system later settled must be unlocked by refresh();
        // an unsettled one must keep guarding against overlapping mutations.
        let settledFake = FakeLoginItem()
        let settledService = LoginItemService(manager: settledFake, operationTimeout: .milliseconds(50))
        settledFake.status = .enabled
        settledFake.suspendCancellation = true
        let settledRemoval = Task { await settledService.setEnabled(false) }
        await eventually("Settled-case removal must start") { settledFake.cancellation != nil }
        await eventually("Settled-case removal must time out") { !settledService.isUpdating }
        precondition(settledService.hasPendingOperation && settledService.errorMessage != nil)
        settledFake.status = .notRegistered  // The system finished the removal behind the UI.
        settledService.refresh()
        precondition(
            !settledService.hasPendingOperation && settledService.errorMessage == nil,
            "Refresh must unlock a pending request the system already settled")
        await settledRemoval.value
        let settledRemovals = settledFake.cancellations
        await settledService.setEnabled(false)
        precondition(
            settledFake.cancellations == settledRemovals,
            "An unlocked settled request must not be re-issued")
        settledFake.failure = NSError(
            domain: "LoginItemTest", code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Late removal failure"])
        settledFake.cancellation?.resume()
        await eventually("A late result must not relock a reconciled request") {
            settledService.errorMessage != nil && !settledService.hasPendingOperation
                && !settledService.isUpdating
        }

        let stuckFake = FakeLoginItem()
        let stuckService = LoginItemService(manager: stuckFake, operationTimeout: .milliseconds(50))
        stuckFake.suspendRegistration = true
        let stuckRegistration = Task { await stuckService.setEnabled(true) }
        await eventually("Unsettled-case registration must start") { stuckFake.registration != nil }
        await eventually("Unsettled-case registration must time out") { !stuckService.isUpdating }
        stuckService.refresh()
        precondition(
            stuckService.hasPendingOperation,
            "Refresh must keep guarding a request the system has not settled")
        stuckFake.registration?.resume()
        await stuckRegistration.value

        // Exercise the production adapter, including synchronous blocking before
        // an asynchronous unregister call has a chance to suspend.
        for enabled in [true, false] {
            let blocking = BlockingLoginOperation()
            let manager = MainAppLoginItem(
                readStatus: { enabled ? .notRegistered : .enabled },
                registerOperation: { blocking.run() },
                unregisterOperation: { blocking.run() })
            let blockedService = LoginItemService(manager: manager, operationTimeout: .milliseconds(30))
            let request = Task { await blockedService.setEnabled(enabled) }
            await eventually("Production adapter must start the system operation") { blocking.hasStarted }
            await eventually("Main actor and deadline must remain responsive during blocked system calls") {
                !blockedService.isUpdating
            }
            await request.value
            precondition(blockedService.hasPendingOperation && blockedService.errorMessage != nil)
            blocking.release()
            await eventually("Production adapter must reconcile late completion") {
                !blockedService.hasPendingOperation
            }
            precondition(blockedService.errorMessage == nil)
        }
        print(
            "PASS: four statuses, opt-in, external changes, approval, failures, concurrency, registration/removal deadlines, bounded retry, late results, refresh reconciliation and blocked production adapter"
        )
    }
}
