import Foundation
import IcliKit
import notify
import VphonedNative

/// Re-applies a foldable guest's saved posture after each boot.
///
/// The posture `display.posture` sets rides two channels: SpringBoard's
/// test-automation pose override — state of the running SpringBoard, gone
/// with it at shutdown — and the virtual hinge preference, which survives
/// but is only read when the provider enumerates. A rebooted guest that had
/// the pose open therefore starts with the hinge reporting open while
/// SpringBoard still holds its default pose, until the pose is set again;
/// SpringBoard's own VM-sub-type restore path cannot stand in, because its
/// `SBFDevicePoseLastKnown*` defaults are written on display-mode
/// transitions, which a single display never makes (measured 2026-10-25:
/// they stay zero). Retry until SpringBoard reports the restored pose, but
/// cancel immediately when an explicit request supersedes the boot snapshot.
///
/// Only a guest whose hinge was configured is touched. The home grid itself
/// still needs a working display-content transition; this restore does not
/// establish one. See Research/Guest/iphone_duo_bringup.md.
enum GuestFoldPose {
    private final class RestoreState: @unchecked Sendable {
        let lock = NSLock()
        var cancelled = false
        var generation: UInt64 = 0
        var explicitRequest = false
        var latestPose: [Int32]?
        var observerInstalled = false
    }

private static let restoration = RestoreState()

    static func requestViewport(for angle: Double) {
        notify_post(angle < 5 ? "com.vphone.display.viewport.apply.cover" : "com.vphone.display.viewport.apply.inner")
    }

    /// A new explicit request supersedes the boot snapshot. Serialize this
    /// with publication so an in-flight retry cannot overwrite the request.
    static func cancelStartupRestore() {
        restoration.lock.withLock {
            restoration.cancelled = true
            restoration.generation &+= 1
            restoration.explicitRequest = true
        }
    }

    /// Capture the actual final state, including a failed request's rollback.
    /// Never retain the requested value as proof that SpringBoard applied it.
    static func finishExplicitRequest() {
        restoration.lock.withLock {
            let actual = vp_device_pose_get()
            restoration.latestPose = poseValues(actual)
            restoration.explicitRequest = false
            restoration.generation &+= 1
        }
    }

    private static func poseValues(_ actual: [String: Any]) -> [Int32]? {
        guard actual["available"] as? Bool == true,
              let orientation = actual["device_orientation"] as? Int32,
              let hinge = actual["hinge"] as? Int32,
              let tabletop = actual["tabletop"] as? Int32,
              (1...4).contains(orientation), (1...4).contains(hinge)
        else { return nil }
        return [orientation, hinge, tabletop]
    }

    private static let restoreQueue = DispatchQueue(label: "vphoned.fold-pose-replay", qos: .utility)

    private static func observeSpringBoardStartup() {
        let install = restoration.lock.withLock {
            if restoration.observerInstalled { return false }
            restoration.observerInstalled = true
            return true
        }
        guard install else { return }
        var token: Int32 = 0
        let status = notify_register_dispatch("com.apple.springboard.finishedstartup", &token, restoreQueue) { _ in
            let generation = restoration.lock.withLock { restoration.generation }
            for delay in [0.5, 1.5, 3.0] {
                restoreQueue.asyncAfter(deadline: .now() + delay) {
                    restoration.lock.withLock {
                        guard restoration.generation == generation, !restoration.explicitRequest,
                              let pose = restoration.latestPose,
                              vp_hinge_get()["enabled"] as? Bool == true else { return }
                        if let angle = vp_hinge_get()["angle"] as? Double {
                            if poseValues(vp_device_pose_get()) != pose {
                                _ = vp_device_pose_set(pose[0], pose[1], pose[2])
                                // The pipeline re-reads the pose only through
                                // this channel; feed it before the viewport
                                // apply so the swap arbitrates from the pose.
                                notify_post("com.vphone.display.orientation.pose.refresh")
                                NSLog("vphoned: replay latest fold pose after SpringBoard startup")
                            }
                            requestViewport(for: angle)
                        }
                    }
                }
            }
        }
        if status != 0 {
            NSLog("vphoned: cannot observe SpringBoard pose lifecycle: %u", status)
        }
    }

    /// SpringBoard is up well inside this on a normal boot; a first boot
    /// after a restore takes longer, and the later attempts cover it. The
    /// setter reports only submission, so read the actual pose before
    /// deciding whether another retry is needed.
    private static let attemptDelays: [TimeInterval] = [8, 12, 15, 20, 30, 45, 60, 90]

    static func startOnStartup() {
        let hinge = vp_hinge_get()
        guard hinge["enabled"] as? Bool == true, let angle = hinge["angle"] as? Double else { return }
        observeSpringBoardStartup()
        NSLog("vphoned: fold pose restore: %.0f° over the boot ladder", angle)
        DispatchQueue.global(qos: .utility).async {
            var waited: TimeInterval = 0
            for delay in attemptDelays {
                Thread.sleep(forTimeInterval: delay - waited)
                waited = delay
                let expectedHinge = hingeState(for: angle)
                // Device 1 is the pose enum's portrait, not the mounted
                // device value: the Duo inner panel presents portrait as
                // device 3 under its rotated mounting.  Resolve against the
                // live map; a later rung corrects an early read that still
                // carries the identity fallback table.
                let portraitDevice = (vp_display_orientation_mapping()["deviceOrientations"] as? [Int])
                    .flatMap { GuestDisplayRotation.resolve("0", deviceOrientations: $0)?.deviceOrientation } ?? 1
                let published = restoration.lock.withLock {
                    guard !restoration.cancelled else { return false }
                    _ = vp_device_pose_set(Int32(portraitDevice), Int32(expectedHinge), 0)
                    _ = vp_hinge_set(angle)
                    requestViewport(for: angle)
                    restoration.latestPose = poseValues(vp_device_pose_get())
                    return true
                }
                guard published else { return }
                // The running scene re-reads the device pose only through
                // the pose-refresh channel; without the poke the pipeline
                // keeps whatever direction it held before the restore.
                notify_post("com.vphone.display.orientation.pose.refresh")
                notify_post("com.vphone.display.orientation.arbitration.refresh")
                notify_post("com.vphone.display.orientation.actuation.refresh")
                let actual = vp_device_pose_get()
                if actual["available"] as? Bool == true,
                   actual["hinge"] as? Int == expectedHinge,
                   interfaceRotationDegrees() == 0 { return }
            }
        }
    }

    /// SpringBoard's hinge-state bands: closed below 5°, open-flat from 170°,
    /// partially open between.
    private static func hingeState(for angle: Double) -> Int {
        if angle < 5 { return 1 }
        if angle >= 170 { return 3 }
        return 2
    }
}
