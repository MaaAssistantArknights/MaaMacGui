#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_TEST_DIR=$(mktemp -d /tmp/maa-hotkey-tests.XXXXXX)
trap 'rm -rf "$TASK_TEST_DIR"' EXIT
swiftc -parse-as-library MeoAsstMac/Hotkeys/HotkeyConfiguration.swift MeoAsstMac/Hotkeys/GlobalHotkeyService.swift Tests/HotkeyTests.swift -o "$TASK_TEST_DIR/tests"
"$TASK_TEST_DIR/tests"
