# VPhone bundle integration

The `VPhone` Xcode scheme produces `VPhone.bundle`. It is a container for
executables and resources, not a macOS app or a dynamically loaded plug-in.
`vphone-workstation` should keep the bundle intact and launch
`Contents/MacOS/vphone-cli` as a process. The CLI locates its companion
`vphone-vm` by resolving its own executable path.

| Path | Role |
| --- | --- |
| `Contents/MacOS/vphone-cli` | Unentitled command entry point |
| `Contents/MacOS/vphone-vm` | VM and window process; private virtualization entitlements |
| `Contents/MacOS/vphone-escalator` | AMFI allowlist tool for the current VM cdhash |
| `Contents/MacOS/libswiftCompatibilitySpan.vphone.dylib` | Swift back-deployment library for `vphone-vm` on macOS 15 |
| `Contents/Resources/guest-resources/vphoned` | Pre-signed guest daemon with its own entitlements; the bundle contains no unsigned copy |
| `Contents/Resources/guest-resources/*.dylib` | Guest libraries: launchd hook, SystemHook, camera hooks and the GPU compiler plugin |
| `Contents/Resources/guest-resources/*.plist` | Guest launch daemon configuration and camera hook filters |
| `Contents/Resources` | Localized strings; no signing script or entitlement file is shipped |

`Contents/MacOS` holds only programs that run on the Mac.
`guest-resources` holds only files installed into the guest; every Mach-O in
it is built for iOS. `ValidateBundle.sh` enforces both rules.
Launchpad 2.1.0 and later require a bundle version of at least 2.1.0, which
adds patch presets (`fw patches`, `fw set-patches`, `fw patch --preset`), and
the `vphone-escalator` executable. It does not load older bundle layouts.

Executable payloads are signed ad hoc unless the build names a signing
identity (`VPHONE_SIGN_IDENTITY`, below). Only the required child processes
carry private entitlements. The bundle has no `CFBundleExecutable`,
app launcher, SMJobBless helper, installer, password prompt, or automatic root
acquisition. The integrating application owns download, release verification,
host authorization, installation, and update policy. Developer Tools access
and AMFI authorization are separate host decisions.

macOS asks for a privacy permission (microphone, location) on behalf of the
responsible process and ties the grant to its code signature. When
`vphone-cli` is started with responsibility disclaimed, it becomes the
responsible process for `vphone-vm`; signed ad hoc, its designated
requirement is its cdhash, so each new bundle build is asked again. A build
signed with a certificate keeps the grant (see Signing identity below). An integrating application that starts `vphone-cli` as
an ordinary child of a process with a stable signature, without disclaiming
responsibility, gets the permission asked once. Launchpad does this with
`vphone-launchpad-launcher`, which it carries in its own `Contents/MacOS`.
macOS attributes a tool there to the enclosing app, so the prompt, the usage
description and the grant are the app's. Under the hardened runtime the app's
main executable must carry the matching resource entitlement
(`com.apple.security.device.audio-input`,
`com.apple.security.personal-information.location`); without it macOS refuses
the request without asking.

Install and update the whole bundle as one versioned unit. Do not rewrite a
signed binary in place. When `vphone-vm` changes, its cdhash changes; the
integrating application must arrange AMFI admission for the new build before
launching it. The VM library and caches stay outside `VPhone.bundle`, under
`~/.vphone` by default. Host-side VM outputs use mode `0777` so a separate
workstation process can access them, including after a root-run create.
Guest filesystem permissions inside `Disk.img` retain their own semantics.

Build and validate:

```sh
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeBundle build
```

## Signing identity

The `VPhone` scheme signs the host-side code (`vphone-cli`, `vphone-vm`,
`vphone-escalator`, the Span compatibility library, `VPhonePatchKit`,
`VPhoneLocation.app` and the bundle) ad hoc by default. Pass a codesign
identity as a build setting to sign them with it instead:

```sh
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/XcodeBundle build \
  VPHONE_SIGN_IDENTITY=<SHA-1 of a codesigning identity in the keychain>
```

With an identity the designated requirement names the identifier and the
certificate's team rather than the build's cdhash, so privacy grants that macOS
keys to the requirement (Network Volumes for an NFS `MachineState`, the
microphone) carry over to later builds signed the same way. Entitlements are
unchanged, the guest binaries stay ad hoc, and the signature takes a secure
timestamp. `ValidateBundle.sh` then refuses a bundle or `vphone-vm` whose
requirement is still a cdhash. AMFI authorization does not change: a private
entitlement still needs `vphone-escalator allow`, which allow-lists the
`vphone-vm` cdhash whoever signed it. Gatekeeper is not involved for a bundle
installed without quarantine, and the bundle is not notarized. Never commit
the identity or a team ID.

