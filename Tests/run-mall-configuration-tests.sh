#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${1:?Usage: $0 <DerivedData directory containing a built MAA Debug app>}"
products="$derived_data/Build/Products/Debug"
parser_include="$derived_data/SourcePackages/checkouts/JBird/Sources/JBirdParser/include"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Reuse the app's built JBird dependency; do not substitute a fake JSON builder.
test -f "$products/JBird.o"
printf 'import Foundation\n' > "$test_dir/MAAClientChannel.swift"
sed -n '/^enum MAAClientChannel:/,/^}/p' \
    "$repo_root/MeoAsstMac/Task Configurations/StartupConfiguration.swift" >> "$test_dir/MAAClientChannel.swift"
sed -e 's/^import SwiftUI$/import Foundation/' -e '/^\/\/ MARK: JSON TaskParams/,$d' \
    "$repo_root/MeoAsstMac/Task Configurations/MAATaskConfiguration.swift" > "$test_dir/MAATaskConfiguration.swift"
sed -n '/^extension KeyedDecodingContainer/,$p' \
    "$repo_root/MeoAsstMac/Task Configurations/MAATaskConfiguration.swift" >> "$test_dir/MAATaskConfiguration.swift"
# Substitute only clock reads in a temporary copy so the production getter can
# be exercised deterministically while the clock advances across 04:00.
sed -e 's/Date\.now/MallTestClock.now/g' \
    "$repo_root/MeoAsstMac/Task Configurations/MallConfiguration.swift" > "$test_dir/MallConfiguration.swift"
xcrun swiftc -module-cache-path "$test_dir/module-cache" \
    -I "$products" -I "$parser_include" \
    "$test_dir/MAAClientChannel.swift" "$test_dir/MAATaskConfiguration.swift" \
    "$repo_root/MeoAsstMac/Utils/HGCalendar.swift" "$test_dir/MallConfiguration.swift" \
    "$repo_root/Tests/MallConfigurationTestSupport.swift" "$repo_root/Tests/MallConfigurationTests.swift" \
    "$products"/JBird*.o -o "$test_dir/mall-tests"
"$test_dir/mall-tests"
