#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maa-roguelike-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path('MeoAsstMac/Configuration Views/RoguelikeSettingsView.swift').read_text()
constants = source[source.index('extension RoguelikeConfiguration.Theme:'):]
Path(sys.argv[1]).write_text(constants + '\n' + Path('Tests/RoguelikeEndingFlightTests.swift').read_text())
squad = source[source.index('private func squadSettings()'):source.index('private func startCollectibles()')]
for control in ['开局分队', '开局职业组', '开局干员（单个）', '使用助战', '非好友助战']:
    assert control in squad, f'missing opening control: {control}'
gated = squad.count('.disabled(config.usesBlackflowFastFlight)') + squad.count(
    '.disabled(config.start_with_elite_two || config.usesBlackflowFastFlight)'
)
assert gated == 5, f'fast flight must disable all 5 opening controls, found {gated}'
ending = source[source.index('Picker("目标结局"'):source.index('Toggle("疾速飞行"')]
assert 'config.blackflowEnding != .coreDefault, !config.blackflowFastFlight' in ending, \
    'ending selection must explain that opening settings still apply'
assert '上方的难度与开局设置照常生效' in ending, 'missing ending selection caption'
PY
xcrun swiftc Tests/RoguelikeTestSupport.swift 'MeoAsstMac/Task Configurations/RoguelikeConfiguration.swift' "$test_dir/main.swift" -o "$test_dir/tests"
"$test_dir/tests"
