#!/usr/bin/env python3
"""Exercise the production completion callback waiter with a controllable Core."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'MeoAsstMac/Model/MAAViewModel.swift').read_text()

def declaration(pattern):
    match = re.search(pattern, source, re.M)
    assert match, pattern
    start = source.index('{', match.start())
    depth, end = 1, start + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[match.start():end]

members = '\n'.join(declaration(r'^    (?:private )?func ' + name + r'\b') for name in
                    ['resetStatus', 'finishDailyRunIfStopped'])
header = '''import Foundation
struct DailyTask {}
@MainActor final class Gate {
 var entered = false; var continuation: CheckedContinuation<Void, Never>?
 func wait() async { entered = true; await withCheckedContinuation { continuation = $0 } }
 func release() { continuation?.resume(); continuation = nil }
}
@MainActor final class Core {
 var value = true; var gate: Gate?
 var running: Bool { get async { if let g = gate { gate = nil; await g.wait() }; return value } }
}
@MainActor final class LogStore {
 var screencapCost: Int?; var lastScreencapWarningLevel = 0
 var hasPrintedFPSHighTip = false; var taskStartTime: Date?
 var sanityReport: Int?; var fightReport: Int?; var stoneUsedTimes = 0; var recruitConfirmTimes = 0
}
@MainActor final class Probe {
 enum Status { case idle, pending, busy }
 var status = Status.busy
 var taskCompletionGeneration: UInt64 = 0
 var dailyCompletionTask: Task<Void, Never>?
 var dailyFinishAttemptedRunID: UUID?
 var medicineUsedTimes = 0; var expiringMedicineUsedTimes = 0
 var logStore: LogStore? = LogStore()
 let dailyRunCoordinator: DailyRunCoordinator
 init(journalURL: URL? = nil) { dailyRunCoordinator = DailyRunCoordinator(journalURL: journalURL) }
 var dailyRunOutcome = DailyRunOutcome.completed
 var isStartStopInFlight = false
 var handle: Core? = Core()
 var canStartTasks: Bool { status == .idle && !isStartStopInFlight && dailyRunCoordinator.active == nil }
 var dailyRunTasks: [DailyTask]?
 var finishes = 0
 var errors: [String] = []
 func logError(verbatim: String) { errors.append(verbatim) }
 func stopCompletion() async { await finishDailyRunIfStopped(allowInFlight: true) }
 func observeFinishes() {
  dailyRunCoordinator.didChange = { [weak self] in
   guard let self, self.dailyRunCoordinator.active == nil else { return }
   self.finishes += 1
  }
 }
'''+members+'\n}\n'
main = '''
@main struct Main {
 @MainActor static func main() async throws {
  let p = Probe()
  p.observeFinishes()
  let first = try p.dailyRunCoordinator.begin(profileID: "A", origin: .schedule)!
  try p.dailyRunCoordinator.transition(.running, for: first)
  p.resetStatus()
  try await Task.sleep(for: .milliseconds(350))
  precondition(p.dailyRunCoordinator.active?.id == first && !p.canStartTasks, "callback before native stop must retain ownership")
  p.resetStatus() // Duplicate completion callbacks cannot finish twice.
  p.status = .busy // Another entry can reconcile the still-active run while waiting.
  p.handle?.value = false
  try await Task.sleep(for: .milliseconds(350))
  precondition(p.dailyRunCoordinator.active == nil && p.dailyRunCoordinator.lastTerminal?.outcome == .completed && p.canStartTasks && p.finishes == 1, "stopped core must reach completed and release start")
  let old = try p.dailyRunCoordinator.begin(profileID: "A", origin: .manual)!
  try p.dailyRunCoordinator.transition(.running, for: old)
  p.handle?.value = true; p.resetStatus()
  try await Task.sleep(for: .milliseconds(30))
  try p.dailyRunCoordinator.finish(old, outcome: .cancelled, cleanupSucceeded: true)
  p.finishes = 1 // Exclude the explicit simulated cancellation.
  let new = try p.dailyRunCoordinator.begin(profileID: "B", origin: .manual)!
  try p.dailyRunCoordinator.transition(.running, for: new)
  p.handle?.value = false
  try await Task.sleep(for: .milliseconds(350))
  precondition(p.dailyRunCoordinator.active?.id == new && p.finishes == 1, "old waiter must not finish a new run")
  p.isStartStopInFlight = true; p.resetStatus()
  try await Task.sleep(for: .milliseconds(350))
  precondition(p.dailyRunCoordinator.active?.id == new, "in-flight operation must retain ownership")
  p.isStartStopInFlight = false
  try await Task.sleep(for: .milliseconds(350))
  precondition(p.dailyRunCoordinator.active == nil && p.finishes == 2 && p.canStartTasks, "in-flight callback must be retried")
  let gated = try p.dailyRunCoordinator.begin(profileID: "C", origin: .schedule)!
  try p.dailyRunCoordinator.transition(.running, for: gated)
  let gate = Gate(); p.handle?.gate = gate; p.handle?.value = false; p.resetStatus()
  while !gate.entered { await Task.yield() }
  try p.dailyRunCoordinator.finish(gated, outcome: .cancelled, cleanupSucceeded: true)
  p.finishes = 2 // Exclude the explicit simulated cancellation.
  let latest = try p.dailyRunCoordinator.begin(profileID: "D", origin: .manual)!
  try p.dailyRunCoordinator.transition(.running, for: latest)
  gate.release()
  try await Task.sleep(for: .milliseconds(350))
  precondition(p.dailyRunCoordinator.active?.id == latest && p.finishes == 2, "suspended Core read cannot finish later run")
  try p.dailyRunCoordinator.finish(latest, outcome: .cancelled, cleanupSucceeded: true)
  p.finishes = 2 // Exclude the explicit simulated cancellation.
  let same = try p.dailyRunCoordinator.begin(profileID: "same", origin: .schedule)!
  try p.dailyRunCoordinator.transition(.running, for: same)
  let firstGate = Gate(); p.handle?.gate = firstGate; p.handle?.value = true; p.resetStatus()
  while !firstGate.entered { await Task.yield() }
  let secondGate = Gate(); p.handle?.gate = secondGate; p.resetStatus()
  while !secondGate.entered { await Task.yield() }
  p.handle?.value = false; firstGate.release()
  try await Task.sleep(for: .milliseconds(100))
  precondition(p.dailyRunCoordinator.active?.id == same && p.finishes == 2, "cancelled same-run waiter must not finish")
  secondGate.release()
  try await Task.sleep(for: .milliseconds(350))
  precondition(p.dailyRunCoordinator.active == nil && p.finishes == 3, "new waiter completes same run exactly once")
  let stopped = try p.dailyRunCoordinator.begin(profileID: "stop", origin: .manual)!
  try p.dailyRunCoordinator.transition(.stopping, for: stopped)
  let stopGate = Gate(); p.handle?.gate = stopGate; p.handle?.value = false
  let stop = Task { await p.stopCompletion() }
  while !stopGate.entered { await Task.yield() }
  stop.cancel(); stopGate.release(); await stop.value
  precondition(p.dailyRunCoordinator.active == nil && p.dailyRunCoordinator.lastTerminal?.id == stopped, "cancelled explicit stop must still finish cleanup")
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("maa-failing-journal-" + UUID().uuidString)
  let journal = dir.appendingPathComponent("journal.json")
  let failure = Probe(journalURL: journal)
  failure.observeFinishes()
  let failureID = try failure.dailyRunCoordinator.begin(profileID: "E", origin: .schedule)!
  try failure.dailyRunCoordinator.transition(.running, for: failureID)
  try FileManager.default.removeItem(at: dir)
  try Data("obstruction".utf8).write(to: dir)
  defer { try? FileManager.default.removeItem(at: dir) }
  failure.handle?.value = false
  failure.resetStatus()
  try await Task.sleep(for: .milliseconds(800))
  failure.resetStatus() // Duplicate callbacks must not retry a failed journal.
  try await Task.sleep(for: .milliseconds(350))
  precondition(failure.errors.count == 1 && failure.finishes == 1
   && failure.dailyRunCoordinator.active == nil && failure.dailyRunCoordinator.lastTerminal?.id == failureID
   && failure.status == .idle && failure.canStartTasks,
   "journal failure must attempt once, drop ownership and keep runs startable")
  print("Completion lifecycle: 10 production-path assertions passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='maa-completion-lifecycle-') as tmp:
    path = Path(tmp)
    (path / 'Probe.swift').write_text(header + main)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-module-cache-path', str(path / 'cache'), str(path / 'Probe.swift'),
                    str(root / 'MeoAsstMac/RunHooks/RunContext.swift'), '-o', str(path / 'probe')], check=True)
    subprocess.run([str(path / 'probe')], check=True, timeout=10)
