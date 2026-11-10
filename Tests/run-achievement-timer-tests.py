#!/usr/bin/env python3
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'MeoAsstMac/Utils/TaskTimerManager.swift').read_text()
start=source.index('    private func startDailyTaskIfNeeded(')
brace=source.index('{',start);depth=0
for end in range(brace,len(source)):
    if source[end]=='{':depth+=1
    elif source[end]=='}':
        depth-=1
        if depth==0:break
method=source[start:end+1].replace('private func','func',1)
support='''import Foundation
enum DailyRunOrigin { case manual, schedule, hotkey }
@MainActor final class MAAViewModel {
    enum Status { case idle, busy }
    enum Result { case started, skipped, failed }
    struct DailyTaskTimer { let id = UUID(); var uniqueKey: String { id.uuidString } }
    var status = Status.idle
    var origins: [DailyRunOrigin] = []
    var result = Result.started
    func startDailyTasks(origin: DailyRunOrigin = .manual) async -> Result { origins.append(origin); return result }
}
@MainActor final class TimerProbe {
    weak var viewModel: MAAViewModel?
'''+method+'''\n}
@main struct Probe {
 @MainActor static func main() async throws {
  let model = MAAViewModel(); let probe = TimerProbe(); probe.viewModel = model
  let config = MAAViewModel.DailyTaskTimer()
  for result in [MAAViewModel.Result.started, .skipped, .failed] {
   model.result = result; probe.startDailyTaskIfNeeded(config: config)
   for _ in 0..<20 { await Task.yield() }
  }
  precondition(model.origins == [.schedule, .schedule, .schedule], "production timer must identify scheduled origin in every result")
  model.status = .busy; probe.startDailyTaskIfNeeded(config: config)
  for _ in 0..<20 { await Task.yield() }
  precondition(model.origins.count == 3, "busy timer must not start")
  probe.viewModel = nil; probe.startDailyTaskIfNeeded(config: config)
  for _ in 0..<20 { await Task.yield() }
  precondition(model.origins.count == 3, "missing model must not start")
  print("Achievement timer: 3 production entry assertions passed")
 }
}
'''
with tempfile.TemporaryDirectory() as temporary:
    path=Path(temporary);(path/'Probe.swift').write_text(support)
    subprocess.run(['swiftc','-parse-as-library',str(path/'Probe.swift'),'-o',str(path/'probe')],check=True)
    subprocess.run([str(path/'probe')],check=True)
