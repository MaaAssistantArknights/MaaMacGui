#!/usr/bin/env python3
"""Observe production availability getters/subscriptions and the real run coordinator."""
from pathlib import Path
import re,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
model=(root/'MeoAsstMac/Model/MAAViewModel.swift').read_text()
bridge=(root/'MeoAsstMac/Model/NewViewModel.swift').read_text()
def block(source,pattern):
 m=re.search(pattern,source,re.M);assert m,pattern
 a=source.index('{',m.start());d=1;b=a+1
 while d:d+=(source[b]=='{')-(source[b]=='}');b+=1
 return source[m.start():b]
subscriptions='\n'.join(re.findall(r'        parent\.(?:\$\w+|objectWillChange)\.sink.*?        \.store\(in: &cancellables\)',bridge,re.S))
wiring=re.search(r'^        dailyRunCoordinator\.didChange = .*$',model,re.M)[0]
support='''import Foundation
import Combine
import Observation
struct DailyTask {}
@MainActor final class MAAViewModel: ObservableObject {
 enum Status { case idle, busy, pending }
 @Published var status = Status.idle
 @Published var isStartStopInFlight = false
 let dailyRunCoordinator = DailyRunCoordinator()
'''+block(model,r'^    var canStartTasks:')+'\n init() {\n'+wiring+'\n}\n}\n'+'''
@Observable final class NewModel {
 private let parent: MAAViewModel
 @ObservationIgnored private var cancellables = Set<AnyCancellable>()
'''+block(bridge,r'^    @MainActor var status:')+'\n'+block(bridge,r'^    @MainActor var canStartTasks:')+'''
 @MainActor init(parent: MAAViewModel) {
  self.parent=parent
'''+subscriptions+'''
 }
}
final class Flag: @unchecked Sendable {
 private let lock=NSLock();private var changed=false
 func set() { lock.lock();defer { lock.unlock() };changed=true }
 var value: Bool { lock.lock();defer { lock.unlock() };return changed }
}
@main struct Probe {
 @MainActor static func main() throws {
  let parent=MAAViewModel();let bridge=NewModel(parent:parent)
  let run=try parent.dailyRunCoordinator.begin(profileID:"A",origin:.manual)!
  precondition(!bridge.canStartTasks)
  let flag=Flag()
  withObservationTracking { _=bridge.canStartTasks } onChange: { flag.set() }
  _=try parent.dailyRunCoordinator.finish(run,outcome:.completed,cleanupSucceeded:true)
  precondition(bridge.canStartTasks && flag.value)
  precondition(parent.status == .idle && !parent.isStartStopInFlight)
  print("RunAvailabilityObservationTests: 3 production assertions passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='maa-run-observation-') as directory:
 p=Path(directory);(p/'Probe.swift').write_text(support)
 subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',str(p/'Probe.swift'),str(root/'MeoAsstMac/RunHooks/RunContext.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
