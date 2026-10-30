#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maa-roguelike-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path('MeoAsstMac/Configuration Views/RoguelikeSettingsView.swift').read_text()
marker = 'extension RoguelikeConfiguration.Theme:'
start = source.find(marker)
if start < 0 or 'var squads' not in source[start:]:
    sys.exit('Tests/run-roguelike-seed-tests.sh: cannot find Theme squads after %r in '
             'RoguelikeSettingsView.swift; update the test runner' % marker)
constants = source[start:]
Path(sys.argv[1]).write_text(constants + '\n' + Path('Tests/RoguelikeSeedTests.swift').read_text())
PY
xcrun swiftc Tests/RoguelikeTestSupport.swift 'MeoAsstMac/Task Configurations/RoguelikeConfiguration.swift' "$test_dir/main.swift" -o "$test_dir/tests"
"$test_dir/tests"
