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
private enum ForcedRecoveryFailure: Error { case notReady, timedOut, resultStalled }
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
 var lastParams = ""
 var holdAppend = false; var appendGate: CheckedContinuation<Void,Never>?
 var running: Bool { get async { isRunning } }
 func appendTask(type: MAATaskType, params: String) async throws -> Int32 {
  appendCount += 1
  lastParams = params
  if holdAppend { await withCheckedContinuation { appendGate = $0 } }
  if type == .Custom { precondition(params.contains("Home") && !params.contains("StartUpBegin")) }
  return appendCount
 }
 func start() async throws { precondition(!isRunning, "must wait for Core idle before retry"); startCount += 1; isRunning = true; onStart?() }
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
 var forceRecoveryAbortRequested = false
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
  // Replay the captured stage-page outcome: StartUp ends there, Home-only fails,
  // and the resource quick-switch path reaches a separately recognized Home.
  let stage = Probe(); let stageCore = stage.handle!; stage.dailyRunCoordinator.active = .init(id:run)
  stageCore.onStart = { [weak stage, weak stageCore] in
   guard let stage, let stageCore, let state = stage.forceRecovery else { return }
   stage.forceRecovery?.chainStart(state.taskID)
   var success = true
   if state.requiresHome {
    let names = (try? JSONSerialization.jsonObject(with: Data(stageCore.lastParams.utf8)) as? [String:[String]])?["task_names"] ?? []
    success = names.contains("Home@QuickSwitch@ToHome@Open") && names.contains("Home@QuickSwitch@ToHome@Entry")
    if success {
     stage.forceRecovery?.subtask(chain:state.chain,taskID:state.taskID,name:"Open",algorithm:"MatchTemplate")
     stage.forceRecovery?.subtask(chain:state.chain,taskID:state.taskID,name:"Entry",algorithm:"MatchTemplate")
     stage.forceRecovery?.subtask(chain:state.chain,taskID:state.taskID,name:"Home",algorithm:"MatchTemplate")
    }
   }
   stage.forceRecovery?.chainFinish(state.taskID,success:success)
   stage.forceRecovery?.allFinished([state.taskID]); stageCore.isRunning = false
  }
  try await stage.recoverGameToHome(runID:run,isCurrent:{ true },timeout:2)
  precondition(stage.handle != nil && stageCore.stopped == 0, "stage page must navigate and verify home")
  // A real captured StartUp remained on a recognized result page after its click.
  // The next StartUp must wait for the old Core to stop before trying again.
  let stalled = Probe(); let stallCore = stalled.handle!; stalled.dailyRunCoordinator.active = .init(id:run)
  stallCore.stopDelay = .milliseconds(120)
  stallCore.onStart = { [weak stalled, weak stallCore] in
   guard let stalled, let stallCore, let state = stalled.forceRecovery else { return }
   stalled.forceRecovery?.chainStart(state.taskID)
   if stallCore.startCount == 1 {
    stalled.forceRecovery?.subtask(chain:"StartUp",taskID:0,name:"EndOfAction",algorithm:"MatchTemplate")
    stalled.forceRecovery?.resultSince = Date().addingTimeInterval(-60)
    return
   }
   precondition(state.requiresHome, "after stalled StartUp check home navigation before retrying StartUp")
   stalled.forceRecovery?.subtask(chain:state.chain,taskID:0,name:"Home",algorithm:"MatchTemplate")
   stalled.forceRecovery?.chainFinish(state.taskID,success:true); stalled.forceRecovery?.allFinished([state.taskID]); stallCore.isRunning = false
  }
  try await stalled.recoverGameToHome(runID:run,isCurrent:{ true },timeout:2)
  precondition(stallCore.stopped == 1 && stallCore.startCount == 2 && stalled.handle != nil, "stalled result retries once and verifies home")
  let fallback = Probe(); let fallbackCore = fallback.handle!; fallback.dailyRunCoordinator.active = .init(id:run)
  fallbackCore.onStart = { [weak fallback, weak fallbackCore] in
   guard let fallback, let fallbackCore, let state = fallback.forceRecovery else { return }
   fallback.forceRecovery?.chainStart(state.taskID)
   switch fallbackCore.startCount {
   case 1:
    fallback.forceRecovery?.subtask(chain:"StartUp",taskID:0,name:"EndOfAction",algorithm:"MatchTemplate")
    fallback.forceRecovery?.resultSince = Date().addingTimeInterval(-60)
   case 2:
    precondition(state.requiresHome, "first retry must attempt home navigation")
    fallback.forceRecovery?.chainFinish(state.taskID,success:false); fallback.forceRecovery?.allFinished([state.taskID])
   default:
    if state.requiresHome { fallback.forceRecovery?.subtask(chain:state.chain,taskID:0,name:"Home",algorithm:"MatchTemplate") }
    fallback.forceRecovery?.chainFinish(state.taskID,success:true); fallback.forceRecovery?.allFinished([state.taskID]); fallbackCore.isRunning = false
   }
  }
  try await fallback.recoverGameToHome(runID:run,isCurrent:{ true },timeout:2)
  precondition(fallbackCore.startCount == 4 && fallbackCore.stopped == 2 && fallback.handle != nil, "unrecognized page retries startup then requires verified home")
  var progressed = ForcedGameRecovery(taskID:42,chain:"StartUp",requiresHome:false)
  progressed.chainStart(42); progressed.subtask(chain:"StartUp",taskID:0,name:"EndOfAction",algorithm:"MatchTemplate")
  precondition(progressed.resultSince != nil)
  progressed.subtask(chain:"StartUp",taskID:0,name:"ClickCorner",algorithm:"JustReturn")
  precondition(progressed.resultSince != nil, "click alone does not prove the result page closed")
  progressed.subtask(chain:"StartUp",taskID:0,name:"LoadingIcon",algorithm:"MatchTemplate")
  precondition(progressed.resultSince == nil, "subsequent recognition clears stalled result")
  let retryStopFails = Probe(); let failedRetryCore = retryStopFails.handle!
  retryStopFails.dailyRunCoordinator.active = .init(id:run); failedRetryCore.stopFails = true
  failedRetryCore.onStart = { [weak retryStopFails] in
   guard let retryStopFails, let state = retryStopFails.forceRecovery else { return }
   retryStopFails.forceRecovery?.chainStart(state.taskID)
   retryStopFails.forceRecovery?.subtask(chain:"StartUp",taskID:0,name:"EndOfAction",algorithm:"MatchTemplate")
   retryStopFails.forceRecovery?.resultSince = Date().addingTimeInterval(-60)
  }
  do { try await retryStopFails.recoverGameToHome(runID:run,isCurrent:{ true },timeout:2); fatalError("failed retry stop must fail") }
  catch is ForcedRecoveryCleanupFailure {}
  precondition(failedRetryCore.startCount == 1 && retryStopFails.forceRecoveryCleanupPending && retryStopFails.handle === failedRetryCore, "failed stop never starts retry")
  let twice = Probe(); let twiceCore = twice.handle!; twice.dailyRunCoordinator.active = .init(id:run)
  twiceCore.onStart = { [weak twice] in
   guard let twice, let state = twice.forceRecovery else { return }
   twice.forceRecovery?.chainStart(state.taskID)
   if state.requiresHome {
    twice.forceRecovery?.chainFinish(state.taskID,success:false); twice.forceRecovery?.allFinished([state.taskID])
   } else {
    twice.forceRecovery?.subtask(chain:"StartUp",taskID:0,name:"EndOfAction",algorithm:"MatchTemplate")
    twice.forceRecovery?.resultSince = Date().addingTimeInterval(-60)
   }
  }
  do { try await twice.recoverGameToHome(runID:run,isCurrent:{ true },timeout:2); fatalError("unverified final home must fail") }
  catch ForcedRecoveryFailure.notReady {}
  precondition(twiceCore.startCount == 4 && twiceCore.stopped == 4 && twice.handle == nil, "final navigation remains bounded and fails closed")
  let second = Probe(); let secondCore = second.handle!; second.dailyRunCoordinator.active = .init(id:run)
  secondCore.onStart = { [weak second, weak secondCore] in
   guard let second, let secondCore, let state = second.forceRecovery else { return }
   second.forceRecovery?.chainStart(state.taskID)
   if !state.requiresHome {
    second.forceRecovery?.subtask(chain:"StartUp",taskID:0,name:"EndOfAction",algorithm:"MatchTemplate")
    second.forceRecovery?.resultSince = Date().addingTimeInterval(-60)
   } else if secondCore.startCount == 2 {
    second.forceRecovery?.chainFinish(state.taskID,success:false); second.forceRecovery?.allFinished([state.taskID])
   } else {
    second.forceRecovery?.subtask(chain:"Custom",taskID:0,name:"Home",algorithm:"MatchTemplate")
    second.forceRecovery?.chainFinish(state.taskID,success:true); second.forceRecovery?.allFinished([state.taskID]); secondCore.isRunning = false
   }
  }
  try await second.recoverGameToHome(runID:run,isCurrent:{ true },timeout:2)
  precondition(secondCore.startCount == 4 && secondCore.stopped == 3 && second.handle != nil, "second result stall checks and verifies home")
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
  let abort = Probe(); let abortCore = abort.handle!; abort.dailyRunCoordinator.active = .init(id:run)
  abortCore.onStart = { [weak abort] in
   guard let abort, let state = abort.forceRecovery else { return }
   abort.forceRecovery?.chainStart(state.taskID)
  }
  let abortWork = Task { try await abort.recoverGameToHome(runID:run,isCurrent:{ true },timeout:2) }
  while abortCore.startCount == 0 { await Task.yield() }
  abort.forceRecoveryAbortRequested = true
  do { try await abortWork.value; fatalError("user abort must not succeed") } catch is CancellationError {}
  precondition(abortCore.stopped == 1 && !abortCore.isRunning && abort.handle == nil, "user abort during recovery cleans up like a cancellation")
  print("PASS: recovery success, missing home, timeout, cancellation, cleanup failure, delayed/stuck idle, scope change during append and user abort")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='maa-force-recovery-') as tmp:
 path=Path(tmp); (path/'Probe.swift').write_text(pre+main)
 subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-module-cache-path',str(path/'cache'),str(path/'Probe.swift'),'-o',str(path/'test')],check=True)
 subprocess.run([str(path/'test')],check=True,timeout=10)
