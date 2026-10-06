import Foundation
import VPhoneDesignKit

// MARK: - Session State

/// Where one terminal tab's shell is. The guest's messages and the end of the
/// connection move it; nothing moves it back, since a tab never reconnects.
enum VPhoneTerminalSessionState: Equatable {
    /// Opening the connection, or waiting for the guest to start the shell.
    case connecting
    /// The shell runs; `shell` is its path in the guest.
    case running(shell: String)
    /// The shell ended.
    case exited(status: Int?, signal: Int?)
    /// The guest started no shell, or could not be reached.
    case failed(String)
    /// The connection ended while the shell ran: the guest restarted, or
    /// vphoned stopped.
    case disconnected

    mutating func apply(_ message: VPhoneTerminalWire.Message) {
        switch (self, message) {
        case let (.connecting, .started(_, shell, _, _)):
            self = .running(shell: shell)
        case let (.connecting, .exited(status, signal)), let (.running, .exited(status, signal)):
            self = .exited(status: status, signal: signal)
        case let (.connecting, .failed(_, message)), let (.running, .failed(_, message)):
            self = .failed(message)
        default:
            break
        }
    }

    /// The connection ended, with `reason` when it never opened.
    mutating func connectionClosed(reason: String?) {
        switch self {
        case .connecting:
            self = .failed(reason ?? VPhoneLocalization.text("The guest closed the terminal before a shell started."))
        case .running:
            self = .disconnected
        case .exited, .failed, .disconnected:
            break
        }
    }

    /// True while the tab has, or is about to have, a shell.
    var isLive: Bool {
        switch self {
        case .connecting, .running: true
        case .exited, .failed, .disconnected: false
        }
    }

    /// A shell that ended with status 0 closes its tab, as `exit` does in
    /// Terminal; any other end keeps the tab, with its output, until closed.
    var closesTab: Bool {
        self == .exited(status: 0, signal: nil)
    }

    /// The tab's status dot.
    var tone: DKTone {
        switch self {
        case .connecting: .warning
        case .running: .success
        case .exited: .idle
        case .failed, .disconnected: .danger
        }
    }

    /// The line written into the terminal when the session ends, or nil while
    /// it is live.
    var notice: String? {
        switch self {
        case .connecting, .running:
            nil
        case let .exited(status, signal):
            if let signal {
                VPhoneLocalization.format("[Process terminated by signal %ld]", signal)
            } else {
                VPhoneLocalization.format("[Process exited with status %ld]", status ?? 0)
            }
        case let .failed(message):
            message
        case .disconnected:
            VPhoneLocalization.text("[Connection to the guest closed]")
        }
    }
}

// MARK: - Tab List

/// The Terminal window's tabs: their order, their numbers and the selection.
/// The first tab is named after the machine, later ones add their number
/// ("research-26 (2)"); numbers go on from the highest open one and start
/// over once every tab is closed.
struct VPhoneTerminalTabList<ID: Hashable & Sendable> {
    struct Entry: Equatable {
        let id: ID
        let number: Int
    }

    private(set) var entries: [Entry] = []
    var selection: ID?

    var isEmpty: Bool {
        entries.isEmpty
    }

    var ids: [ID] {
        entries.map(\.id)
    }

    /// Adds a tab after the others and selects it. Returns its number.
    @discardableResult
    mutating func add(_ id: ID) -> Int {
        let number = (entries.map(\.number).max() ?? 0) + 1
        entries.append(Entry(id: id, number: number))
        selection = id
        return number
    }

    /// Removes a tab. Closing the selected tab selects its right neighbour,
    /// or its left one when it was last, as `DKTabStrip` does.
    mutating func remove(_ id: ID) {
        let tabs = entries.map { DKTab(id: $0.id, title: "") }
        selection = tabs.selectionAfterClosingTab(id, selection: selection)
        entries.removeAll { $0.id == id }
    }

    /// Keeps only the tabs in `ids`, in their order there; returns the ones
    /// dropped. The tab strip edits its own copy of the list this way.
    @discardableResult
    mutating func keep(_ ids: [ID]) -> [ID] {
        let dropped = entries.filter { !ids.contains($0.id) }.map(\.id)
        for id in dropped {
            remove(id)
        }
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        entries.sort { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        return dropped
    }

    func number(of id: ID) -> Int? {
        entries.first { $0.id == id }?.number
    }

    static func title(machine: String, number: Int) -> String {
        number <= 1 ? machine : "\(machine) (\(number))"
    }
}

// MARK: - Availability

/// Whether Window › Terminal can open a shell, and why not.
enum VPhoneTerminalAvailability: Equatable {
    static let capability = "terminal"

    case available
    case notConnected
    /// The connected vphoned predates the terminal.
    case unsupported

    /// `capabilities` is what the agent reported; empty while disconnected.
    init(capabilities: [String]) {
        if capabilities.isEmpty {
            self = .notConnected
        } else {
            self = capabilities.contains(Self.capability) ? .available : .unsupported
        }
    }

    var isAvailable: Bool {
        self == .available
    }

    /// The menu item's tooltip while it is disabled.
    var reason: String? {
        switch self {
        case .available:
            nil
        case .notConnected:
            VPhoneLocalization.text("The guest agent is not connected.")
        case .unsupported:
            VPhoneLocalization.text("The guest agent does not report the “terminal” capability. Update vphoned in the guest to open a terminal.")
        }
    }
}
