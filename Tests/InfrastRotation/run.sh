#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
swiftc "$repo/Tests/InfrastRotation/TestSupport.swift" \
  "$repo/MeoAsstMac/Model/InfrastRotation.swift" \
  "$repo/MeoAsstMac/Model/MAAInfrast.swift" \
  "$repo/MeoAsstMac/Task Configurations/InfrastConfiguration.swift" \
  "$repo/Tests/InfrastRotation/main.swift" -o "$build_dir/rotation-tests"
"$build_dir/rotation-tests" "$repo/Tests/InfrastRotation/fixtures.json"
swiftc -typecheck "$repo/Tests/InfrastRotation/TestSupport.swift" \
  "$repo/MeoAsstMac/Model/InfrastRotation.swift" \
  "$repo/MeoAsstMac/Model/MAAInfrast.swift" \
  "$repo/MeoAsstMac/Task Configurations/InfrastConfiguration.swift" \
  "$repo/MeoAsstMac/Configuration Views/InfrastSettingsView.swift"
python3 "$repo/Tests/InfrastRotation/extract-lifecycle.py" "$build_dir/ProductionLifecycle.swift"
swiftc "$repo/Tests/InfrastRotation/TestSupport.swift" \
  "$repo/MeoAsstMac/Model/InfrastRotation.swift" \
  "$repo/MeoAsstMac/Model/MAAInfrast.swift" \
  "$repo/MeoAsstMac/Task Configurations/InfrastConfiguration.swift" \
  "$repo/Tests/InfrastRotation/LifecycleSupport.swift" \
  "$build_dir/ProductionLifecycle.swift" \
  "$repo/Tests/InfrastRotation/LifecycleTests.swift" -o "$build_dir/lifecycle-tests"
"$build_dir/lifecycle-tests"
