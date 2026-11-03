#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Reuse a completed Debug build's real JBird module, macro plugin and objects.
# Usage: Tests/run-roguelike-settlement-tests.sh <DerivedData> [SourcePackages]
derived_data="${1:?Pass the DerivedData directory from a completed Debug build}"
products="$derived_data/Build/Products/Debug"
source_packages="${2:-$derived_data/SourcePackages}"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maa-settlement-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path('MeoAsstMac/Core/MaaMessage.swift').read_text()
start = source.index('@JSONRepresentable\nprivate struct RoguelikeSettlementDetails {')
end = source.index('\n@JSONRepresentable', start + 1)
Path(sys.argv[1]).write_text('import Foundation\nimport JBird\n' + source[start:end] + '\n' + Path('Tests/RoguelikeSettlementTests.swift').read_text())
PY
xcrun swiftc -I "$products" \
  -Xcc "-fmodule-map-file=$source_packages/checkouts/JBird/Sources/JBirdParser/include/module.modulemap" \
  -load-plugin-executable "$products/JBirdMacrosCompilerPlugin#JBirdMacrosCompilerPlugin" \
  "$products"/JBird*.o "$test_dir/main.swift" -lc++ -o "$test_dir/settlement-tests"
"$test_dir/settlement-tests" Tests/Fixtures/RoguelikeMissingFloorPackets.json Resources/Localizable.xcstrings
