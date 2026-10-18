# PoC F1–F5: freezing, NBD disks and cold migration

The tests the `feat/suspend-and-nbd` branch still owes on real Macs. They
could not run on the development Mac where the branch was written: a vphone
guest needs `vphone-vm`'s private entitlements admitted by AMFI, and that
host's security settings were not to be changed. What *was* checked there is
in `Research/Host/save_restore_and_network_disks.md` (configuration-level
`validateSaveRestoreSupport()` results, NBD URL handling) and in the
VPhoneCoreKit tests.

`run-poc.zsh` drives each step and writes logs, JSON replies and a
`results.txt` into `$POC_OUT` (default `./poc-results-<time>`). Read a step
below before running it.

## Ground rules

- **Test machines only.** The script refuses any machine named `wecom*`. Make
  a test machine from a template with `vphone-cli vm clone <template> poc-01
  --new-identity` (and `poc-wecom` with a WeCom **test** account for F5).
- Install a `VPhone.bundle` built from this branch on the test Mac the way the
  fleet installs bundles, including the host's usual AMFI admission of its
  `vphone-vm`. The script uses `vphone-cli` from `PATH`, or `VPHONE_CLI`.
- Nothing here changes SIP, AMFI or system settings, and nothing needs sudo.
- F2 and the cross-Mac half of F4 need two Macs; everything else runs on one.

## Steps

### Preflight

```sh
./run-poc.zsh preflight poc-01
```

Records the macOS build, the CLI, `vm storage --json` and `vm info --json`.

### F1 — same-Mac save and restore

```sh
./run-poc.zsh f1 poc-01
F1_FORCE=1 ./run-poc.zsh f1 poc-01     # also try saving despite the validation
```

1. Boots the machine headless and records SpringBoard's PID.
2. `vm save-state --check`: Virtualization's `validateSaveRestoreSupport()` on
   the real PV=3 configuration, with every blocking device named.
   **Expected** (from the PV=2 probe): unsupported, blocked by the multi-touch
   screen and the SEP coprocessor. Record the exact summary either way: it is
   the first PV=3 answer.
3. If unsupported and `F1_FORCE=1`: `--ignore-validation --then resume` to see
   whether `saveMachineStateTo` itself refuses (expected `VZErrorSave`) and
   that the VM keeps running after the refusal.
4. If supported: saves (pause, save, stop), checks the process is gone, runs
   `vm restore-state`, and passes only when the log says `Restored in` and
   SpringBoard kept its PID (a cold boot would give it a new one).

If a supported save restores as `the disk image changed since it was saved`,
the disk fingerprint is too strict for how Virtualization opens the image:
report it, it is a bug in this branch.

### F2 — cross-Mac restore (only if F1 saved)

On Mac A: `./run-poc.zsh f2-save poc-01`, then copy the stopped machine to
Mac B (`vm export` / `vm import`, which leave `SavedState/` out) and copy
`~/.vphone/machines/poc-01/SavedState` separately. Do not boot `poc-01` on A
in between. On Mac B:

```sh
./run-poc.zsh f2-restore poc-01 /path/to/copied/SavedState
```

It uses `--restore-from-other-host --no-cold-boot-fallback`, so vphone hands
the file to Virtualization instead of refusing it first (the host and the copied disk's fingerprint are only warned about). **Expected:**
`VZErrorRestore`, permission denied, as the header says. A successful restore
would contradict the documentation and must be reported.

### F3 — NBD disk

Needs an NBD server the Mac reaches over a trusted link, exporting a **copy**
of the test machine's disk, for example on the storage node:

```sh
qemu-nbd --persistent --shared=1 --format=raw --export-name=poc-01 \
  --bind=10.20.0.3 --port=10809 /srv/poc/poc-01.img
```

(or `nbdkit file /srv/poc/poc-01.img --exportname=poc-01`). Then:

```sh
NBD_TIMEOUT=10 \
NBD_STOP_CMD='ssh storage-node systemctl stop poc-nbd' \
NBD_START_CMD='ssh storage-node systemctl start poc-nbd' \
./run-poc.zsh f3 poc-01 nbd://10.20.0.3:10809/poc-01
```

1. Switches the machine to the export with `vm storage --disk … --nbd-timeout`
   and back to its previous disk when the step ends.
2. Boots it; `vmstate` must show `nbd.connected` and one connection. Records
   `validateSaveRestoreSupport()` with the NBD attachment (configuration level;
   the PV=2 probe passed it).
3. With the stop/start commands set: an outage of half the timeout and one of
   three times the timeout. After each, the guest must answer again and the
   log should show `[nbd] reconnected`. Record whether the guest saw errors
   (`logs.syslog`) and how long I/O stalled.
4. `NBD_FATAL_TEST=1` stops the server for good and waits up to 10 minutes:
   record whether Virtualization ever reports a non-recoverable error
   (`[nbd] lost … for good`, after which vphone-vm stops the VM) or keeps
   retrying.

TLS is not tested: Virtualization refuses `nbds://` (see the research note).

### F4 — timings and the identity rehearsal

```sh
./run-poc.zsh f4 poc-01
```

Records pause and resume times through `vphone.sock`; save and restore times
when F1 saved; `vm stop` (guest shutdown) time; and the cold start time from
`vm launch` to vphoned's ping. Then it rehearses the cold start on a target
Mac on one Mac: `vm storage --state-dir on`, clears `machineIdentifier` in
`config.plist` (a backup goes to `$POC_OUT`), boots, and checks the log says
`Adopted the machine identity` and the UDID is unchanged.

For the cross-Mac cold migration, after `vm stop` on Mac A: move the disk
(or keep it on NBD), copy `MachineState/` and the machine definition to Mac B,
boot there and time it the same way. Record the total downtime from
`vm stop` on A to the ping on B.

### F5 — WeCom test account

On a test machine logged in to a WeCom **test** account:

```sh
./run-poc.zsh f5 poc-wecom before
# freeze/restore (F1) or cold-migrate (F4) the machine
./run-poc.zsh f5 poc-wecom after
```

Takes a screenshot and asks whether WeCom opens without asking to log in,
whether messages arrive, and whether a security prompt appeared. Run it after
a same-Mac restore (if F1 saved), after a same-Mac cold boot, and after a
cold start on another Mac with the NAT exit address changed.

## Reporting

Send back `results.txt`, `poc.log` and the JSON files, plus macOS and bundle
versions. For each of F1–F5 state: ran or not, on which Macs, and whether the
result matches the expectation above.
