import Foundation

enum VPhoneVirtualMachineError: Error, CustomStringConvertible {
    case hardwareModelNotSupported
    case romNotFound(String)
    case diskNotFound(String)
    case invalidKernelDebugPort(Int)
    case apiSocketUnavailable
    case machineIdentityMismatch(String)
    case notRunning(String)
    case saveRestoreUnsupported(String)
    case networkVolumeConsentPending(String)
    case stateDirectoryNotWritable(String, String)

    var description: String {
        switch self {
        case .hardwareModelNotSupported:
            """
            PV=3 hardware model not supported. Check:
              1. macOS >= 15.0 (Sequoia)
              2. Signed with com.apple.private.virtualization + \
            com.apple.private.virtualization.security-research
              3. SIP/AMFI disabled
            """
        case let .romNotFound(p):
            "ROM not found: \(p)"
        case let .diskNotFound(p):
            "Disk image not found: \(p)"
        case let .invalidKernelDebugPort(port):
            "Invalid kernel debug port: \(port) (expected 6000...65535)"
        case .apiSocketUnavailable:
            "VM has no VSOCK device for the API proxy"
        case let .machineIdentityMismatch(reason):
            "Refusing to start: \(reason)"
        case let .notRunning(state):
            "The VM is \(state); it must be running or paused."
        case let .saveRestoreUnsupported(reason):
            "Virtualization cannot save this VM's state. Blocked by: \(reason)"
        case let .networkVolumeConsentPending(message):
            "Refusing to start: \(message)"
        case let .stateDirectoryNotWritable(path, reason):
            "Refusing to start: cannot create a file in \(path): \(reason)"
        }
    }
}
