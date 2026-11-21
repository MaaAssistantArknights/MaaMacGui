import Foundation
import JBirdCore
import Network
import os

/// MaaCore overlays resources process-wide. Each client gets a fresh process so its OCR rules
/// and templates cannot leak into the next client's run.
@MainActor
enum ClientTaskRunner {
    static let argument = "--maa-client-task-batch"

    enum Event {
        case task(Int32, UUID)
        case message(MaaMessage)
    }

    private enum Record: Codable {
        case task(Int32, UUID)
        case message(Int, Data)
        case completed([Int32])
        case failure(String)
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func run(
        _ batch: ClientTaskBatch, inactivityTimeout: Duration = .seconds(30 * 60), receive: (Event) -> Void
    ) async throws -> MaaMessage {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = Bundle.main.executableURL
        process.arguments = [argument]
        process.standardInput = input
        process.standardOutput = output
        let request = try JSONEncoder().encode(batch) + [0x0a]
        // A worker can exit while a large request is still in the pipe. Return EPIPE to the GUI.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw MaaCoreError.startFailed
        }
        try process.run()
        @Sendable func killWorker() -> Bool {
            process.isRunning && kill(process.processIdentifier, SIGKILL) == 0
        }
        // The parent must be able to stop a worker even if its core or main thread is blocked.
        let activity = OSAllocatedUnfairLock(initialState: SuspendingClock.now)
        let watchdog = Task.detached {
            while true {
                let deadline = activity.withLock { $0 + inactivityTimeout }
                try await Task.sleep(until: deadline, clock: .suspending)
                guard activity.withLock({ $0 + inactivityTimeout <= .now }) else { continue }
                return killWorker()
            }
        }
        defer {
            watchdog.cancel()
            try? input.fileHandleForWriting.close()
            _ = killWorker()
            process.waitUntilExit()
        }
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await Task.detached { try input.fileHandleForWriting.write(contentsOf: request) }.value
                var completed: [Int32]?
                for try await line in output.fileHandleForReading.bytes.lines {
                    try Task.checkCancellation()
                    let record = try JSONDecoder().decode(Record.self, from: Data(line.utf8))
                    activity.withLock { $0 = .now }
                    switch record {
                    case .task(let coreID, let id): receive(.task(coreID, id))
                    case .message(let code, let details):
                        receive(.message(MaaMessage(code: code, details: try JSON(details))))
                    case .completed(let ids): completed = ids
                    case .failure(let detail): throw Failure(detail)
                    }
                }
                await Task.detached { process.waitUntilExit() }.value
                try Task.checkCancellation()
                guard process.terminationStatus == 0, let completed else {
                    throw Failure(String(localized: .taskError(name: batch.client.description)))
                }
                let details = try JSONEncoder().encode(["finished_tasks": completed])
                return MaaMessage(code: .AllTasksCompleted, details: try JSON(details))
            } onCancel: {
                _ = killWorker()
            }
        } catch {
            watchdog.cancel()
            try Task.checkCancellation()
            if (try? await watchdog.value) == true {
                throw Failure(String(localized: "\(batch.client.description)：任务超时，已停止"))
            }
            throw error
        }
    }

    static func workerMain() async -> Int32 {
        // Reserve the pipe for framed events, including when native libraries print diagnostics.
        let descriptor = fcntl(STDOUT_FILENO, F_DUPFD_CLOEXEC, 0)
        guard descriptor >= 0 else { return EXIT_FAILURE }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else { return EXIT_FAILURE }
        func send(_ record: Record) throws {
            try output.write(contentsOf: JSONEncoder().encode(record) + [0x0a])
        }
        do {
            guard let line = readLine() else { throw CancellationError() }
            let batch = try JSONDecoder().decode(ClientTaskBatch.self, from: Data(line.utf8))
            // A closed parent (including a crash) must not leave an automation process running.
            DispatchQueue.global().async {
                _ = try? FileHandle.standardInput.readToEnd()
                _exit(EXIT_FAILURE)
            }
            try await execute(batch, send: send)
            return EXIT_SUCCESS
        } catch {
            let message = switch error {
            case let failure as Failure: failure.description
            case MaaToolsError.handshakeFailed, MaaCoreError.connectFailed, is NWError: String(localized: "连接失败")
            case MaaToolsError.unsupportedVersion: String(localized: "不支持此版本PlayCover")
            case MAAError.gameStartFailed: String(localized: .failedToOpenClient)
            case is CancellationError: String(localized: .stopped)
            default: String(localized: "StartTasksFailed: \(String(describing: error))")
            }
            Logger(subsystem: "plus.maa.swift", category: "ClientTaskRunner").error("Worker failed: \(String(describing: error))")
            try? send(.failure(message))
            return EXIT_FAILURE
        }
    }

    private static func execute(_ batch: ClientTaskBatch, send: (Record) throws -> Void) async throws {
        let model = MAAViewModel(loadDailyTasks: false)
        try await model.initialize(for: batch.client)
        var options = model.instanceOptions
        options[.ClientType] = batch.client.rawValue
        let handle = try await MAAHandle(options: options)
        var messages = handle.messages.makeAsyncIterator()
        var entries = batch.tasks
        if model.touchMode == .MacPlayTools, batch.followedByAnotherClient {
            var close = ClosedownConfiguration()
            close.client_type = batch.client
            if entries.last?.task != .closedown(close) { entries.append(DailyTask(config: close)) }
        }
        var remaining = entries[...]
        var completed = [Int32]()
        while let first = remaining.first {
            // Wait for each login to succeed before submitting actions for that account.
            let tasks: ArraySlice<DailyTask>
            if case .startup(let startup) = first.task {
                if model.touchMode == .MacPlayTools {
                    try await model.preparePlayCover(client: batch.client, launch: startup.start_game_enabled)
                }
                try await model.connect(handle)
                tasks = remaining.prefix(1)
            } else {
                if completed.isEmpty {
                    if model.touchMode == .MacPlayTools {
                        try await model.preparePlayCover(client: batch.client, launch: false)
                    }
                    try await model.connect(handle)
                }
                tasks = remaining.prefix {
                    if case .startup = $0.task { return false }
                    return true
                }
            }
            var ids = [Int32]()
            for task in tasks {
                let id = try await handle.appendTask(task.task)
                ids.append(id)
                try send(.task(id, task.id))
            }
            try await handle.start()
            while true {
                guard let message = await messages.next() else { throw MaaCoreError.startFailed }
                if message.code == .AllTasksCompleted {
                    let finished: [Int32] = try message.details["finished_tasks"]
                    guard finished == ids else { throw MaaCoreError.startFailed }
                    completed += finished
                    break
                }
                try send(.message(message.code, message.details.serialize()))
                if message.code == .TaskChainStopped {
                    throw CancellationError()
                }
                if message.code == .TaskChainError, case .startup = first.task {
                    try await handle.stop()
                    throw Failure(String(localized: .stopped))
                }
            }
            remaining = remaining.dropFirst(tasks.count)
            if !remaining.isEmpty, model.touchMode == .MacPlayTools, case .closedown? = tasks.last?.task {
                // A second login on this same client must not attach to its closing window.
                let deadline = ContinuousClock.now + .seconds(6)
                while try await MaaToolsClient.runningBundle(at: model.connectionAddress) == batch.client.appBundleID {
                    guard ContinuousClock.now < deadline else { throw MAAError.gameStartFailed }
                    try await Task.sleep(for: .milliseconds(200))
                }
            }
            // The completion callback precedes the core thread returning to its idle state.
            while !remaining.isEmpty, await handle.running {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        try send(.completed(completed))
    }
}
