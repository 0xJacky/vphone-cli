import Foundation

/// Interface requests use UIKit orientation codes; the native scene supplies
/// the inverse device map, including a foldable panel's mounting transform.
struct GuestDisplayRotation: Equatable, Sendable {
    let interfaceDegrees: Int
    let deviceOrientation: Int
    let accelerometerDegrees: Int

    static func resolve(_ spec: String, deviceOrientations: [Int]) -> Self? {
        guard deviceOrientations.count == 4, Set(deviceOrientations) == Set(1 ... 4) else { return nil }
        let interfaceOrientation: Int
        switch spec.lowercased() {
        case "0", "portrait": interfaceOrientation = 1
        case "90", "landscape-left", "left": interfaceOrientation = 4
        case "180", "upside-down", "portrait-upside-down": interfaceOrientation = 2
        case "270", "landscape-right", "right": interfaceOrientation = 3
        default: return nil
        }
        let device = deviceOrientations[interfaceOrientation - 1]
        let degrees = [1: 0, 2: 180, 3: 270, 4: 90][device]!
        let interfaceDegrees = [1: 0, 2: 180, 3: 270, 4: 90][interfaceOrientation]!
        return Self(interfaceDegrees: interfaceDegrees, deviceOrientation: device, accelerometerDegrees: degrees)
    }
}
