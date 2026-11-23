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
        try? await Task.sleep(for: .milliseconds(150))
        precondition(
            settledService.errorMessage == nil && !settledService.hasPendingOperation
                && !settledService.isUpdating,
            "A late result for a reconciled request must be discarded, not shown as a fresh error")

        // A late result from a request that refresh() already reconciled must not
        // disturb the pending bookkeeping of a newer in-flight request.
        let staleFake = FakeLoginItem()
        let staleService = LoginItemService(manager: staleFake, operationTimeout: .milliseconds(50))
        staleFake.status = .enabled
        staleFake.suspendCancellation = true
        Task { await staleService.setEnabled(false) }
        await eventually("Stale-case removal must start") { staleFake.cancellation != nil }
        await eventually("Stale-case removal must time out") { !staleService.isUpdating }
        precondition(staleService.hasPendingOperation)
        staleFake.status = .notRegistered  // The system settled the removal behind the UI.
        staleService.refresh()  // Reconciliation abandons the old removal's eventual result.
        precondition(!staleService.hasPendingOperation)
        staleFake.suspendRegistration = true
        Task { await staleService.setEnabled(true) }
        await eventually("Stale-case registration must start") { staleFake.registration != nil }
        precondition(
            staleService.isUpdating && staleService.hasPendingOperation,
            "The successor request must be tracked and awaited")
        staleFake.failure = NSError(
            domain: "LoginItemTest", code: 6,
            userInfo: [NSLocalizedDescriptionKey: "Stale removal failure"])
        staleFake.cancellation?.resume()  // The abandoned removal finally reports failure.
        try? await Task.sleep(for: .milliseconds(200))
        precondition(
            staleService.hasPendingOperation && !staleService.isUpdating
                && staleService.errorMessage != nil
                && staleService.errorMessage != "Stale removal failure",
            "A stale late result must leave the successor's tracking and its own deadline intact")
        staleFake.failure = nil
        staleFake.registration?.resume()
        await eventually("The successor must settle on its own result") {
            staleService.status == .enabled && !staleService.hasPendingOperation
                && !staleService.isUpdating && staleService.errorMessage == nil
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

        // The convergence predicate's register direction: a timed-out registration
        // the system enabled behind the UI must be unlocked by refresh(), and its
        // late failure must not surface as a fresh error or re-issue the request.
        let settledRegisterFake = FakeLoginItem()
        let settledRegisterService = LoginItemService(
            manager: settledRegisterFake, operationTimeout: .milliseconds(50))
        settledRegisterFake.status = .notRegistered
        settledRegisterFake.suspendRegistration = true
        let settledRegistration = Task { await settledRegisterService.setEnabled(true) }
        await eventually("Settled-case registration must start") { settledRegisterFake.registration != nil }
        await eventually("Settled-case registration must time out") { !settledRegisterService.isUpdating }
        await settledRegistration.value
        precondition(
            settledRegisterService.hasPendingOperation && settledRegisterService.errorMessage != nil,
            "A stalled registration must stay tracked until it settles or refresh() reconciles it")
        settledRegisterFake.status = .enabled  // The system finished the registration behind the UI.
        settledRegisterService.refresh()
        precondition(
            !settledRegisterService.hasPendingOperation && settledRegisterService.errorMessage == nil
                && settledRegisterService.status == .enabled,
            "Refresh must unlock a pending registration the system already enabled")
        let settledRegistrations = settledRegisterFake.registrations
        await settledRegisterService.setEnabled(true)
        precondition(
            settledRegisterFake.registrations == settledRegistrations,
            "An unlocked settled registration must not be re-issued")
        settledRegisterFake.failure = NSError(
            domain: "LoginItemTest", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Late settled-registration failure"])
        settledRegisterFake.registration?.resume()
        try? await Task.sleep(for: .milliseconds(150))
        precondition(
            settledRegisterService.errorMessage == nil && !settledRegisterService.hasPendingOperation
                && !settledRegisterService.isUpdating && settledRegisterService.status == .enabled,
            "A late failure for a reconciled registration must be discarded, not shown as a fresh error")

        // Two successive refresh() reconciliations bump the generation twice; stale
        // results from both abandoned requests must be discarded inside the pending
        // window of the third request, which settles on its own result.
        let chainFake = FakeLoginItem()
        let chainService = LoginItemService(manager: chainFake, operationTimeout: .milliseconds(50))
        chainFake.status = .enabled
        chainFake.suspendCancellation = true
        Task { await chainService.setEnabled(false) }  // Request A: removal, generation 0.
        await eventually("Chain request A must start") { chainFake.cancellation != nil }
        await eventually("Chain request A must time out") { !chainService.isUpdating }
        let staleRemovalA = chainFake.cancellation
        chainFake.cancellation = nil
        chainFake.status = .notRegistered  // The system settled A behind the UI.
        chainService.refresh()  // First reconciliation abandons A's eventual result.
        precondition(!chainService.hasPendingOperation)
        chainFake.suspendRegistration = true
        Task { await chainService.setEnabled(true) }  // Request B: registration, generation 1.
        await eventually("Chain request B must start") { chainFake.registration != nil }
        await eventually("Chain request B must time out") { !chainService.isUpdating }
        let staleRegistrationB = chainFake.registration
        chainFake.registration = nil
        chainFake.status = .enabled  // The system settled B behind the UI.
        chainService.refresh()  // Second reconciliation abandons B's eventual result.
        precondition(
            !chainService.hasPendingOperation && chainService.status == .enabled,
            "Both reconciliations must unlock their own abandoned requests")
        Task { await chainService.setEnabled(false) }  // Request C: removal, generation 2.
        await eventually("Chain request C must start") { chainFake.cancellation != nil }
        precondition(
            chainService.isUpdating && chainService.hasPendingOperation,
            "The third request must be tracked and awaited")
        chainFake.failure = NSError(
            domain: "LoginItemTest", code: 8,
            userInfo: [NSLocalizedDescriptionKey: "Stale chain failure A"])
        staleRemovalA?.resume()  // A's abandoned removal finally reports failure.
        chainFake.failure = NSError(
            domain: "LoginItemTest", code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Stale chain failure B"])
        staleRegistrationB?.resume()  // B's abandoned registration finally reports failure.
        try? await Task.sleep(for: .milliseconds(200))
        precondition(
            chainService.hasPendingOperation && !chainService.isUpdating
                && chainService.errorMessage != nil
                && chainService.errorMessage != "Stale chain failure A"
                && chainService.errorMessage != "Stale chain failure B",
            "Stale results from two abandoned generations must leave the third request's tracking and its own deadline intact")
        chainFake.failure = nil
        chainFake.cancellation?.resume()
        await eventually("Chain request C must settle on its own result") {
            chainService.status == .notRegistered && !chainService.hasPendingOperation
                && !chainService.isUpdating && chainService.errorMessage == nil
        }

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
            "PASS: four statuses, opt-in, external changes, approval, failures, concurrency, registration/removal deadlines, bounded retry, late results, refresh reconciliation, register-direction reconciliation, stale-result isolation, multi-generation stale chain and blocked production adapter"
        )
    }
}
