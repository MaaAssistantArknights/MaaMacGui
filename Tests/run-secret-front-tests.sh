#!/bin/bash
# Model-layer tests for the Secret Front feature. Only the pure decision
# logic compiled from SecretFront.swift is covered here; the MAAViewModel
# wiring around it -- the cache refresh hooks (updateChannel,
# loadResource/reloadResources defers) and the miniGame startup catch path --
# depends on @MainActor/SwiftUI/Core and is not compilable in this harness.
# Verify those call sites manually when touching them.
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maa-secret-front-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
cp Tests/SecretFrontTests.swift "$test_dir/main.swift"
xcrun swiftc -module-cache-path "$test_dir/module-cache" MeoAsstMac/Model/SecretFront.swift "$test_dir/main.swift" -o "$test_dir/secret-front-tests"
"$test_dir/secret-front-tests" "$@"
