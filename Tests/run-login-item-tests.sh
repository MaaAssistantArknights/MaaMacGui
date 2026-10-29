#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d /tmp/maa-login-item-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
    MeoAsstMac/Utils/LoginItemService.swift Tests/LoginItemServiceTests.swift \
    -o "$build_dir/tests"
"$build_dir/tests"
