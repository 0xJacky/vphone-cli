# Freezing, NBD Disks and Cold Migration

Three building blocks for moving a vphone off a Mac that is failing or short
of memory. None of them moves a running guest between Macs:
Virtualization.framework encrypts a saved machine state with a key tied to
the Mac that wrote it, so a guest can only be **frozen in place** and resumed
on the same Mac. To run it elsewhere it is **cold-started** there: shut down
on the old Mac (or lost with it) and booted on the new one from the same disk
and state files.

| Need | Use |
| --- | --- |
| Stop a guest for a moment, same process | `vm pause`, `vm resume` |
| Give a guest's memory back to the Mac, resume later on the same Mac | `vm save-state`, `vm restore-state` |
| Keep the disk on shared storage | `vm storage --disk nbd://host:port/export` |
| Keep everything else that must follow the machine in one directory | `vm storage --state-dir on` |
| Make a new machine on a network disk and a mounted state directory | `vm create --remote-disk … --from-manifest …` |

Research notes, including which devices stop a vphone from being saved, are
in `Research/Host/save_restore_and_network_disks.md`. The tests still owed on
a real Mac are in `Documents/PoC/suspend-migration/README.md`.

## Pause and resume

```sh
vphone-cli vm pause wecom-03
vphone-cli vm resume wecom-03
```

The guest stops executing; its memory stays allocated in `vphone-vm`. Quitting
a paused VM turns it off at once, since the guest cannot answer a shutdown
request. Network connections in the guest time out if the pause lasts.

## Save and restore (same Mac only)

```sh
vphone-cli vm save-state wecom-03 --check     # can this configuration be saved?
vphone-cli vm save-state wecom-03             # pause, save to SavedState/, stop
vphone-cli vm restore-state wecom-03 --headless --api-listen 127.0.0.1:8765
```

`save-state` asks Virtualization's `validateSaveRestoreSupport()` first. When
it refuses, nothing is paused or written, and the command names every device
that blocks it, found by trying the configuration without each one. On
macOS 27.0.1 the multi-touch screen and the SEP coprocessor are expected to
block every vphone (see the research note); `--check` shows what the running
machine reports, and exits 2 when it cannot be saved.

Options:

- `[path]` — a directory to create; default `SavedState/` in the machine
  folder. `--replace` replaces an existing one.
- `--then stop|pause|resume` — after saving: stop the VM and end the process
  (default; the memory goes back to the Mac), stay paused, or keep running. After
  `resume` the disk moves on and the state can no longer be restored from a
  disk file.
- `--ignore-validation` — PoC only: save even though the validation refused.

