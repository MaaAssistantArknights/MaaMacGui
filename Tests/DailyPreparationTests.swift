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
  print("DailyPreparationTests: \(count) production async assertions passed")
 }
}
