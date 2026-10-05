import AppKit
import Foundation

@MainActor
@Observable
final class VPhoneGuestClipboardModel {
    enum Activity {
        case reading
        case sending
        case typing

        var title: String {
            switch self {
            case .reading: String(localized: "Reading guest clipboard…", bundle: VPhoneLocalization.bundle)
            case .sending: String(localized: "Sending text to guest…", bundle: VPhoneLocalization.bundle)
            case .typing: String(localized: "Typing text into the guest…", bundle: VPhoneLocalization.bundle)
            }
        }
    }

    /// How Send to the Guest delivers the text.
    enum SendMode: String, CaseIterable, Identifiable {
        /// Replaces the guest clipboard; the user pastes it in the guest.
        case setClipboard
        /// Types the text into the focused field, one key at a time.
        case typeKeystrokes

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .setClipboard: String(localized: "Set Clipboard", bundle: VPhoneLocalization.bundle)
            case .typeKeystrokes: String(localized: "Type as Keystrokes", bundle: VPhoneLocalization.bundle)
            }
        }
    }

    typealias HistoryEntry = VPhoneGuestClipboardHistory.Entry

    let control: VPhoneGuestControl
    /// The part of the page the Data menu opened it for: reading the guest
    /// clipboard, or writing to it (which focuses the compose editor).
    var mode: VPhoneGuestToolMode = .read
    /// Set to move focus to the compose editor the next time the view updates.
    var focusComposeRequested = false
    var sendMode: SendMode = .setClipboard
    private(set) var activity: Activity?
    private(set) var status: VPhoneGuestToolStatus?
    private(set) var clipboard: VPhoneGuestControl.ClipboardContent?
    private(set) var readDate: Date?
    /// Lives as long as this model, which the VM window owns.
    var history = VPhoneGuestClipboardHistory()
    var composeText = ""

    var isBusy: Bool {
        activity != nil
    }

    var canCopyText: Bool {
        clipboard?.text != nil
    }

    var canCopyImage: Bool {
        clipboard?.imageData != nil
    }

    var canSend: Bool {
        !composeText.isEmpty && !isBusy
    }

    init(control: VPhoneGuestControl) {
        self.control = control
    }

    // MARK: - Read

    func refresh() async {
        await read(recording: true)
    }

    private func read(recording: Bool) async {
        guard activity == nil else { return }
        activity = .reading
        defer { activity = nil }
        do {
            let content = try await control.clipboardGet()
            apply(read: content, recording: recording)
        } catch {
            fail(String(localized: "Unable to read the guest clipboard. Check the connection, then try again.", bundle: VPhoneLocalization.bundle))
        }
    }

    /// Shows what the guest clipboard holds and, when `recording`, adds it to
    /// the history.
    func apply(read content: VPhoneGuestControl.ClipboardContent, recording: Bool, at date: Date = .now) {
        clipboard = content
        readDate = date
        status = nil
        if recording {
            history.recordRead(content, at: date)
        }
    }

    func copyTextToMac() {
        guard let text = clipboard?.text else { return }
        writeToMac(text: text)
        succeed(String(localized: "Copied guest text to the Mac clipboard.", bundle: VPhoneLocalization.bundle))
    }

    func copyImageToMac() {
        guard let data = clipboard?.imageData, writeToMac(imageData: data) else { return }
        succeed(String(localized: "Copied guest image to the Mac clipboard.", bundle: VPhoneLocalization.bundle))
    }

    /// Copies what the guest holds: its text, or its image when it has no text.
    func copyToMac() {
        if canCopyText {
            copyTextToMac()
        } else {
            copyImageToMac()
        }
    }

    // MARK: - Write

    /// Delivers the compose text the way `sendMode` says.
    func submit() async {
        switch sendMode {
        case .setClipboard: await send()
        case .typeKeystrokes: typeAsKeystrokes()
        }
    }

    func send() async {
        await send(composeText)
    }

    private func send(_ text: String) async {
        guard !text.isEmpty, activity == nil else { return }
        activity = .sending
        do {
            try await control.clipboardSet(text: text)
        } catch {
            activity = nil
            fail(String(localized: "Unable to set the guest clipboard. Check the connection, then try again.", bundle: VPhoneLocalization.bundle))
            return
        }
        activity = nil
        history.recordSent(text)

        // Read it back so On the Guest shows what the guest now holds.
        await read(recording: false)
        succeed(
            text.count == 1
                ? String(localized: "Sent 1 character to the guest clipboard.", bundle: VPhoneLocalization.bundle)
                : String(localized: "Sent \(text.count) characters to the guest clipboard.", bundle: VPhoneLocalization.bundle),
        )
    }

    func typeAsKeystrokes() {
        type(composeText)
    }

    /// Types `text` into the guest's focused field as key presses queued
    /// through vphoned. Characters a US keyboard cannot type are skipped.
    private func type(_ text: String) {
        guard !text.isEmpty, activity == nil else { return }
        guard control.isConnected else {
            fail(String(localized: "The guest agent is not connected. Wait for it to connect, then try again.", bundle: VPhoneLocalization.bundle))
            return
        }
        guard control.guestCapabilities.contains("hid") else {
            fail(String(localized: "Update the guest agent to type text into the guest.", bundle: VPhoneLocalization.bundle))
            return
        }
        let plan = VPhoneGuestKeystrokes(text: text)
        guard !plan.keys.isEmpty else {
            fail(String(localized: "Nothing to type. Only ASCII characters can be typed.", bundle: VPhoneLocalization.bundle))
            return
        }
        plan.send(through: control)
        history.recordTyped(text)

        let typed = plan.keys.count
        if plan.skipped == 0 {
            succeed(
                typed == 1
                    ? String(localized: "Typed 1 character into the guest.", bundle: VPhoneLocalization.bundle)
                    : String(localized: "Typed \(typed) characters into the guest.", bundle: VPhoneLocalization.bundle),
            )
        } else {
            succeed(String(localized: "Typed \(typed) characters into the guest. Skipped \(plan.skipped) that are not ASCII.", bundle: VPhoneLocalization.bundle))
        }
    }

    func pasteFromMac() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            fail(String(localized: "The Mac clipboard has no text.", bundle: VPhoneLocalization.bundle))
            return
        }
        composeText = text
        status = nil
    }

    // MARK: - History

    /// Copies a history item to the Mac clipboard: its text, or its image.
    func copyToMac(_ entry: HistoryEntry) {
        if let text = entry.text {
            writeToMac(text: text)
        } else if let data = entry.imageData, writeToMac(imageData: data) {
            // Written.
        } else {
            return
        }
        succeed(String(localized: "Copied a history item to the Mac clipboard.", bundle: VPhoneLocalization.bundle))
    }

    /// Sends or types a history item's text again, the way it went the first time.
    func sendAgain(_ entry: HistoryEntry) async {
        guard let text = entry.text else { return }
        switch entry.kind.resendMode {
        case .typeKeystrokes: type(text)
        case .setClipboard: await send(text)
        }
    }

    func clearHistory() {
        history.clear()
    }

    // MARK: - Mac Clipboard

    private func writeToMac(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func writeToMac(imageData data: Data) -> Bool {
        guard let image = NSImage(data: data) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        return true
    }

    // MARK: - Status

    private func succeed(_ message: String) {
        status = VPhoneGuestToolStatus(message: message, isError: false)
    }

    private func fail(_ message: String) {
        status = VPhoneGuestToolStatus(message: message, isError: true)
    }
}

