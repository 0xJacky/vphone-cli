#!/bin/zsh
set -euo pipefail

launchpad="${0:a:h:h}"
machines="$launchpad/VPhoneLaunchpad/Machines"
temporary="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$temporary"' EXIT

/usr/bin/xcrun swiftc -swift-version 6 -strict-concurrency=complete \
    -parse-as-library \
    "$machines/VPhoneLaunchpadMachineMenu.swift" \
    "$machines/VPhoneLaunchpadMachineFormat.swift" \
    "$machines/VPhoneLaunchpadPatchCatalog.swift" \
    "$launchpad/VPhoneLaunchpad/Application/VPhoneLaunchpadLogTranslator.swift" \
    "$launchpad/Tests/MachinesLogicTests.swift" \
    -o "$temporary/machines-logic-tests"
"$temporary/machines-logic-tests" "$@"
