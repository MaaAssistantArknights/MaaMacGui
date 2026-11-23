#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" -parse-as-library MeoAsstMac/Model/AnnouncementService.swift MeoAsstMac/Model/AnnouncementStore.swift Tests/AnnouncementTests.swift -o "$TEST_DIR/tests"
"$TEST_DIR/tests"
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" -parse-as-library MeoAsstMac/Model/AnnouncementService.swift MeoAsstMac/Model/AnnouncementStore.swift MeoAsstMac/Views/AnnouncementView.swift Tests/AnnouncementViewTests.swift -o "$TEST_DIR/view-tests"
"$TEST_DIR/view-tests"
