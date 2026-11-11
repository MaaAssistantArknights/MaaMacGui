#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Compile the production channel enum and calendar without the app's MaaCore/UI dependencies.
# The enum is a top-level declaration with its closing brace in column one.
printf 'import Foundation\n' > "$test_dir/MAAClientChannel.swift"
sed -n '/^enum MAAClientChannel:/,/^}/p' \
    "$repo_root/MeoAsstMac/Task Configurations/StartupConfiguration.swift" >> "$test_dir/MAAClientChannel.swift"
xcrun swiftc -module-cache-path "$test_dir/module-cache" \
    "$test_dir/MAAClientChannel.swift" \
    "$repo_root/MeoAsstMac/Utils/HGCalendar.swift" \
    "$repo_root/Tests/HGCalendarTests.swift" \
    -o "$test_dir/hgcalendar-tests"
"$test_dir/hgcalendar-tests"
