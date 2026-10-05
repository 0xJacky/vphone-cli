#!/bin/zsh
set -euo pipefail

launchpad="${0:a:h:h}"
repository="${launchpad:h}"
application="$launchpad/VPhoneLaunchpad/Application"
library="$launchpad/VPhoneLaunchpad/Library"
temporary="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$temporary"' EXIT

# VPhoneDesignKit as a module of its own, as the app links it.
/usr/bin/xcrun swiftc -swift-version 6 -parse-as-library \
    -module-name VPhoneDesignKit -emit-library -emit-module \
    -emit-module-path "$temporary/VPhoneDesignKit.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libVPhoneDesignKit.dylib \
    $(/usr/bin/find "$repository/VPhoneKit/VPhoneDesignKit" -name '*.swift' ! -name '*Previews.swift' ! -name '*Preview.swift') \
    -o "$temporary/libVPhoneDesignKit.dylib"

# The app's own isolation: MainActor unless a type says otherwise.
/usr/bin/xcrun swiftc -swift-version 6 -strict-concurrency=complete \
    -default-isolation MainActor \
    -parse-as-library \
    -I "$temporary" -L "$temporary" -lVPhoneDesignKit -Xlinker -rpath -Xlinker "$temporary" \
    "$launchpad/VPhoneLaunchpadShared/VPhoneLaunchpadBundleStore.swift" \
    "$application/VPhoneLaunchpadNavigation.swift" \
    "$application/VPhoneLaunchpadPageText.swift" \
    "$application/VPhoneLaunchpadStatus.swift" \
    "$library/VPhoneLaunchpadLibraryFormat.swift" \
    "$library/VPhoneLaunchpadIPSW.swift" \
    "$library/VPhoneLaunchpadLibraryScan.swift" \
    "$library/VPhoneLaunchpadFirmwareRows.swift" \
    "$library/VPhoneLaunchpadNetworkFacts.swift" \
    "$library/VPhoneLaunchpadLibraryPage.swift" \
    "$library/VPhoneLaunchpadFirmwaresPage.swift" \
    "$library/VPhoneLaunchpadDisksPage.swift" \
    "$library/VPhoneLaunchpadNetworkPage.swift" \
    "$launchpad/Tests/ShellTests.swift" \
    -o "$temporary/shell-tests"
# The expected words are English, with English list and date formats.
"$temporary/shell-tests" -AppleLanguages '(en)' -AppleLocale en_US "$@"
