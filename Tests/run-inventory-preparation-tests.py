#!/usr/bin/env python3
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'MeoAsstMac/Model/MAAViewModel.swift').read_text()
def anchor(source,marker):
 # The signature string is the test contract with the production source.
 try:return source.index(marker)
 except ValueError:raise SystemExit(f"FAIL: production source anchor not found: {marker!r}")
a=anchor(source,'    private func startTasks() async throws {');start=source.index('{',a);depth=0
for b in range(start,len(source)):
    if source[b]=='{':depth+=1
    elif source[b]=='}':
        depth-=1
        if depth==0:break
method=source[a:b+1].replace('private func','func',1)
header='''import Foundation
protocol MAATaskConfiguration: Codable, Hashable, Sendable {}
extension MAATaskConfiguration { init() { self = try! JSONDecoder().decode(Self.self, from: Data("{}".utf8)) } }
enum MAATaskType { case Fight; var description: String { "Fight" } }
struct Startup: Sendable { var client_type = "CN"; var start_game_enabled = false }
struct Closedown: Sendable { var client_type = "CN" }
enum MAATask: Sendable { case fight(FightConfiguration), startup(Startup), closedown(Closedown), other }
struct DailyTask: Sendable { let id: UUID; let task: MAATask; var enabled: Bool }
enum MAAError: Error { case gameStartFailed }
enum Touch { case maatouch, MacPlayTools }
actor FakeHandle {
 var connected = true
 var running = false
 var queue: [MAATask] = []
 var started: [[MAATask]] = []
 var stopCalls = 0
 var onAppend: (@MainActor () -> Void)?
 func setOnAppend(_ action: (@MainActor () -> Void)?) { onAppend = action }
 func appendTask(_ task: MAATask) async throws -> Int32 { queue.append(task); await onAppend?(); return Int32(queue.count) }
 func stop() throws { stopCalls += 1; queue.removeAll(); running = false }
 var cleanStoppedQueue: Bool { stopCalls == 1 && queue.isEmpty }
 var untouched: Bool { started.isEmpty && queue.isEmpty }
 func start() { started.append(queue); queue.removeAll(); running = true }
}
@MainActor final class Probe {
 enum Status { case idle, pending, busy }
 enum TaskStatus { case success }
 var status = Status.idle
 var touchMode = Touch.maatouch
 var clientChannel = "CN"
 var tasks: [DailyTask] = []
 var handle: FakeHandle? = FakeHandle()
 var messageTask: Task<Void,Never>?
 var taskIDMap: [Int32: UUID] = [:]
 var taskStatus: [UUID: TaskStatus] = [:]
 var inventory = InventorySnapshotAdapter()
 var inventoryScope = InventoryScope(connection: "adb", server: "CN", profile: "Default")
 var currentInventorySnapshot: InventorySnapshot? { inventory.usableSnapshot(scope: inventoryScope) }
 var logs: [String] = []
 var connectionRequests = 0
 func invalidateInventory() { inventory.invalidate() }
 func logInfo(_ message: String) { logs.append(message) }
 func logTrace(verbatim message: String) { logs.append(message) }
 func handleEarlyReturn(backTo: Status) { if status == .pending { status = backTo } }
 func ensureHandle(requireConnect: Bool = true) async throws { taskIDMap.removeAll(); taskStatus.removeAll(); if requireConnect { connectionRequests += 1; invalidateInventory() } }
 func startGame(client: String) async -> Bool { true }
 func startCoreTasks(recordDailyTaskStart: Bool) async throws { await handle?.start(); status = .busy }
'''+method+'''\n}
'''
main='''@main struct Main {
 @MainActor static func main() async throws {
  var checks = 0
  func check(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
  FightConfiguration.dropItems = [("30012", DropItem(classifyType: "MATERIAL", description: nil, icon: "", name: "Material", sortId: 1, usage: nil))]
  var config = FightConfiguration(); config.inventoryTarget = InventoryTarget(itemID: "30012", quantity: 10)
  func make(_ stock: Int) throws -> Probe {
   let model = Probe(); model.tasks = [.init(id: UUID(), task: .fight(config), enabled: true)]
   try model.inventory.capture(items: ["30012": stock], complete: true, scope: model.inventoryScope)
   return model
  }
  let changing = try make(5); let core = changing.handle!
  await core.setOnAppend { changing.inventoryScope = InventoryScope(connection: "other", server: "CN", profile: "Default"); changing.invalidateInventory() }
  do { try await changing.startTasks(); preconditionFailure("stale scope must reject") } catch { checks += 1 }
  check(await core.started.isEmpty, "scope change never starts Core")
  check(await core.cleanStoppedQueue, "stale preparation clears all appended tasks")
  check(changing.inventory.snapshot == nil && changing.taskIDMap.isEmpty, "stale ownership released")
  await core.setOnAppend(nil)
  try changing.inventory.capture(items: ["30012": 8], complete: true, scope: changing.inventoryScope)
  try await changing.startTasks()
  let batches = await core.started
  check(batches.count == 1 && batches[0].count == 1, "new run contains no abandoned prior task")
  if case .fight(let prepared) = batches[0][0] { check(prepared.drops == ["30012": 2] && prepared.inventoryTarget == nil, "frozen difference sent to Core") }
  else { preconditionFailure("Fight expected") }
  let switching = try make(5); let switchingCore = switching.handle!
  await switchingCore.setOnAppend { switching.invalidateInventory() }
  do { try await switching.startTasks(); preconditionFailure("account switch must reject frozen plan even with same scope") } catch { checks += 1 }
  check(await switchingCore.started.isEmpty, "account switch while appending never starts Core")
  check(await switchingCore.cleanStoppedQueue, "account switch clears already appended tasks")
  check(switching.inventory.snapshot == nil && switching.taskIDMap.isEmpty, "account switch releases stale ownership")
  let cancelled = try make(5); let cancelledCore = cancelled.handle!
  await cancelledCore.setOnAppend { withUnsafeCurrentTask { $0?.cancel() } }
  let task = Task { try await cancelled.startTasks() }
  do { try await task.value; preconditionFailure("cancel must reject") } catch is CancellationError { checks += 1 }
  check(await cancelledCore.started.isEmpty, "cancel after append does not start")
  check(await cancelledCore.cleanStoppedQueue, "cancel after append removes stale queue")
  let reached = try make(10); let reachedCore = reached.handle!
  try await reached.startTasks()
  let skippedBatches = await reachedCore.started
  check(skippedBatches.count == 1 && skippedBatches[0].isEmpty, "reached target never appends drops=0 Fight")
  check(reached.logs.contains("Inventory.AlreadyReached"), "reached target is visible after ensureHandle")
  let missing = Probe(); missing.tasks = [.init(id: UUID(), task: .fight(config), enabled: true)]
  let missingCore = missing.handle!
  do { try await missing.startTasks(); preconditionFailure("missing snapshot must reject") } catch { checks += 1 }
  check(await missingCore.untouched, "missing snapshot has no Core side effects")
  let ordered = try make(5); let orderedCore = ordered.handle!
  ordered.tasks = [.init(id: UUID(), task: .startup(Startup()), enabled: true), .init(id: UUID(), task: .fight(config), enabled: true)]
  do { try await ordered.startTasks(); preconditionFailure("target behind another enabled task must reject") } catch InventoryTargetError.unsafeOrder { checks += 1 }
  check(await orderedCore.untouched, "unsafe queue order never reaches Core")
  let doubled = try make(5); let doubledCore = doubled.handle!
  doubled.tasks = [.init(id: UUID(), task: .fight(config), enabled: true), .init(id: UUID(), task: .fight(config), enabled: true)]
  do { try await doubled.startTasks(); preconditionFailure("multiple targets must reject") } catch InventoryTargetError.multipleTargets { checks += 1 }
  check(await doubledCore.untouched, "multiple targets never reach Core")
  var relaunch = Startup(); relaunch.start_game_enabled = true
  let relaunching = try make(5); let relaunchingCore = relaunching.handle!
  relaunching.tasks = [.init(id: UUID(), task: .fight(config), enabled: true), .init(id: UUID(), task: .startup(relaunch), enabled: true)]
  do { try await relaunching.startTasks(); preconditionFailure("enabled relaunch after recognition must reject") } catch InventoryTargetError.unsafeOrder { checks += 1 }
  check(await relaunchingCore.untouched, "relaunch after recognition never reaches Core")
  var normal = FightConfiguration(); normal.drops = ["30012": 3]
  let ordinary = Probe(); ordinary.tasks = [.init(id: UUID(), task: .fight(normal), enabled: true)]
  try await ordinary.startTasks(); let normalBatches = await ordinary.handle!.started
  if case .fight(let actual) = normalBatches[0][0] { check(actual.drops == ["30012": 3], "normal drop mode preserved") }
  print("Inventory preparation: \\(checks) production assertions passed")
 }
}
'''
with tempfile.TemporaryDirectory() as temporary:
    path=Path(temporary);(path/'Probe.swift').write_text(header+main)
    subprocess.run(['swiftc','-parse-as-library',str(root/'MeoAsstMac/Model/InventoryTarget.swift'),str(root/'MeoAsstMac/Task Configurations/FightConfiguration.swift'),str(path/'Probe.swift'),'-o',str(path/'probe')],check=True)
    subprocess.run([str(path/'probe')],check=True)
