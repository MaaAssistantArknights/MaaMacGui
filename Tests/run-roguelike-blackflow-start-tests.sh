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
Path(sys.argv[1]).write_text(constants + '\n' + Path('Tests/RoguelikeBlackflowStartTests.swift').read_text())
PY
xcrun swiftc MeoAsstMac/Utils/BlackflowStartSupport.swift Tests/RoguelikeTestSupport.swift 'MeoAsstMac/Task Configurations/RoguelikeConfiguration.swift' "$test_dir/main.swift" -o "$test_dir/tests"
"$test_dir/tests" "$@"
