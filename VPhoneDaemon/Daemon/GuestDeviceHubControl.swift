import Foundation
import VphonedNative

/// Folds and turns an iPhone Duo guest as Xcode's DeviceHub asks
/// (vphoned_devicehub.m decodes its controls). A closed / book / open button
/// animates DeviceHub's hinge from the current angle to the target, sending a
/// value every frame, and DeviceHub then waits for the device's hinge to
/// agree. SpringBoard folds itself in one sweep, so a run of values is folded
/// once it settles, to where it ended. The orientation picker sets the device
/// orientation. Both go through the paths `display.posture` uses, so the host
/// window, which polls the fold angle, follows too.
enum GuestDeviceHubControl {
    private final class Pending: @unchecked Sendable {
        /// Owned by `queue`.
        var generation = 0
    }

    private static let pending = Pending()
    private static let queue = DispatchQueue(label: "vphoned.devicehub-fold", qos: .userInitiated)
    /// Longer than DeviceHub's frame interval, short enough to feel direct.
    private static let settle: DispatchTimeInterval = .milliseconds(200)
    /// Apple's DeviceOrientation names, as the picker sends them.
    private static let orientations: [String: Int32] = [
        "portrait": 1, "portraitUpsideDown": 2, "landscapeLeft": 3, "landscapeRight": 4, "faceUp": 5, "faceDown": 6,
    ]

    static func startOnStartup() {
        guard vp_devicehub_controls_start({ control in handle(control) }) else { return }
        NSLog("vphoned: following DeviceHub's fold controls")
    }

    private static func handle(_ control: [AnyHashable: Any]) {
        let value = control["value"]
        switch control["source"] as? String {
        case "hinge-slider-control":
            guard let angle = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init),
                  angle.isFinite
            else { return }
            // DeviceHub draws a closed or open hinge state at 0 or 180 degrees
            // whatever its own animation shows, so a reading still at the old
            // pose pulled its model back there between the end of the run and
            // the fold. The reading follows the run; the fold then sets the
            // hinge to where it ended, or back if it does not run.
            if !vp_core_motion_hinge() {
                let reading = min(max(angle, 0), 180)
                vp_hinge_reading_publish(reading, Int32(GuestAPI.hingeState(for: reading)))
            }
            queue.async {
                pending.generation &+= 1
                let generation = pending.generation
                queue.asyncAfter(deadline: .now() + settle) {
                    guard pending.generation == generation else { return }
                    do {
                        try GuestAPI.foldFromDeviceHub(angle: angle)
                    } catch {
                        NSLog("vphoned: DeviceHub fold to %.0f° failed: %@", angle, "\(error)")
                        if !vp_core_motion_hinge(), let held = (vp_hinge_get()["angle"] as? NSNumber)?.doubleValue {
                            vp_hinge_reading_publish(held, Int32(GuestAPI.hingeState(for: held)))
                        }
                    }
                }
            }
        case "orientation-picker-control":
            guard let name = value as? String, let orientation = orientations[name] else { return }
            queue.async {
                do {
                    try GuestAPI.orientFromDeviceHub(orientation)
                } catch {
                    NSLog("vphoned: DeviceHub orientation %@ failed: %@", name, "\(error)")
                }
            }
        default:
            break
        }
    }
}
