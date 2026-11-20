#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maa-activity-medicine.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
core=Path('MeoAsstMac/Core/Maa.swift').read_text()
channel=Path('MeoAsstMac/Task Configurations/StartupConfiguration.swift').read_text()
p.joinpath('ActivityModels.swift').write_text('import Foundation\n'+core[core.index('struct MAAStageActivity:'):]+channel[channel.index('enum MAAClientChannel:'):])
legacy=Path('MeoAsstMac/Task Configurations/LegacyConfigurations.swift').read_text()
start=legacy.index('extension FightConfiguration {')
end=legacy.index('\nextension ', start+1)
p.joinpath('main.swift').write_text(legacy[start:end]+'\n'+Path('Tests/ActivityMedicineTests.swift').read_text())
PY
xcrun swiftc Tests/ActivityMedicineTestSupport.swift \
  'MeoAsstMac/Task Configurations/FightConfiguration.swift' \
  MeoAsstMac/Model/StageActivity.swift MeoAsstMac/Utils/HGCalendar.swift \
  Packages/LegacyUserTasks/Sources/LegacyUserTasks/Fight.swift \
  "$test_dir/ActivityModels.swift" "$test_dir/main.swift" -o "$test_dir/tests"
"$test_dir/tests" "$@"
