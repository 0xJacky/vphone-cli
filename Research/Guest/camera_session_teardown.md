# Camera session teardown crash

The virtual-camera `isRunning` hook adds a weak reference to a session during deallocation.
Objective-C rejects the reference and aborts the app.
AVFoundation reaches the hook through `AVCaptureInput setSession:` while it removes the session inputs.

The getter must keep tracking live sessions.
Some camera clients skip `startRunning` because the getter already returns `YES`.
Removing tracking from the getter can stop frame delivery for those clients.

`cfx_live_session` uses `objc_storeWeakOrNil` to skip objects already in deallocation.
Its strong weak-load keeps live sessions alive through table insertion.
The tracking argument uses `__unsafe_unretained` so ARC does not retain a dying session on entry.

## Reproduction

Build the small camera app:

```sh
make -C VPhoneGuestComponents build-camfix-session-reproducer
```

Install `.build/siblings/camera-session-reproducer/SessionProbe.ipa` in an iOS guest.
Run `org.example.vphone.SessionProbe`.
The app automatically creates and releases 100 sessions with the virtual-camera input and a video data output.
It adds a KVO observer for `running` on alternate cycles.
It does not start capture.

The original library aborts during session deallocation.
The patched library completes all cycles.
The app shows the result and writes `Documents/result.txt` in its data container.

## Crash stack with the original 2.13.4 library

The [crash log excerpt](Evidence/camfix_session_teardown_crash.txt) includes the abort frames and library names.

```text
Exception: EXC_CRASH (SIGABRT)
Termination namespace: OBJC

weak_register_no_lock + 396
objc_storeWeak + 468
-[NSConcreteHashTable addObject:] + 96
cfx_track_vcam_session + 128
cfx_session_isRunning_hook + 76
-[AVCaptureInput setSession:] + 64
-[AVCaptureDeviceInput setSession:] + 272
-[AVCaptureSession _removeInput:] + 232
-[AVCaptureSession removeInput:] + 344
-[AVCaptureSession dealloc] + 308
_NSKVOPerformWithDeallocatingObservable + 180
NSKVODeallocate + 184
AutoreleasePoolPage::releaseUntil(objc_object**) + 204
objc_autoreleasePoolPop + 244
RunCameraSessionProbe + 440
```

## Results on iOS 27.0.1 (24A446)

- The original 2.13.4 libcamfix crashed twice with the same test app.
- A repeat with both stock 2.13.4 camera libraries produced the same crash.
- The clean-branch libcamfix with stock libvcamcaptured completed 100 release cycles.
- With that pair, Camera.app showed the host test pattern and saved photos and an 8.32-second movie.
- The movie contained 1280x720 H.264 video. All 251 decoded frames had distinct hashes.
- Camera.app also saved a photo after a cold reopening. No Camera.app crash reports appeared.

Camera.app was a regression check. The small test app reproduced the crash.
The final comparison used stock libvcamcaptured in both runs.
Only libcamfix changed. No local 1080p format changes were present.
These results cover one firmware pairing.

The full `VPhone` Debug build and bundle admission passed with Xcode 27.2.
The bundled libcamfix hash matched the clean-branch library used in the final guest run.
The camera geometry, data plane, prewarm, drive gate, loader links, and session lifetime tests passed.

The host regression test covers nil, live sessions, and deallocation.
It also checks that weak tracking does not retain a session after its owner releases it.

```sh
make -C VPhoneGuestComponents test-camfix-session-lifetime
```
