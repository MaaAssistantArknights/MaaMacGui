#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d /tmp/maa-login-item-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
    -module-cache-path "$build_dir/module-cache" \
    MeoAsstMac/Utils/LoginItemService.swift Tests/LoginItemServiceTests.swift \
    -o "$build_dir/tests"
"$build_dir/tests"
