import Foundation
import Darwin

struct HookResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let stdoutTruncated: Bool
    let stderrTruncated: Bool
    let timedOut: Bool
    let cancelled: Bool
    var succeeded: Bool { exitCode == 0 && !timedOut && !cancelled }
}

/// Owns one POSIX process group; cancellation never targets the application group.
private final class HookProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var cancelled = false
    private var timedOut = false
    private var finished = false
    private var terminationDeadline: DispatchTime?

    func install(_ child: pid_t) {
        lock.lock()
        pid = child
        let shouldStop = cancelled || timedOut
        lock.unlock()
        if shouldStop { terminate() }
    }
    func cancel(timeout: Bool = false) {
        lock.lock()
        if timeout { timedOut = true } else { cancelled = true }
        lock.unlock()
        terminate()
    }
    private func terminate() {
        lock.lock()
        guard !finished, pid > 0, terminationDeadline == nil else { lock.unlock(); return }
        let deadline = DispatchTime.now() + 2
        terminationDeadline = deadline
        kill(-pid, SIGTERM)
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: deadline) { self.signalGroup(SIGKILL) }
    }
    private func signalGroup(_ signal: Int32) {
        lock.lock(); defer { lock.unlock() }
        guard !finished, pid > 0 else { return }
        kill(-pid, signal)
    }
    func finishGroup(ownsUnreapedChild: Bool) -> (Bool, Bool) {
        while true {
            lock.lock()
            let now = DispatchTime.now().uptimeNanoseconds
            if ownsUnreapedChild, let deadline = terminationDeadline, deadline.uptimeNanoseconds > now {
                let remaining = deadline.uptimeNanoseconds - now
                lock.unlock()
                // The leader can exit before its children finish TERM cleanup.
                // This runs on the process worker, never the main actor. Keep the
                // zombie leader/PID reserved for the group's full grace period.
                Thread.sleep(forTimeInterval: Double(remaining) / 1_000_000_000)
                continue
            }
            // Final group signal still precedes waitpid, excluding PGID reuse.
            if ownsUnreapedChild, pid > 0 { kill(-pid, SIGKILL) }
            finished = true
            let result = (timedOut, cancelled)
            lock.unlock()
            return result
        }
    }
}

/// Drains both streams concurrently, retaining at most 32 KiB of each.
struct HookRunner {
    static let outputLimit = 32 * 1024
    /// How long pipe EOF is still awaited after the leader was reaped. A
    /// descendant that escaped the process group via setsid survives every
    /// kill(-pid, ...) and can hold the pipes open forever, so draining must
    /// stay bounded: after this grace the partial output is kept and reading
    /// is abandoned (the foreground command has already finished).
    static let drainGrace: TimeInterval = 5
    /// Longest single poll(2) wait inside a drain; tightening the read deadline
    /// takes effect within one slice.
    static let pollSliceMs = 250

