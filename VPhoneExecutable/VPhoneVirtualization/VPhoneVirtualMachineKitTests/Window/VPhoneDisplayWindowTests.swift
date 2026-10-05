import AppKit
import Testing
@testable import VPhoneVirtualMachineKit

/// The display window's bars: the recording timer and the room they take
/// around the guest display.
@Suite("Display window")
struct VPhoneDisplayWindowTests {
    @Test
    func `the recording timer counts minutes and seconds, then hours`() {
        let start = Date(timeIntervalSince1970: 1000)
        let elapsed = { (seconds: Double) in
            VPhoneScreenRecordingStatus.elapsedText(from: start, to: start.addingTimeInterval(seconds))
        }
        #expect(elapsed(0) == "00:00")
        #expect(elapsed(42) == "00:42")
        #expect(elapsed(42.9) == "00:42")
        #expect(elapsed(600) == "10:00")
        #expect(elapsed(3599) == "59:59")
        #expect(elapsed(3723) == "1:02:03")
        // A clock that steps back shows zero rather than a negative time.
        #expect(elapsed(-5) == "00:00")
    }

    @Test
    func `the bars' insets come off the window and go back on`() {
        let insets = NSEdgeInsets(top: 80, left: 16, bottom: 80, right: 16)
        let content = NSRect(x: 100, y: 200, width: 425, height: 1012)
        let display = content.inset(by: insets)
        #expect(display == NSRect(x: 116, y: 280, width: 393, height: 852))
        #expect(display.outset(by: insets) == content)
    }

    @MainActor
    @Test
    func `recording posts its start and its stop`() async {
        let start = Date(timeIntervalSince1970: 2000)
        let received = Received()
        let observer = NotificationCenter.default.addObserver(
            forName: .vphoneScreenRecordingDidChange, object: nil, queue: nil,
        ) { notification in
            let date = notification.userInfo?[VPhoneScreenRecordingStatus.startedAtKey] as? Date
            MainActor.assumeIsolated { received.dates.append(date) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        VPhoneScreenRecordingStatus.post(startedAt: start)
        VPhoneScreenRecordingStatus.post(startedAt: nil)
        #expect(received.dates == [start, nil])
    }

    @MainActor
    private final class Received {
        var dates: [Date?] = []
    }
}
