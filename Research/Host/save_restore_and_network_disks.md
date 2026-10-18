# Save/restore support and NBD disks

What Virtualization.framework allows for freezing a vphone in place and for
attaching its disk over NBD, and how vphone uses it. The implementation is
`VPhoneVirtualMachine+SaveRestore.swift` (vphone-vm), `VPhoneSavedMachineState`,
`VPhoneDiskLocation` and `VPhoneMachineStateLayout` (VPhoneCoreKit). User-facing
commands are in `Documents/Guides/suspend-and-migration.md`; the on-machine
tests still owed are in `Documents/PoC/suspend-migration/README.md`.

Checked on 2026-10-18/19 on a development Mac: macOS 27.0.1, Xcode 27.1,
MacOSX27.0 SDK, SIP and AMFI untouched. **No vphone guest was started.** The
findings below come from the SDK headers and from a probe program that builds
configurations and asks Virtualization to validate them, signed ad hoc with
the public `com.apple.security.virtualization` entitlement only.

## What the API promises

From `VZVirtualMachine.h` and `VZVirtualMachineConfiguration.h` (macOS 27 SDK):

- `saveMachineStateTo(url:)` saves a **paused** VM; arm64 only; macOS 14+.
  On failure the VM state is unchanged.
- `restoreMachineStateFrom(url:)` restores into a **stopped** VM, which ends
  up paused. On failure the VM state is unchanged, so the same
  `VZVirtualMachine` can still be started cold. vphone relies on this for its
  fallback.
- The file "must have been generated … on the same host", otherwise
  `VZErrorRestore` (permission denied). "Each file is protected by an
  encryption key that is tied to the host on which it is created." A newer
  writer's file, or a host changed by a software update, gives
  `VZErrorRestore` (invalid argument); "the virtual machine should be
  restarted". There is no cross-Mac restore.
- `validateSaveRestoreSupport()`: "Not all configuration options can be
  safely saved and restored from file." The header does not list them.

## Which vphone devices block saving

`validateSaveRestoreSupport()` reports only the **first** part it rejects, as
`VZErrorDomain` code 2 with a failure reason naming the kind of device. vphone
therefore diagnoses by elimination (`VPhoneSaveRestoreDiagnosis`): it copies
the configuration, removes every candidate part, and puts them back one at a
time. A part whose presence alone fails is reported as a blocker.

The PV=3 hardware model vphone uses needs the private virtualization
entitlements, which an ad hoc build cannot carry here without changing AMFI.
The probe was therefore run twice:

| Configuration | Result |
| --- | --- |
| PV=3 descriptor (`_VZMacHardwareModelDescriptor` 3/0x90/2), public entitlement only | `isSupported` is false; validation stops at `“auxiliaryStorage” is nil` before any device is checked |
| PV=2 macOS guest model (`PlatformVersion 2`), every vphone device added | see below |

With the PV=2 model, each vphone device alone, macOS 27.0.1:

| Device (configuration class) | `validateSaveRestoreSupport()` |
| --- | --- |
| `VZMacGraphicsDeviceConfiguration` 1290×2796 | passes |
| `VZVirtioSoundDeviceConfiguration`, host input and output | passes |
| `VZDiskImageStorageDeviceAttachment` | passes |
| `VZNetworkBlockDeviceStorageDeviceAttachment` (`nbd://127.0.0.1:10809/vphone`) | passes |
| `VZNATNetworkDeviceAttachment` | passes |
| `_VZPL011SerialPortConfiguration` with file handles | passes |
| `_VZMacVideoToolboxDeviceConfiguration`, `_VZMacNeuralEngineDeviceConfiguration`, `_VZMacScalerAcceleratorDeviceConfiguration` | pass |
| `_VZUSBTouchScreenConfiguration` (multi-touch) | **fails**: "Unsupported multi-touch device in configuration." |
| `VZVirtioEntropyDeviceConfiguration`, `VZUSBKeyboardConfiguration`, `VZVirtioSocketDeviceConfiguration` | pass |
| `_VZMacBatteryPowerSourceDeviceConfiguration` with `_VZMacSyntheticBatterySource` | passes |
| `_VZGDBDebugStubConfiguration` (kernel) | passes |
| `_VZSEPCoprocessorConfiguration`, with or without its own `_VZGDBDebugStubConfiguration` | **fails**: "Unsupported coprocessor in configuration." |
| `VZMacOSBootLoader` with `_setROMURL` | passes |
| full vphone set | fails on multi-touch first; without it, on the coprocessor; without both, passes |

The ObjC runtime lists no save/restore override for these private classes;
the only `supportsSaveRestore` switches are on
`VZCustomVirtioDeviceConfiguration` and `_VZCustomMMIODeviceConfiguration`.

**Conclusion, static:** two private devices block saving:

1. the multi-touch screen (`_VZUSBTouchScreenConfiguration`). vphone could
   drop it for headless machines, which already inject touches through
   vphoned's `input.touch`, but windowed launches use it;
2. the SEP coprocessor (`_VZSEPCoprocessorConfiguration`), with or without its
   debug stub. An iOS guest cannot run without it.

So in-place freezing is expected to be **refused for every vphone guest** on
macOS 27.0.1, unless the PV=3 path behaves differently from the PV=2 one, which
only PoC F1 on a test Mac can show. `vm save-state --check` prints the same
diagnosis from the running VM, and `--ignore-validation` exists for F1 to see
whether `saveMachineStateTo` itself refuses (expected: `VZErrorSave`).

The other parts were checked alone; the check does not prove a part that
passes alone survives a real save and restore.

## NBD disks

From `VZNetworkBlockDeviceStorageDeviceAttachment.h` and the probe:

- `init(url:timeout:isForcedReadOnly:synchronizationMode:)`; macOS 14+. The
  connection is made when the VM starts, not when the attachment is created.
  On a timeout or recoverable error the client reconnects by itself,
  transparently to the guest. `attachmentWasConnected` fires on every
  (re)connection; `attachment(_:didEncounterError:)` means the client is
  non-functional from then on.
- The convenience initializer's defaults, read back on macOS 27.0.1: timeout
  5 s, synchronization `full`, not read-only.
- `validate(_:)` accepts `nbd://host[:port]/export`, `nbd://[::1]:10809/e`,
  `nbd+unix:///e?socket=…`; it refuses `nbds://…` with "The URL is not
  supported." **TLS is not available**, and the API has no certificate
  parameters. vphone accepts only `nbd://` over TCP.
- The header asks for `com.apple.security.network.client`; that applies to
  sandboxed apps, and vphone-vm is not sandboxed. Not verified on a running
  guest.

vphone writes the URL into `diskImage`, which builds from before NBD reject
(not a plain file name) rather than booting a stale `Disk.img`. A fatal client
error stops the VM (`vphone-vm` exits non-zero) instead of leaving a guest
without its disk.

## Not verified here

- Any real save, restore, NBD connection, reconnection or failure with a
  vphone guest: PoC F1–F5.
- PV=3 save/restore validation.
- Whether `restoreMachineStateFrom` with an NBD disk keeps working when the
  export reconnects during the restore.
