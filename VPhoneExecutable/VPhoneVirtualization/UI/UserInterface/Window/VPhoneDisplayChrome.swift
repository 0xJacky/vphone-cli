import AppKit
import Observation
import SwiftUI
import VPhoneDesignKit

// MARK: - Model

/// What the display window's title bar shows, and what its Home button
/// does. The window controller fills it from vphoned's status and the
/// menu bar; the bars redraw when it changes.
@MainActor
@Observable
final class VPhoneDisplayChromeModel {
    var machineName = ""
    var isAgentConnected = false
    var iosVersion: String?
    var address: String?
    /// Frames the guest presented in the last second; nil while Show Frame Rate is off.
    var frameRate: Int?
    /// When the screen recording started; nil while not recording. The
    /// status line shows its timer.
    var recordingStartedAt: Date?

    var canPressHome = false

    @ObservationIgnored var onHome: @MainActor () -> Void = {}
}

// MARK: - Recording

extension Notification.Name {
    /// Posted by the Capture menu when a screen recording starts or stops.
    /// `userInfo[VPhoneScreenRecordingStatus.startedAtKey]` holds the start
    /// `Date` while recording and is absent once it stops.
    static let vphoneScreenRecordingDidChange = Notification.Name("VPhoneScreenRecordingDidChange")
}

enum VPhoneScreenRecordingStatus {
    static let startedAtKey = "startedAt"

    @MainActor
    static func post(startedAt: Date?) {
        NotificationCenter.default.post(
            name: .vphoneScreenRecordingDidChange,
            object: nil,
            userInfo: startedAt.map { [startedAtKey: $0] },
        )
    }

    /// "00:42", or "1:02:03" past an hour.
    static func elapsedText(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let (hours, minutes, rest) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%02d:%02d", minutes, rest)
    }
}

// MARK: - Title Bar

/// The machine's name over its status line (state dot, iOS version, address,
/// the frame rate when shown, and the recording's time while recording),
/// with the window buttons on the leading side and Home, the window's one
/// button, on the trailing side, as in 2.6.0. Rotate, screenshots,
/// recording and Guest Tools are in the menu bar.
struct VPhoneDisplayTitleBar: View {
    let model: VPhoneDisplayChromeModel

    var body: some View {
        if let start = model.recordingStartedAt {
            TimelineView(.periodic(from: start, by: 1)) { context in
                bar(recording: VPhoneScreenRecordingStatus.elapsedText(from: start, to: context.date))
            }
        } else {
            bar(recording: nil)
        }
    }

    private func bar(recording: String?) -> some View {
        DKTitleBar(
            model.machineName,
            tone: model.isAgentConnected ? .success : .warning,
            status: model.isAgentConnected ? VPhoneLocalization.text("Running") : nil,
            os: statusText(recording: recording),
            address: model.isAgentConnected ? model.address : nil,
            actions: [
                DKButtonSpec(
                    VPhoneLocalization.text("Home"),
                    glyph: .home,
                    size: .icon,
                    isEnabled: model.canPressHome,
                    help: VPhoneLocalization.text("Home Button"),
                    id: "home",
                    action: { model.onHome() },
                ),
            ],
        )
        .environment(\.dkLocalizationBundle, VPhoneLocalization.bundle)
    }

    /// Never empty, so the bar keeps the height it was measured at: without
    /// a version the line says whether the agent is there.
    private func statusText(recording: String?) -> String {
        var text = if model.isAgentConnected, let version = model.iosVersion, !version.isEmpty {
            "iOS \(version)"
        } else {
            VPhoneLocalization.text(model.isAgentConnected ? "Guest agent connected" : "Guest agent not connected")
        }
        if let frameRate = model.frameRate {
            text += " · " + VPhoneLocalization.format("%ld fps", frameRate)
        }
        if let recording {
            text += " · " + VPhoneLocalization.format("Recording %@", recording)
        }
        return text
    }
}
