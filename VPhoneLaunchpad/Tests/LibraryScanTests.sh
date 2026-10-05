#!/bin/zsh
set -euo pipefail

launchpad="${0:a:h:h}"
library="$launchpad/VPhoneLaunchpad/Library"
temporary="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$temporary"' EXIT

/usr/bin/xcrun swiftc -swift-version 6 -strict-concurrency=complete \
    -parse-as-library \
    "$library/VPhoneLaunchpadLibraryFormat.swift" \
    "$library/VPhoneLaunchpadIPSW.swift" \
    "$library/VPhoneLaunchpadLibraryScan.swift" \
    "$library/VPhoneLaunchpadFirmwareRows.swift" \
    "$library/VPhoneLaunchpadNetworkFacts.swift" \
    "$launchpad/Tests/LibraryScanTests.swift" \
    -o "$temporary/library-scan-tests"
"$temporary/library-scan-tests" "$@"