The directory holds `MachineState.vzvmsave` (Virtualization's file) and
`binding.plist`, which records what the state belongs to. `restore-state`
refuses, before Virtualization sees the file, a state that:

- was saved by another machine (machine identifier) or hardware model;
- was saved on another Mac (hardware UUID);
- was saved with another CPU count, memory size, disk, MAC address, network
  mode, screen, keyboard setting or guest device;
- was saved with a disk image file that has changed since (device, inode,
  size and modification time). An NBD disk cannot be checked this way; that is
  logged as a warning;
- was already used: a successful restore, a cold boot of the machine, or a
  failed restore that fell back to a cold boot marks it used.

When vphone or Virtualization refuses the state, the guest **boots cold**
instead, and the state is marked used. `--no-cold-boot-fallback` makes
`vphone-vm` exit with an error instead, for a supervisor that wants to choose.
`--restore-from-other-host` exists only for PoC F2: it lets Virtualization
itself refuse a state from another Mac.

The saved state never leaves the Mac: clones and exports leave `SavedState/`
out, and it is not part of `MachineState/`.

## NBD disks

```sh
vphone-cli vm storage wecom-03 --disk nbd://10.20.0.3:10809/wecom-03 --nbd-timeout 15
vphone-cli vm storage wecom-03 --disk Disk.img     # back to the local file
```

The disk is attached with `VZNetworkBlockDeviceStorageDeviceAttachment`
(macOS 14+). The NBD server runs outside vphone, for example `qemu-nbd`
exporting a DRBD device.

- **No TLS.** Virtualization's NBD client refuses `nbds://` and takes no
  certificates. Serve the export on a link the Mac trusts: loopback, a private
  network, or a tunnel set up outside vphone. Data and writes cross that link
  in the clear.
- `--nbd-timeout` (1–600 s, default 5) is how long the client waits on the
  connection before it reconnects. Reconnects are invisible to the guest; its
  disk I/O stalls meanwhile. Each (re)connection is logged as `[nbd] connected`
  / `[nbd] reconnected`, and `vphone.sock`'s `vmstate` reports the count.
- When the client gives up for good, `vphone-vm` logs `[nbd] lost … for good`,
  stops the VM and exits non-zero, so a supervisor sees it stop.
- `--nbd-sync none` acknowledges the guest's flushes without sending them;
  only for throwaway machines.
- Switching to NBD leaves `Disk.img` in the folder untouched and unused. Do not
  switch back to it while the export is in use elsewhere.
- vphone cannot clone, snapshot, revert, rebase, export or trim an NBD
  machine, because each would take the SEP storage without the disk it pairs
  with, or let two machines write one disk. Do those on the storage side,
  together with `MachineState/`. `cfw install` and restores that patch
  `Disk.img` on the host need the file disk as well.
- `vm stop` finds an NBD machine by its SEP storage instead of its disk.

## The machine state directory

```sh
vphone-cli vm storage wecom-03 --state-dir on
vphone-cli vm storage wecom-03                 # show layout, identity, problems
vphone-cli vm storage wecom-03 --state-dir off
```

What must follow a machine to another Mac for a cold start, besides its disk:

| State | Where, legacy layout | Where, state-directory layout |
| --- | --- | --- |
| Machine identifier (ECID, so the UDID) | `config.plist` | `config.plist`, mirrored in `MachineState/identity.plist` |
| MAC address | `config.plist` | the same, mirrored |
| Hardware model (fixed PV=3 descriptor) | not stored | recorded in `identity.plist` to detect a mismatch |
| NVRAM, which is the auxiliary storage (`VZMacAuxiliaryStorage`) | `nvram.bin` | `MachineState/nvram.bin` |
| SEP storage | `SEPStorage` | `MachineState/SEPStorage` |

The rest of the machine definition (`config.plist`'s CPU, memory, network,
screen and ROM names, the ROM files, `restore-info.json`) is recreated or
copied by whoever moves the machine. Host-bound files stay out of
`MachineState/`: `vphone.sock`, `.vphoned.signed`, `Snapshots/`, `SavedState/`.

`--state-dir on` moves the two files by `rename(2)` (the folder must be on the
machine's volume while it runs), writes `identity.plist`, then writes
`config.plist`. Run it again to finish an interrupted move; a launch refuses a
half-moved machine. To put `MachineState` on a shared volume afterwards, copy
the directory there and mount the volume over `MachineState` (a mount point is
a real directory; a symbolic link is refused).

On every boot in this layout `vphone-vm`:

- refuses to start a machine that has booted before when its NVRAM or SEP
  storage is missing — what an unmounted state volume looks like — instead of
  creating empty ones the guest's data could no longer be decrypted with;
- refuses a `MachineState` whose `identity.plist` names another machine or
  hardware model;
- adopts the identity from `identity.plist` when `config.plist` has none, so a
  `config.plist` recreated on the target Mac keeps the ECID, UDID and MAC;
- rewrites `identity.plist` when anything in it changed.

Snapshots keep each state file under its plain name in both layouts, so a
snapshot taken before `--state-dir on` still reverts after it. Snapshots and
clones need `MachineState` on the same APFS volume as the machine folder.

## A new machine on a network disk

```sh
mkdir ~/.vphone/machines/st-1                      # then mount the state volume on st-1/MachineState
vphone-cli vm create st-1 --remote-disk nbd://10.41.2.2:17600/vm-st-1-disk.tok \
    --from-manifest ~/.vphone/machines/st-1/MachineState/config.plist \
    --cpu 4 --memory 6144 --network tunnel --json
```

For a machine whose disk and state live on storage nodes (a Mac fleet clones
both from a template there), so the template itself is not on this Mac. The
folder must already exist and hold only `MachineState`, a real directory (a
mount point is one) that this account can write, with the template's
`nvram.bin` and `SEPStorage` in it. `--from-manifest` is the template's
`config.plist`, only read. The machine is completed around them as a clone
from a template is: a new identity (machine identifier, MAC address, fixed
address, port forwards and a hand-set mDNS name cleared, `identity.plist`
removed), this bundle's OpenAVB and OpenSEP, then `--cpu`, `--memory`,
`--network` and `--unlock-at-startup`. Nothing is copied or downloaded and the
guest does not boot; the first start is `vm launch`, as for any machine.

- `--nbd-timeout` is 60 s by default and cannot be lower: the client rides out
  a server that stalls for less than its timeout, but a reconnect stops the VM
  for good, so the timeout must outlast a storage node's stalls.
- It refuses a folder with anything but `MachineState` in it (an existing
  `config.plist` reads as "already exists"), a `MachineState` without the two
  state files, and a template whose `config.plist` names them differently.
- On failure only what it added to the folder is removed; the folder and
  `MachineState/` stay as they were, so it can be run again.
- A machine on an NBD disk never starts without its NVRAM and SEP storage, on
  its first boot too: an empty `MachineState` is an unmounted state volume.
- `vm delete` refuses while `MachineState` is a mounted volume; unmount it
  first, or the files on it would be deleted with the folder.
- An NFS-mounted `MachineState` is a network volume, and macOS asks before an
  app opens files on one (Privacy & Security > Files & Folders, Network
  Volumes). The first open blocks until someone answers the dialog on the
  Mac's own screen; it does not fail. `vphone-vm` probes `MachineState` first
  and gives up after 30 s with an error naming the dialog (2.12.2; 2.12.1 sat
  with no VM and no log). The bundle is signed ad hoc, so TCC knows it by its
  cdhash and asks again after every bundle upgrade, on every Mac. Starting it
  over SSH does not help: the job runs in the logged-in user's session.

## Compatibility

- **Existing machines are unchanged.** Nothing moves unless `vm storage` is
  run; a legacy machine with a file disk boots, stops, clones and snapshots as
  before. `config.plist` gains a key only for an NBD disk (`nbd`).
- **Older vphone builds refuse, rather than misread, the new forms.** An
  `nbd://` disk and `MachineState/…` names are not plain file names, which every
  build since 2.0 requires. Such a build reports the manifest as invalid and
  `vm list` skips the machine with a warning, so a supervisor still running an
  older bundle on that Mac will not see it. Booting it with an older build is
  therefore impossible — that is the point: it would create new NVRAM and SEP
  storage, or boot a stale `Disk.img`. `vm storage --state-dir off` and
  `--disk Disk.img` make a machine readable by older builds again.
- `vm list --json` and `vm info --json` add `networkDisk`, `stateLayout` and
  `hasSavedState`, all optional.
- `vphone.sock` adds `vmstate`, `pause`, `resume` and `save-state`; the
  existing commands are unchanged.
- `vm launch` and `vphone-vm` take `--restore-state`, `--no-cold-boot-fallback`
  and `--restore-from-other-host`; without them a launch is as before, except
  that it marks an unused `SavedState/` of the machine as used.
- Launchpad is not changed. It shows an NBD machine's disk as 0 bytes, and its
  helper's firmware operations need `Disk.img`.
