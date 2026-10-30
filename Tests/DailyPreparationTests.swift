import Foundation
@main struct DailyPreparationTests {
 @MainActor static func main() async {
  var count=0
  func check(_ value: Bool,_ message: String) { precondition(value,message);count+=1 }
  for failStop in [false,true] {
   let model=MAAViewModel();let core=model.handle!
   model.tasks=[.init(task:.fixture),.init(task:.fixture)];core.failAppendAt=2;core.failStop=failStop
   let result=await model.startDailyTasks()
   check(result == .failed && core.startCount == 0,"partial append must never start")
   check(model.taskIDMap.isEmpty,"failed preparation must clear ownership")
   check(model.dailyRunCoordinator.lastTerminal?.cleanupSucceeded == !failStop,"terminal must reflect native cleanup failure")
   if failStop { check(model.handle == nil,"failed cleanup must isolate handle") }
   else {
    check(core.queued.isEmpty,"stopped core must have an empty queue")
    core.failAppendAt=nil;model.tasks=[.init(task:.fixture)]
    check(await model.startDailyTasks() == .started && core.queued.count == 1,"next run must contain only newly appended tasks")
   }
  }
  let model=MAAViewModel();let gate=Gate();model.connectionGate=gate;model.dailyTaskProfile="A"
  let original=DailyTask(task:.fixture);model.tasks=[original]
  let pending=Task { await model.startDailyTasks() }
  for _ in 0..<10000 { if gate.entered { break };await Task.yield() }
  check(gate.entered,"connection suspension reached")
  model.dailyTaskProfile="B";model.tasks=[DailyTask(id:original.id,task:.startup(.init()),enabled:false)]
  gate.release();let result=await pending.value
  check(result == .started && model.handle?.queued.count == 1,"GUI clone switch cannot replace frozen tasks")
  check(model.dailyRunCoordinator.active?.profileID == "A" && model.dailyRunTasks?.first?.enabled == true,"frozen snapshot belongs to original profile")
  if case .fixture? = model.dailyTask(coreID:1) { count+=1 } else { fatalError("callback read must use frozen task, not clone") }
  let invalidated=MAAViewModel(); let recoveryGate=Gate(); invalidated.recoveryGate=recoveryGate
  invalidated.tasks=[.init(task:.fixture)]; var valid=true
  let interrupted=Task { await invalidated.startDailyTasks(recoverGame:true, recoveryCurrent:{ valid }) }
  for _ in 0..<10000 { if recoveryGate.entered { break }; await Task.yield() }
  check(recoveryGate.entered && invalidated.handle?.appendCount == 0, "recovery precedes every user append")
  valid=false; recoveryGate.release()
  check(await interrupted.value == .failed && invalidated.handle?.startCount == 0, "plan invalidation prevents user queue start")
  let quarantine=MAAViewModel(); let quarantineCore=quarantine.handle!
  quarantine.tasks=[.init(task:.fixture)]; quarantine.failRecoveryCleanup = true
  check(await quarantine.startDailyTasks(recoverGame:true) == .failed, "cleanup timeout reports failure")
  check(quarantine.handle === quarantineCore && quarantine.forceRecoveryInFlight && !quarantine.canStartTasks && quarantineCore.startCount == 0, "running recovery stays quarantined")
  quarantineCore.isRunning = false
  try? await Task.sleep(for:.milliseconds(350))
  check(quarantine.handle == nil && !quarantine.forceRecoveryInFlight && quarantine.dailyRunCoordinator.lastTerminal?.outcome == .failed, "idle observation releases quarantined handle and finishes failure")
  // Regression: a stale forceRecoveryInFlight after a failed recovery cleanup
  // (start/stop mutex already released) must not short-circuit a user stop.
  let stuckStop=MAAViewModel(); let stuckCore=stuckStop.handle!
  stuckStop.tasks=[.init(task:.fixture)]; stuckStop.failRecoveryCleanup = true
  check(await stuckStop.startDailyTasks(recoverGame:true) == .failed, "cleanup failure reports failure")
  check(stuckStop.forceRecoveryInFlight && !stuckStop.operationInFlightForTest && !stuckStop.canStartTasks && stuckCore.isRunning, "failed cleanup leaves stale recovery flag while the mutex is released")
  try? await stuckStop.stop()
  check(stuckCore.stopCount == 1 && !stuckCore.isRunning && stuckStop.handle == nil && !stuckStop.forceRecoveryInFlight, "stale recovery flag must not block a full stop of the stuck core")
  check(stuckStop.dailyRunCoordinator.active == nil && stuckStop.dailyRunCoordinator.lastTerminal?.outcome == .cancelled && stuckStop.canStartTasks, "stop finishes the cleanup-failure run as cancelled and unblocks start")
  // While recovery genuinely runs (inside startDailyTasks, mutex held), stop
  // must keep requesting an abort instead of stopping Core underneath it.
  let abortStop=MAAViewModel(); let abortCore=abortStop.handle!; let abortGate=Gate()
  abortStop.recoveryGate=abortGate; abortStop.tasks=[.init(task:.fixture)]; var abortValid=true
  let abortWork=Task { await abortStop.startDailyTasks(recoverGame:true, recoveryCurrent:{ abortValid }) }
  for _ in 0..<10000 { if abortGate.entered { break }; await Task.yield() }
  try? await abortStop.stop()
  check(abortCore.stopCount == 0 && abortStop.infos.contains("正在中止恢复中的强制开始任务，请稍候。") && abortStop.dailyRunCoordinator.active != nil, "stop during live recovery requests an abort instead of stopping Core")
  abortValid=false; abortGate.release()
  check(await abortWork.value == .failed && abortCore.stopCount == 1 && abortStop.dailyRunCoordinator.active == nil, "aborted recovery unwinds through cleanup and finishes like a cancellation")
  // Regression (r3 A-P2-1): in the tail window right after a failed recovery
  // cleanup (mutex still held, cleanupPending set, recovery loop already gone)
  // stop() must be refused honestly, never silently swallowed by the abort path.
  let tailStop=MAAViewModel(); let tailCore=tailStop.handle!
  let tailRecoveryGate=Gate(); let tailRunningGate=Gate()
  tailStop.tasks=[.init(task:.fixture)]; tailStop.failRecoveryCleanup = true
  tailStop.recoveryGate = tailRecoveryGate
  let tailWork=Task { await tailStop.startDailyTasks(recoverGame:true) }
  while !tailRecoveryGate.entered { await Task.yield() }
  // Suspend the catch path's `await handle?.running` query: the recovery loop
  // has thrown its terminal failure (cleanupPending set) while the start/stop
  // mutex is still held.
  tailCore.runningGate = tailRunningGate
  tailRecoveryGate.release()
  while !tailRunningGate.entered { await Task.yield() }
  var tailSwallowed=false
  do { try await tailStop.stop(); tailSwallowed=true } catch {}
  check(!tailSwallowed && tailCore.stopCount == 0 && !tailStop.infos.contains("正在中止恢复中的强制开始任务，请稍候。") && tailStop.forceRecoveryCleanupPending, "stop in the cleanup-failure tail window is refused honestly instead of being swallowed")
  tailRunningGate.release()
  check(await tailWork.value == .failed, "the refused stop leaves the failed recovery to unwind on its own")
  tailCore.isRunning = false
  try? await Task.sleep(for:.milliseconds(350))
  check(tailStop.handle == nil && !tailStop.forceRecoveryInFlight && tailStop.dailyRunCoordinator.active == nil, "idle observation still releases the quarantined core after the refused stop")
  // Regression (r3 A-P2-2): journal corruption + failed recovery cleanup + user
  // stop must digest the quarantine flags instead of leaking them into the next
  // run's message routing and completion filters.
  let abandonRoot=FileManager.default.temporaryDirectory.appendingPathComponent("maa-journal-abandon-\(UUID())")
  defer { try? FileManager.default.removeItem(at:abandonRoot) }
  let abandonModel=MAAViewModel(journalURL:abandonRoot.appendingPathComponent("run.json"))
  let abandonCore=abandonModel.handle!; let abandonGate=Gate()
  abandonModel.tasks=[.init(task:.fixture)]; abandonModel.failRecoveryCleanup = true; abandonModel.recoveryGate = abandonGate
  let abandonWork=Task { await abandonModel.startDailyTasks(recoverGame:true) }
  while !abandonGate.entered { await Task.yield() }
  try! FileManager.default.removeItem(at:abandonRoot)
  try! Data().write(to:abandonRoot)
  abandonGate.release()
  check(await abandonWork.value == .failed && abandonModel.forceRecoveryCleanupPending && abandonModel.forceRecoveryInFlight && abandonCore.isRunning, "compound journal+cleanup failure retains the quarantine flags")
  try? await abandonModel.stop()
  check(abandonCore.stopCount == 1 && abandonModel.handle == nil && !abandonModel.forceRecoveryCleanupPending && !abandonModel.forceRecoveryInFlight, "stop digests the quarantine flags after abandoning the run record")
  check(abandonModel.dailyRunCoordinator.active == nil && abandonModel.dailyRunCoordinator.lastTerminal?.outcome == .cancelled && abandonModel.canStartTasks, "the abandoned quarantine run finishes cancelled and unblocks start")
  let journalRoot=FileManager.default.temporaryDirectory.appendingPathComponent("maa-journal-fault-\(UUID())")
  defer { try? FileManager.default.removeItem(at:journalRoot) }
  let journalModel=MAAViewModel(journalURL:journalRoot.appendingPathComponent("run.json"))
  let journalCore=journalModel.handle!; let journalGate=Gate()
  journalModel.tasks=[.init(task:.fixture)]; journalModel.failRecoveryCleanup = true; journalModel.recoveryGate = journalGate
  let journalWork=Task { await journalModel.startDailyTasks(recoverGame:true) }
  while !journalGate.entered { await Task.yield() }
  try! FileManager.default.removeItem(at:journalRoot)
  try! Data().write(to:journalRoot)
  journalGate.release()
  check(await journalWork.value == .failed && journalModel.handle === journalCore && journalCore.isRunning && !journalModel.canStartTasks, "journal transition error retains live Core and blocks start")
  journalCore.isRunning = false
  try? await Task.sleep(for:.milliseconds(650))
  check(journalModel.handle == nil && journalModel.dailyRunCoordinator.active != nil && !journalModel.canStartTasks && !journalModel.forceRecoveryInFlight, "journal error releases only idle Core while run stays blocked")
  check(journalModel.errors.filter { $0.contains("每日运行日志：") }.count == 1, "journal failure logs once without a retry loop")
  let oldJournalRun=journalModel.dailyRunCoordinator.active!.id
  try! FileManager.default.removeItem(at:journalRoot)
  try! FileManager.default.createDirectory(at:journalRoot, withIntermediateDirectories:true)
  try! journalModel.dailyRunCoordinator.finish(oldJournalRun,outcome:.failed,cleanupSucceeded:true)
  journalModel.resetStatus(); journalModel.handle = Core(); journalModel.recoveryGate = nil
  let nextJournalCore=journalModel.handle!
  check(await journalModel.startDailyTasks(recoverGame:true) == .failed && !journalModel.canStartTasks, "next run cleanup retains occupancy")
  nextJournalCore.isRunning = false
  try? await Task.sleep(for:.milliseconds(350))
  check(journalModel.dailyRunCoordinator.active == nil && journalModel.dailyRunCoordinator.lastTerminal?.outcome == .failed, "prior journal failure cannot poison next run")
  let playcover=MAAViewModel(); playcover.touchMode = .MacPlayTools
  playcover.tasks=[.init(task:.startup(.init(start_game_enabled:true)))]
  check(await playcover.startDailyTasks(recoverGame:true) == .failed && playcover.startGameCount == 0 && playcover.handle?.appendCount == 0, "forced PlayCover auto-launch must fail before any device action")
  let scoped=MAAViewModel(); let scopedSnapshot=DailyRunSnapshot(profileID:scoped.dailyTaskProfile,tasks:[.init(task:.fixture)])
  let eligible=scoped.forceRecoveryEligibility(snapshot:scopedSnapshot)
  check(eligible(), "unchanged occurrence scope allows recovery")
  scoped.connectionAddress="127.0.0.1:5556"; check(!eligible(), "connection change invalidates captured occurrence")
  scoped.connectionAddress="127.0.0.1:5555"; scoped.clientChannel = .bilibili; check(!eligible(), "channel change invalidates captured occurrence")
  scoped.clientChannel = .official; scoped.dailyTaskProfile = "Other"; check(!eligible(), "profile change invalidates captured occurrence")
  let unsafe=MAAViewModel(); unsafe.touchMode = .MacPlayTools
  let unsafeSnapshot=DailyRunSnapshot(profileID:unsafe.dailyTaskProfile,tasks:[.init(task:.startup(.init(start_game_enabled:true)))])
  check(!unsafe.forceRecoveryEligibility(snapshot:unsafeSnapshot)(), "PlayCover auto-start is rejected at occurrence")
  print("DailyPreparationTests: \(count) production async assertions passed")
 }
}