    func run(command: HookCommand, context: RunContext, outcome: DailyRunOutcome?, adbPath: String,
             workingDirectory: URL, timeout: TimeInterval = 60) async throws -> HookResult {
        guard !command.arguments.contains(where: { $0.contains("\0") }), !context.profileID.contains("\0"),
              !adbPath.contains("\0") else {
            throw HookError.invalidExecutable
        }
        let url = try command.resolve()
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard command.shellScript ? FileManager.default.isReadableFile(atPath: url.path)
                : FileManager.default.isExecutableFile(atPath: url.path) else { throw HookError.invalidExecutable }
        let executable = command.shellScript ? "/bin/zsh" : url.path
        let arguments = command.shellScript ? ["-f", url.path] + command.arguments : command.arguments
        let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "MAA_RUN_ID": context.id.uuidString,
                           "MAA_PROFILE_ID": context.profileID, "MAA_RUN_ORIGIN": context.origin.rawValue,
                           "MAA_RUN_RESULT": outcome?.rawValue ?? "preparing", "MAA_ADB_PATH": adbPath]
        let control = HookProcess()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try Self.execute(executable: executable, arguments: arguments,
                                                      environment: environment, directory: workingDirectory,
                                                      timeout: min(max(timeout, 1), 300), control: control)
                        continuation.resume(returning: result)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { control.cancel() })
    }

    private static func execute(executable: String, arguments: [String], environment: [String: String],
                                directory: URL, timeout: TimeInterval, control: HookProcess) throws -> HookResult {
        var out: [Int32] = [0, 0], err: [Int32] = [0, 0]
        guard pipe(&out) == 0 else { throw HookError.launch(errno) }
        guard pipe(&err) == 0 else { close(out[0]); close(out[1]); throw HookError.launch(errno) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, err[1], STDERR_FILENO)
        for fd in out + err { posix_spawn_file_actions_addclose(&actions, fd) }
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&actions, directory.path)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        var argv = ([executable] + arguments).map { strdup($0) } + [nil]
        var envp = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var child: pid_t = 0
        let code = posix_spawn(&child, executable, &actions, &attributes, &argv, &envp)
        close(out[1]); close(err[1])
        guard code == 0 else { close(out[0]); close(err[0]); throw HookError.launch(code) }
        control.install(child)
        let expiry = DispatchWorkItem { control.cancel(timeout: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: expiry)
        // Absolute backstop: even if the reap path below never tightens it, both
        // drains stop once the timeout, TERM grace and drain grace have elapsed.
        let backstop = DispatchTime.now() + timeout + Self.drainGrace + 2
        let stdout = StreamDrain(fd: out[0], deadline: backstop), stderr = StreamDrain(fd: err[0], deadline: backstop)
        let drains = DispatchGroup()
        for stream in [stdout, stderr] {
            drains.enter()
            DispatchQueue.global().async { stream.readAll(); drains.leave() }
        }
        var info = siginfo_t()
        var waited: Int32
        repeat { waited = waitid(P_PID, id_t(child), &info, WEXITED | WNOWAIT) } while waited == -1 && errno == EINTR
        expiry.cancel()
        let flags = control.finishGroup(ownsUnreapedChild: waited == 0)
        var status: Int32 = 0
        while waitpid(child, &status, 0) == -1 && errno == EINTR {}
        // The leader is reaped, so the foreground command has finished. A
        // setsid descendant escapes every group signal above while keeping the
        // pipe write ends open; give EOF a short grace, then abandon the drain.
        let pipeGrace = DispatchTime.now() + Self.drainGrace
        stdout.stopReadingNoLaterThan(pipeGrace)
        stderr.stopReadingNoLaterThan(pipeGrace)
        drains.wait()
        let exitCode = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return HookResult(exitCode: exitCode, stdout: String(decoding: stdout.data, as: UTF8.self),
                          stderr: String(decoding: stderr.data, as: UTF8.self), stdoutTruncated: stdout.truncated,
                          stderrTruncated: stderr.truncated, timedOut: flags.0, cancelled: flags.1)
    }
}

/// Reads one pipe until EOF or until an absolute deadline passes, retaining at
/// most 32 KiB. poll() replaces a plain blocking read so a descendant holding
/// the write end open forever cannot pin the reader thread as well.
private final class StreamDrain: @unchecked Sendable {
    let fd: Int32
    private let lock = NSLock()
    private var store = Data()
    private var overLimit = false
    private var abandoned = false
    private var deadline: DispatchTime

    init(fd: Int32, deadline: DispatchTime) {
        self.fd = fd
        self.deadline = deadline
    }

    /// Only ever tightens the read deadline, never extends it.
    func stopReadingNoLaterThan(_ limit: DispatchTime) {
        lock.lock()
        if limit.uptimeNanoseconds < deadline.uptimeNanoseconds { deadline = limit }
        lock.unlock()
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return store
    }

    /// Incomplete output: past the size limit, or reading was abandoned at the
    /// deadline with a pipe holder still alive.
    var truncated: Bool {
        lock.lock(); defer { lock.unlock() }
        return overLimit || abandoned
    }

    func readAll() {
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 8192)
        var watched = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        while true {
            lock.lock(); let stopAt = deadline; lock.unlock()
            let now = DispatchTime.now()
            if now.uptimeNanoseconds >= stopAt.uptimeNanoseconds {
                lock.lock(); abandoned = true; lock.unlock()
                return
            }
            // Sliced so a deadline tightened by the reaper (or any other thread)
            // is noticed within one slice; a single full-window poll would sleep
            // through it until the fd itself wakes up.
            let millis = Int32(min((stopAt.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000_000 + 1,
                                   UInt64(HookRunner.pollSliceMs)))
            let ready = poll(&watched, 1, millis)
            if ready == -1 {
                if errno == EINTR { continue }
                return
            }
            if ready == 0 { continue }  // Timeout: the deadline is re-checked above.
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return }
            lock.lock()
            let remaining = HookRunner.outputLimit - store.count
            if count > remaining { overLimit = true }
            if remaining > 0 { store.append(contentsOf: buffer.prefix(min(count, remaining))) }
            lock.unlock()
        }
    }
}
