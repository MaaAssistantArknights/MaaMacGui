#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Usage: Tests/run-roguelike-exit-log-tests.sh <DerivedData> [SourcePackages]
derived_data="${1:?Pass the DerivedData directory from a completed Debug build}"
products="$derived_data/Build/Products/Debug"
source_packages="${2:-$derived_data/SourcePackages}"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maa-exit-log-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path('MeoAsstMac/Core/MaaMessage.swift').read_text()
start = source.index('@JSONRepresentable\nprivate struct ProcessTaskDetails {')
end = source.index('\nextension MAAViewModel', start)
branch = source.index('            case "ExitThenAbandon":', end)
next_case = source.index('\n            case ', branch + 1)
production = source[start:end] + '\nprivate func handleExit(_ process: ProcessTaskDetails) {\n switch process.task {\n' + source[branch:next_case] + '\n default: break\n }\n}\n'
Path(sys.argv[1]).write_text('import Foundation\nimport JBird\n' + production + Path('Tests/RoguelikeExitLogTests.swift').read_text())
PY
xcrun swiftc -I "$products" \
  -Xcc "-fmodule-map-file=$source_packages/checkouts/JBird/Sources/JBirdParser/include/module.modulemap" \
  -load-plugin-executable "$products/JBirdMacrosCompilerPlugin#JBirdMacrosCompilerPlugin" \
  "$products"/JBird*.o "$test_dir/main.swift" -lc++ -o "$test_dir/exit-log-tests"
"$test_dir/exit-log-tests" Tests/Fixtures/RoguelikeRetainedRunExit.json Resources/Localizable.xcstrings