// MARK: - History

/// The clipboard reads, sends and typed text of one VM window session,
/// newest first.
struct VPhoneGuestClipboardHistory {
    /// One clipboard read, send or typed text.
    struct Entry: Identifiable {
        enum Kind {
            case fromGuest
            case sent
            case typed

            /// How Send Again delivers the entry: typed text is typed again,
            /// anything else goes back on the guest clipboard.
            var resendMode: VPhoneGuestClipboardModel.SendMode {
                self == .typed ? .typeKeystrokes : .setClipboard
            }
        }

        let id = UUID()
        let kind: Kind
        let text: String?
        let imageData: Data?
        let types: [String]
        let date: Date
    }

    private(set) var entries: [Entry] = []

    var isEmpty: Bool {
        entries.isEmpty
    }

    var count: Int {
        entries.count
    }

    /// Adds a guest read, unless it holds nothing or the same content as the
    /// last read already listed.
    mutating func recordRead(_ content: VPhoneGuestControl.ClipboardContent, at date: Date = .now) {
        guard content.text != nil || content.imageData != nil else { return }
        if let last = entries.first(where: { $0.kind == .fromGuest }),
           last.text == content.text, last.imageData == content.imageData
        {
            return
        }
        entries.insert(
            Entry(kind: .fromGuest, text: content.text, imageData: content.imageData, types: content.types, date: date),
            at: 0,
        )
    }

    mutating func recordSent(_ text: String, at date: Date = .now) {
        entries.insert(Entry(kind: .sent, text: text, imageData: nil, types: [], date: date), at: 0)
    }

    mutating func recordTyped(_ text: String, at date: Date = .now) {
        entries.insert(Entry(kind: .typed, text: text, imageData: nil, types: [], date: date), at: 0)
    }

    mutating func clear() {
        entries.removeAll()
    }
}
