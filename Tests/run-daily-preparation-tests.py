#!/usr/bin/env python3
"""Exercise production preparation/lifecycle across async Core boundaries; no game or app container."""
from pathlib import Path
import os,re,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source_root=Path(os.environ.get('MAA_TEST_SOURCE_ROOT',root))
model=(source_root/'MeoAsstMac/Model/MAAViewModel.swift').read_text()
message=(source_root/'MeoAsstMac/Core/MaaMessage.swift').read_text()
def declaration(source,pattern):
 match=re.search(pattern,source,re.M);assert match,pattern
 start=source.index('{',match.start());depth=1;end=start+1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[match.start():end]
parts=[declaration(model,r'^    enum Status:'),declaration(model,r'^    enum TaskStartResult:')]
for pattern in [r'^    private var dailyCompletionTask: .*$', r'^    private var dailyFinishAttemptedRunID: .*$', r'^    @Published private\(set\) var status = .*$',r'^    @Published private\(set\) var isStartStopInFlight = .*$',r'^    private var taskCompletionGeneration = .*$']:
 parts.append(re.search(pattern,model,re.M)[0])
for name in ['canStartTasks','beginTaskOperation','handleEarlyReturn','startCoreTasks','startDailyTasks','startTasks','stop','finishDailyRunIfStopped','reconcileDailyRunStatus','discardPreparedDailyTasks','resetStatus','waitForDailyRunCompletion','forceRecoveryEligibility']:
 pattern=rf'^    (?:private )?(?:func|var) {name}\b'
 if re.search(pattern,model,re.M):parts.append(declaration(model,pattern))
for name in ['dailyTask','taskID']:parts.append(declaration(message,rf'^    (?:private )?func {name}\('))
support=(root/'Tests/DailyPreparationTestSupport.swift').read_text().replace('// PRODUCTION_MODEL_MEMBERS','\n'.join(parts)).replace('// PRODUCTION_CORE_RUNNING_GUARD',declaration(model,r'^        guard await handle\?\.running == false else'))
tasks=(source_root/'MeoAsstMac/Model/MAATask.swift').read_text()
support+='\nextension Array where Element == DailyTask {\n'+declaration(tasks,r'^    subscript\(_ id: UUID\)')+'\n'+declaration(tasks,r'^    func firstIndex\(id: UUID\)')+'\n}\n'
with tempfile.TemporaryDirectory(prefix='maa-daily-preparation-') as directory:
 path=Path(directory);(path/'Support.swift').write_text(support)
 subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',str(path/'Support.swift'),str(source_root/'MeoAsstMac/RunHooks/RunContext.swift'),str(source_root/'MeoAsstMac/Model/MAAError.swift'),str(root/'Tests/DailyPreparationTests.swift'),'-o',str(path/'tests')],check=True)
 subprocess.run([str(path/'tests')],check=True,timeout=30)
