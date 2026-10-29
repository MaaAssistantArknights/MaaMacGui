#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maa-secret-front-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
cp Tests/SecretFrontTests.swift "$test_dir/main.swift"
xcrun swiftc -module-cache-path "$test_dir/module-cache" MeoAsstMac/Model/SecretFront.swift "$test_dir/main.swift" -o "$test_dir/secret-front-tests"
"$test_dir/secret-front-tests" "$@"
