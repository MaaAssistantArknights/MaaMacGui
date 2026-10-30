#!/bin/bash
set -euo pipefail

test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(dirname "$test_dir")"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/maa-startup-tests.XXXXXX")"
trap 'rm -rf "$test_build_dir"' EXIT

# Exercise the production startup method with a controllable core connection.
# Keep its body unchanged; the wrapper only exposes its private entry point.
python3 - "$repo_dir" "$test_build_dir" <<'PY'
import pathlib
import sys

source = (pathlib.Path(sys.argv[1]) / "MeoAsstMac/Model/MAAViewModel.swift").read_text()
start = source.index("    private func startTasks() async throws {")
end = source.index("    private func initScheduledDailyTaskTimer()", start)
body = source[start:end]
# Fail loudly instead of silently absorbing methods added between the markers.
for marker in ("\n    private func ", "\n    func "):
    if marker in body:
        sys.exit(f"unexpected method inside the startTasks slice: {marker.strip()!r}")
output = "import Foundation\nextension MAAViewModel {\n" + body
output += "    func runStartupTest() async throws { try await startTasks() }\n}\n"
(pathlib.Path(sys.argv[2]) / "TaskStartup.swift").write_text(output)
PY

xcrun swiftc -parse-as-library \
    "$repo_dir/MeoAsstMac/Task Configurations/FightConfiguration.swift" \
    "$test_build_dir/TaskStartup.swift" \
    "$test_dir/TaskStartupTests.swift" \
    -o "$test_build_dir/startup-tests"
"$test_build_dir/startup-tests"
