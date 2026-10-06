import Foundation
import GhosttyTerminal
import Observation
import VPhoneDesignKit

// MARK: - Theme

/// Launchpad's terminal look (`VPhoneLaunchpadTerminalTheme`), at a reading
/// size. The ground is `DK.Palette.terminalBackground`, drawn by the window
/// behind a clear terminal.
enum VPhoneTerminalTheme {
    static let configuration = TerminalConfiguration {
        $0.withCursorStyle(.block)
        $0.withCursorStyleBlink(true)
        $0.withFontSize(12)
        $0.withFontThicken(true)
        $0.withWindowPaddingX(12)
        $0.withWindowPaddingY(8)
        $0.withCustom("window-padding-color", "extend")
        $0.withBackgroundOpacity(0)
        // Ghostty's own window and tab shortcuts would take these keys before
        // the menu bar; the window's menus own them. Copy, Paste, Select All,
        // ⌘K and the font size keys stay Ghostty's.
        for key in ["super+t", "super+w", "super+shift+w", "super+alt+w", "super+n", "super+q", "super+d",
                    "super+shift+d", "super+comma", "super+shift+comma", "super+enter", "super+ctrl+f"]
        {
            $0.withCustom("keybind", "\(key)=unbind")
        }
    }

    static let theme = TerminalTheme(
        light: TerminalConfiguration {
            $0.withBackground("feffff")
            $0.withForeground("000000")
            $0.withCursorColor("98989d")
            $0.withCursorText("ffffff")
            $0.withSelectionBackground("abd8ff")
            $0.withSelectionForeground("000000")
            palette(&$0)
        },
        dark: TerminalConfiguration {
            $0.withBackground("1e1e1e")
            $0.withForeground("ffffff")
            $0.withCursorColor("98989d")
            $0.withCursorText("000000")
            $0.withSelectionBackground("3f638b")
            $0.withSelectionForeground("ffffff")
            palette(&$0)
        },
    )

    private static func palette(_ builder: inout TerminalConfiguration.Builder) {
        let colors = [
            "#1a1a1a", "#cc372e", "#26a439", "#cdac08", "#0869cb", "#9647bf", "#479ec2", "#98989d",
            "#464646", "#ff453a", "#32d74b", "#e5bc00", "#0a84ff", "#bf5af2", "#69c9f2", "#ffffff",
        ]
        for (index, color) in colors.enumerated() {
            builder.withPalette(index, color: color)
        }
    }
}

// MARK: - Session

/// One Terminal tab: a Ghostty terminal and the guest shell behind it.
///
/// The connection opens once Ghostty reports the terminal's size, so the
/// shell starts at the size it is shown at, or after a short wait when the
/// size never comes. Output goes from the connection's event loop straight
/// into Ghostty; only the shell's state comes to the main actor.
@MainActor
@Observable
final class VPhoneTerminalSession: Identifiable {
    let id = UUID()
    private(set) var state: VPhoneTerminalSessionState = .connecting

    @ObservationIgnored let view: TerminalViewState
    @ObservationIgnored fileprivate let terminal: InMemoryTerminalSession
    @ObservationIgnored private let connection: VPhoneTerminalConnection
    @ObservationIgnored private let relay: VPhoneTerminalRelay
    @ObservationIgnored private weak var control: VPhoneGuestControl?
    @ObservationIgnored private let machineName: String
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isClosed = false
    /// Called after the state changes, and when the shell ended cleanly.
    @ObservationIgnored var onStateChange: ((VPhoneTerminalSession) -> Void)?

    /// How long to wait for Ghostty's first size before opening at 80×24.
    static let sizeWait: Duration = .milliseconds(600)

    init(control: VPhoneGuestControl, machineName: String) {
        self.control = control
        self.machineName = machineName
        let connection = VPhoneTerminalConnection()
        let relay = VPhoneTerminalRelay()
        self.connection = connection
        self.relay = relay
        terminal = InMemoryTerminalSession(
            write: { data in connection.send(data) },
            resize: { viewport in
                connection.resize(VPhoneTerminalWire.Size(columns: Int(viewport.columns), rows: Int(viewport.rows)))
                Task { @MainActor in relay.session?.start() }
            },
        )
        view = TerminalViewState(theme: VPhoneTerminalTheme.theme, terminalConfiguration: VPhoneTerminalTheme.configuration)
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(terminal))
        relay.session = self

        let terminal = terminal
        connection.setHandlers(.init(
            output: { data in terminal.receive(data) },
            message: { message in Task { @MainActor in relay.session?.received(message) } },
            closed: { reason in Task { @MainActor in relay.session?.connectionClosed(reason: reason) } },
        ))
        Task { [weak self] in
            try? await Task.sleep(for: Self.sizeWait)
            self?.start()
        }
    }

    /// Opens the connection, once.
    func start() {
        guard !hasStarted, !isClosed else { return }
        hasStarted = true
        guard let control, control.isConnected else {
            connectionClosed(reason: VPhoneLocalization.text("The guest agent is not connected."))
            return
        }
        let size = connection.size ?? .fallback
        let machineName = machineName
        Task {
            do {
                let socket = try await control.openSocket()
                connection.start(socket: socket, size: size, machineName: machineName)
            } catch {
                connectionClosed(reason: String(describing: error))
            }
        }
    }

    /// Ends the shell. The tab is going away; nothing more is shown.
    func close() {
        isClosed = true
        relay.session = nil
        onStateChange = nil
        connection.close()
    }

    // MARK: Guest Side

    fileprivate func received(_ message: VPhoneTerminalWire.Message) {
        let previous = state
        state.apply(message)
        finish(from: previous)
    }

    fileprivate func connectionClosed(reason: String?) {
        let previous = state
        state.connectionClosed(reason: reason)
        finish(from: previous)
    }

    /// Writes the closing line once the shell is gone, dimmed, or red for a
    /// failure, after the output already queued.
    private func finish(from previous: VPhoneTerminalSessionState) {
        guard state != previous else { return }
        if previous.isLive, !state.isLive, !state.closesTab, let notice = state.notice {
            let color = if case .failed = state { "\u{1B}[31m" } else { "\u{1B}[2m" }
            let lines = notice.replacingOccurrences(of: "\n", with: "\r\n")
            terminal.receive("\r\n\(color)\(lines)\u{1B}[0m\r\n")
        }
        onStateChange?(self)
    }
}

/// Lets Ghostty's and NIO's threads reach a session without keeping it alive.
@MainActor
private final class VPhoneTerminalRelay {
    weak var session: VPhoneTerminalSession?
}

// MARK: - Automation

extension VPhoneTerminalSession {
    /// Bytes for the shell, as the keyboard would send them ("\r" is Return).
    func type(_ text: String) {
        terminal.sendInput(Data(text.utf8))
    }

    /// The terminal's visible rows, nil before Ghostty draws it.
    var visibleText: String? {
        terminal.readViewportText()
    }
}
