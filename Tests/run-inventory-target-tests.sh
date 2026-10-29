#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -parse-as-library MeoAsstMac/Model/InventoryTarget.swift 'MeoAsstMac/Task Configurations/FightConfiguration.swift' Tests/InventoryTargetTestSupport.swift Tests/InventoryTargetTests.swift -o "$TEMP_DIR/inventory-tests"
"$TEMP_DIR/inventory-tests"
