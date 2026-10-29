#!/usr/bin/env python3
"""Exercise the actual isolated recovery method with controlled Core callbacks."""
from pathlib import Path
import re, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
model = (root/'MeoAsstMac/Model/MAAViewModel.swift').read_text()
schedule = (root/'MeoAsstMac/Scheduling/ScheduleHandoff.swift').read_text()
def declaration(source, pattern):
 m = re.search(pattern, source, re.M); assert m, pattern
 start = source.index('{', m.start()); depth, end = 1, start+1
 while depth:
  depth += (source[end] == '{') - (source[end] == '}'); end += 1
 return source[m.start():end]
method = declaration(model, r'^    private func recoverGameToHome\b') + '\n' + declaration(model, r'^    private func runRecoveryTask\b')
state = declaration(schedule, r'^struct ForcedGameRecovery\b')
pre = '''import Foundation
''' + state + '''
private enum ForcedRecoveryFailure: Error { case notReady, timedOut }
private struct ForcedRecoveryCleanupFailure: Error {}
extension Dictionary where Key == String, Value == [String] {
 func jsonString() throws -> String { String(data: try JSONSerialization.data(withJSONObject:self), encoding:.utf8)! }
}
enum MAATaskType { case Custom, StartUp }
enum Channel { case official }
struct StartupConfiguration { var client_type: Channel; var start_game_enabled: Bool; var account_name: String; var params: Self { self }; func jsonString() throws -> String { precondition(!start_game_enabled && account_name.isEmpty); return "{}" } }
@MainActor final class Coordinator { struct Active { var id: UUID }; var active: Active? }
@MainActor final class Core {
 var isRunning = false; var stopFails = false; var stopped = 0
 var stopDelay: Duration?
 var onStart: (() -> Void)?; var appendCount: Int32 = 0; var startCount = 0
 var holdAppend = false; var appendGate: CheckedContinuation<Void,Never>?
 var running: Bool { get async { isRunning } }
 func appendTask(type: MAATaskType, params: String) async throws -> Int32 {
  appendCount += 1
  if holdAppend { await withCheckedContinuation { appendGate = $0 } }
  if type == .Custom { precondition(params.contains("Home") && !params.contains("StartUpBegin")) }
  return appendCount
 }
 func start() async throws { startCount += 1; isRunning = true; onStart?() }
 func stop() async throws {
  stopped += 1; if stopFails { throw NSError(domain:"test",code:1) }
  if let delay = stopDelay { Task { try? await Task.sleep(for:delay); isRunning = false } }
  else { isRunning = false }
 }
}
typealias MAAHandle = Core
@MainActor final class Probe {
 var clientChannel = Channel.official
 let dailyRunCoordinator = Coordinator()
 var handle: Core? = Core()
 var forceRecovery: ForcedGameRecovery?
 var forceRecoveryCleanupPending = false
 var messageTask: Task<Void,Never>?
''' + method.replace('private func','func',1) + '''
}
'''
main = '''
@main struct Main {
 @MainActor static func main() async throws {
  let run = UUID(); let ok = Probe(); let core = ok.handle!
  ok.dailyRunCoordinator.active = .init(id:run)
  core.onStart = { [weak ok, weak core] in
   guard let ok, let core else { return }
   guard let state = ok.forceRecovery else { return }
   ok.forceRecovery?.chainStart(state.taskID)
   if state.requiresHome { ok.forceRecovery?.subtask(chain:state.chain,taskID:0,name:"Home",algorithm:"MatchTemplate") }
   ok.forceRecovery?.chainFinish(state.taskID,success:true)
   ok.forceRecovery?.allFinished([state.taskID])
   Task { try? await Task.sleep(for:.milliseconds(30)); core.isRunning = false }
  }
  try await ok.recoverGameToHome(runID:run,isCurrent:{ true },timeout:2)
  precondition(ok.handle != nil && ok.forceRecovery == nil && core.stopped == 0)
  let notHome = Probe(); let bad = notHome.handle!; notHome.dailyRunCoordinator.active = .init(id:run)
  bad.onStart = { [weak notHome] in
   guard let state = notHome?.forceRecovery else { return }
   notHome?.forceRecovery?.chainStart(state.taskID)
   notHome?.forceRecovery?.chainFinish(state.taskID,success:true)
   notHome?.forceRecovery?.allFinished([state.taskID])
   bad.isRunning = false
  }
  do { try await notHome.recoverGameToHome(runID:run,isCurrent:{ true },timeout:1); fatalError("no home must fail") }
  catch ForcedRecoveryFailure.notReady {}
  precondition(notHome.handle == nil && bad.stopped == 1)
  let timed = Probe(); let timedCore = timed.handle!; timed.dailyRunCoordinator.active = .init(id:run)
  do { try await timed.recoverGameToHome(runID:run,isCurrent:{ true },timeout:0.01); fatalError("timeout must fail") }
  catch ForcedRecoveryFailure.timedOut {}
  precondition(timed.handle == nil && timedCore.stopped == 1)
  let failedStop = Probe(); let broken = failedStop.handle!; broken.stopFails = true; failedStop.dailyRunCoordinator.active = .init(id:run)
  do { try await failedStop.recoverGameToHome(runID:run,isCurrent:{ true },timeout:0.01); fatalError("cleanup failure must fail closed") }
  catch is ForcedRecoveryCleanupFailure {}
  precondition(failedStop.handle === broken && failedStop.forceRecoveryCleanupPending && broken.stopped == 1)
  let cancel = Probe(); let cancellingCore = cancel.handle!; cancel.dailyRunCoordinator.active = .init(id:run)
  let work = Task { try await cancel.recoverGameToHome(runID:run,isCurrent:{ true },timeout:2) }
  try await Task.sleep(for:.milliseconds(30)); work.cancel()
  do { try await work.value; fatalError("cancel must not succeed") } catch is CancellationError {}
  precondition(cancel.handle == nil && cancellingCore.stopped == 1)
  let delayed = Probe(); let delayedCore = delayed.handle!; delayed.dailyRunCoordinator.active = .init(id:run)
  delayedCore.stopDelay = .milliseconds(120)
  let delayedWork = Task { try await delayed.recoverGameToHome(runID:run,isCurrent:{ true },timeout:2,cleanupTimeout:1) }
  while delayedCore.startCount == 0 { await Task.yield() }
  delayedWork.cancel()
  do { try await delayedWork.value; fatalError("cancel must not succeed") } catch is CancellationError {}
  precondition(delayedCore.stopped == 1 && !delayedCore.isRunning && delayed.handle == nil && !delayed.forceRecoveryCleanupPending)
  let stuck = Probe(); let stuckCore = stuck.handle!; stuck.dailyRunCoordinator.active = .init(id:run)
  stuckCore.stopDelay = .seconds(1)
  do { try await stuck.recoverGameToHome(runID:run,isCurrent:{ true },timeout:0.01,cleanupTimeout:0.1); fatalError("stuck cleanup must fail") }
  catch is ForcedRecoveryCleanupFailure {}
  precondition(stuckCore.isRunning && stuck.handle === stuckCore && stuck.forceRecoveryCleanupPending && stuckCore.startCount == 1)
  let changed = Probe(); let changedCore = changed.handle!; changed.dailyRunCoordinator.active = .init(id:run)
  changedCore.holdAppend = true
  var current = true
  let changedWork = Task { try await changed.recoverGameToHome(runID:run,isCurrent:{ current },timeout:2) }
  while changedCore.appendGate == nil { await Task.yield() }
  current = false; changedCore.appendGate?.resume(); changedCore.appendGate = nil
  do { try await changedWork.value; fatalError("scope change must cancel") } catch is CancellationError {}
  precondition(changedCore.startCount == 0 && changedCore.stopped == 1 && changed.handle == nil)
  print("PASS: recovery success, missing home, timeout, cancellation, cleanup failure, delayed/stuck idle and scope change during append")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='maa-force-recovery-') as tmp:
 path=Path(tmp); (path/'Probe.swift').write_text(pre+main)
 subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-module-cache-path',str(path/'cache'),str(path/'Probe.swift'),'-o',str(path/'test')],check=True)
 subprocess.run([str(path/'test')],check=True,timeout=10)
