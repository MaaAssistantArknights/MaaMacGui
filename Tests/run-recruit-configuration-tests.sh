#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maa-recruit-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
# Compile the actual fileprivate initializer together with its test callers.
python3 - "$test_dir/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path('MeoAsstMac/Task Configurations/LegacyConfigurations.swift').read_text()
start = source.index('extension RecruitConfiguration {')
end = source.index('\nextension ', start + 1)
Path(sys.argv[1]).write_text(source[start:end] + '\n' + Path('Tests/RecruitConfigurationTests.swift').read_text())
PY
xcrun swiftc \
    Tests/RecruitConfigurationTestSupport.swift \
    'MeoAsstMac/Task Configurations/RecruitConfiguration.swift' \
    Packages/LegacyUserTasks/Sources/LegacyUserTasks/Recruit.swift \
    "$test_dir/main.swift" -o "$test_dir/recruit-tests"
"$test_dir/recruit-tests" "$@"
