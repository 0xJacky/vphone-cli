import Darwin
import Foundation

// MARK: - Network volume access

/// macOS asks the user before an app opens files on a network volume (TCC's
/// Network Volumes service). The first such open does not fail: it blocks in
/// the kernel until someone answers the dialog on the Mac's own screen. A
/// state-directory machine whose `MachineState` is an NFS mount hits this on
/// its first launch from a bundle, before Virtualization is even configured,
/// so `vphone-vm` would sit forever with no VM, no API and nothing logged. An
/// ad-hoc signed bundle is known to TCC by its cdhash, so every new bundle
/// build asks again.
///
/// `probe` makes that wait visible and bounded: it creates and removes a file
/// on a thread of its own and gives up after the timeout. The thread may stay
/// blocked; the caller is expected to exit.
public enum VPhoneNetworkVolumeAccess {
    public enum Outcome: Equatable, Sendable {
        case writable
        /// The open did not return in time: most likely the consent dialog.
        case timedOut
        /// The open returned this errno.
        case failed(Int32)
    }

    /// Whether `url` is on a file system macOS does not consider local.
    public static func isNetworkVolume(_ url: URL) -> Bool {
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return false }
        return fs.f_flags & UInt32(MNT_LOCAL) == 0
    }

    /// Creates and removes a file in `directory` the way Foundation's atomic
    /// write does (`O_CREAT | O_EXCL`), waiting at most `timeout`.
    public static func probe(
        directory: URL,
        timeout: TimeInterval,
        create: @escaping @Sendable (String) -> Int32 = createAndRemove,
    ) -> Outcome {
        let path = directory.appendingPathComponent(".vphone-access-\(getpid())").path
        let result = ResultBox()
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            result.set(create(path))
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else { return .timedOut }
        let code = result.get()
        return code == 0 ? .writable : .failed(code)
    }

    /// The message a launch prints when the probe times out.
    public static func consentMessage(directory: URL, waited: TimeInterval) -> String {
        "MachineState at \(directory.path) is on a network volume and opening a file in it "
            + "did not return within \(Int(waited))s. macOS is most likely waiting for consent: "
            + "on this Mac's screen, click Allow in the dialog asking to access files on a network volume, "
            + "or turn VPhone on under System Settings > Privacy & Security > Files & Folders (Network Volumes). "
            + "An ad-hoc signed bundle is asked again after every bundle upgrade."
    }

    public static let createAndRemove: @Sendable (String) -> Int32 = { path in
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return errno }
        close(fd)
        unlink(path)
        return 0
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var code: Int32 = 0
        func set(_ value: Int32) { lock.lock(); code = value; lock.unlock() }
        func get() -> Int32 { lock.lock(); defer { lock.unlock() }; return code }
    }
}
