import Foundation

/// The four windows a machine can open, after uTerm. Each is an independent
/// window from the Window menu, not a mode of one window: the guest display
/// carries the machine's name alone, the other three add their own name after it.
public enum DKVMWindowKind: String, Sendable, CaseIterable, Hashable {
    case display
    case workspace
    case terminal
    case files

    /// The window's own name, as the Window menu lists it.
    public var name: String {
        switch self {
        case .display: "Display"
        case .workspace: "Workspace"
        case .terminal: "Terminal"
        case .files: "Files"
        }
    }

    /// The window title for a machine: `research-26` for the display,
    /// `research-26 — Workspace` for the others.
    public func title(machine: String) -> String {
        switch self {
        case .display: machine
        case .workspace, .terminal, .files: "\(machine) — \(name)"
        }
    }

    /// Whether the window uses the compact title bar. Only the display window,
    /// which is narrow and tall, keeps the roomy one.
    public var usesCompactTitleBar: Bool {
        self != .display
    }
}
