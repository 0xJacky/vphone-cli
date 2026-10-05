import AppKit
import Observation
import SwiftUI
import VPhoneDesignKit

// MARK: - Model

/// What the display window's title bar and control bar show, and what their
/// buttons do. The window controller fills it from vphoned's status and the
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
    /// When the screen recording started; nil while not recording.
    var recordingStartedAt: Date?
    /// Room the title bar leaves for the window's own traffic lights.
    var trafficLightInset = DKTitleBar<EmptyView>.defaultTrafficLightInset

    var canPressHome = false
    var canOpenGuestTools = false
    var canRotate = false
    var canTakeScreenshot = false

    @ObservationIgnored var onHome: @MainActor () -> Void = {}
    @ObservationIgnored var onGuestTools: @MainActor () -> Void = {}
    @ObservationIgnored var onRotateLeft: @MainActor () -> Void = {}
    @ObservationIgnored var onCopyScreenshot: @MainActor () -> Void = {}
    @ObservationIgnored var onToggleRecording: @MainActor () -> Void = {}
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
/// and the frame rate when shown), with Guest Tools on the trailing side. The
/// window's own traffic lights are drawn over the room it leaves on the
/// leading side.
struct VPhoneDisplayTitleBar: View {
    let model: VPhoneDisplayChromeModel

    var body: some View {
        DKTitleBar(
            model.machineName,
            tone: model.isAgentConnected ? .success : .warning,
            status: model.isAgentConnected ? VPhoneLocalization.text("Running") : nil,
            os: statusText,
            address: model.isAgentConnected ? model.address : nil,
            actions: [
                DKButtonSpec(
                    VPhoneLocalization.text("Guest Tools"),
                    glyph: .sidebar,
                    size: .icon,
                    isEnabled: model.canOpenGuestTools,
                    id: "guest-tools",
                    action: { model.onGuestTools() },
                ),
            ],
            trafficLightInset: model.trafficLightInset,
        )
    }

    /// Never empty, so the bar keeps the height it was measured at: without
    /// a version the line says whether the agent is there.
    private var statusText: String {
        var text = if model.isAgentConnected, let version = model.iosVersion, !version.isEmpty {
            "iOS \(version)"
        } else {
            VPhoneLocalization.text(model.isAgentConnected ? "Guest agent connected" : "Guest agent not connected")
        }
        if let frameRate = model.frameRate {
            text += " · " + VPhoneLocalization.format("%ld fps", frameRate)
        }
        return text
    }
}

// MARK: - Control Bar

/// The bar under the guest display: rotate and screenshot on the leading
/// side, Home in the center, and recording on the trailing side, where the
/// running timer replaces the record button.
struct VPhoneDisplayControlBar: View {
    let model: VPhoneDisplayChromeModel

    var body: some View {
        if let start = model.recordingStartedAt {
            TimelineView(.periodic(from: start, by: 1)) { context in
                bar(recordingText: VPhoneScreenRecordingStatus.elapsedText(from: start, to: context.date))
            }
        } else {
            bar(recordingText: nil)
        }
    }

    private func bar(recordingText: String?) -> some View {
        DKControlBar(
            leading: [
                DKButtonSpec(
                    VPhoneLocalization.text("Rotate Left"),
                    glyph: .restart,
                    size: .icon,
                    isEnabled: model.canRotate,
                    id: "rotate-left",
                    action: { model.onRotateLeft() },
                ),
                DKButtonSpec(
                    VPhoneLocalization.text("Copy Screenshot"),
                    glyph: .camera,
                    size: .icon,
                    isEnabled: model.canTakeScreenshot,
                    id: "copy-screenshot",
                    action: { model.onCopyScreenshot() },
                ),
            ],
            center: [
                DKButtonSpec(
                    VPhoneLocalization.text("Home"),
                    glyph: .home,
                    size: .largeIcon,
                    isEnabled: model.canPressHome,
                    help: VPhoneLocalization.text("Home Button"),
                    id: "home",
                    action: { model.onHome() },
                ),
            ],
        ) {
            recording(recordingText)
        }
    }

    /// The record button, or while recording the timer, which stops it. A
    /// narrow window drops the word "Recording" before it truncates the time.
    @ViewBuilder
    private func recording(_ elapsed: String?) -> some View {
        if let elapsed {
            let title = VPhoneLocalization.format("Recording %@", elapsed)
            ViewThatFits(in: .horizontal) {
                DKButton(timerSpec(label: title))
                DKButton(timerSpec(label: elapsed))
                    .accessibilityLabel(title)
            }
        } else {
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Start Recording"),
                glyph: .record,
                size: .icon,
                id: "recording",
                action: { model.onToggleRecording() },
            ))
        }
    }

    private func timerSpec(label: String) -> DKButtonSpec {
        DKButtonSpec(
            label,
            glyph: .record,
            variant: .recording,
            help: VPhoneLocalization.text("Stop Recording"),
            id: "recording",
            action: { model.onToggleRecording() },
        )
    }
}
