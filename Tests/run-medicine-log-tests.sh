#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maa-medicine-log.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir" <<'PYTHON'
from pathlib import Path
import sys
p = Path(sys.argv[1])
core = Path('MeoAsstMac/Core/Maa.swift').read_text()
channel = Path('MeoAsstMac/Task Configurations/StartupConfiguration.swift').read_text()
p.joinpath('ActivityModels.swift').write_text('import Foundation\n' + core[core.index('struct MAAStageActivity:'):] + channel[channel.index('enum MAAClientChannel:'):])
model = Path('MeoAsstMac/Model/MAAViewModel.swift').read_text()
start = model.index('        for task in tasks {', model.index('private func startTasks()'))
end = model.index('        try await handle?.start()', start)
# Execute the production enqueue loop with a recording Core boundary. Only the
# clock is injected so the regression does not depend on a live activity.
enqueue = model[start:end].replace('Date.now', 'now')
message = Path('MeoAsstMac/Core/MaaMessage.swift').read_text()
start = message.index('            let expiry: String', message.index('case "UseMedicine":'))
end = message.index('            if medicine.is_expiring {', start)
expiry = message[start:end]
start = model.index('        taskIDMap.removeAll()')
end = model.index('        guard requireConnect', start)
reset = model[start:end]
p.joinpath('ProductionLogPath.swift').write_text('import Foundation\nextension MedicineLogHarness {\nfunc enqueue() async throws {\n' + enqueue + '}\nfunc expiryText(coreID: Int32?) -> String {\nlet info = CallbackInfo(taskid: coreID)\n' + expiry + 'return expiry\n}\nfunc resetQueue() {\n' + reset + '}\n}\n')
PYTHON
xcrun swiftc Tests/ActivityMedicineTestSupport.swift \
  'MeoAsstMac/Task Configurations/FightConfiguration.swift' \
  MeoAsstMac/Model/StageActivity.swift MeoAsstMac/Utils/HGCalendar.swift \
  "$test_dir/ActivityModels.swift" "$test_dir/ProductionLogPath.swift" \
  Tests/MedicineLogTests.swift -o "$test_dir/tests"
"$test_dir/tests"
