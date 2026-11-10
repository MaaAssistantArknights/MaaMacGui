#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_TEST_DIR=$(mktemp -d /tmp/maa-hooks-tests.XXXXXX)
trap 'rm -rf "$TASK_TEST_DIR"' EXIT
swiftc -parse-as-library MeoAsstMac/RunHooks/RunContext.swift MeoAsstMac/RunHooks/HookConfiguration.swift MeoAsstMac/RunHooks/HookRunner.swift Tests/RunHookTests.swift -o "$TASK_TEST_DIR/tests"
"$TASK_TEST_DIR/tests"
