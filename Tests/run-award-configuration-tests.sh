#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maa-award-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
# Compile the production migration initializer in the same file as its callers
# because it is fileprivate. Do not copy its implementation into the test suite.
python3 - "$test_dir/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path('MeoAsstMac/Task Configurations/LegacyConfigurations.swift').read_text()
start = source.index('extension AwardConfiguration {')
end = source.index('\nextension ', start + 1)
Path(sys.argv[1]).write_text(source[start:end] + '\n' + Path('Tests/AwardConfigurationTests.swift').read_text())
PY
xcrun swiftc \
    Tests/AwardConfigurationTestSupport.swift \
    'MeoAsstMac/Task Configurations/AwardConfiguration.swift' \
    Packages/LegacyUserTasks/Sources/LegacyUserTasks/Award.swift \
    "$test_dir/main.swift" -o "$test_dir/award-tests"
"$test_dir/award-tests"
