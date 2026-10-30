#!/bin/bash
set -euo pipefail

test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(dirname "$test_dir")"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/maa-fight-tests.XXXXXX")"
trap 'rm -rf "$test_build_dir"' EXIT

xcrun swiftc -parse-as-library \
    "$repo_dir/MeoAsstMac/Task Configurations/FightConfiguration.swift" \
    "$test_dir/FightConfigurationTests.swift" \
    -o "$test_build_dir/fight-tests"
"$test_build_dir/fight-tests"
