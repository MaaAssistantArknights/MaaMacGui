#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -parse-as-library MeoAsstMac/Achievements/AchievementDefinition.swift MeoAsstMac/Achievements/AchievementEngine.swift MeoAsstMac/Achievements/AchievementEventAdapter.swift MeoAsstMac/Achievements/AchievementStore.swift Tests/AchievementTests.swift -o "$TEMP_DIR/achievement-tests"
"$TEMP_DIR/achievement-tests"
