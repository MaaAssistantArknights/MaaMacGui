#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library MeoAsstMac/Core/PreviewImageBuffer.swift MeoAsstMac/Model/PeepViewModel.swift Tests/PeepTests.swift -o "$TEST_DIR/peep-tests"
"$TEST_DIR/peep-tests"
