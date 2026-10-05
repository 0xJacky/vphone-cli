import Foundation
import Testing
@testable import VPhoneVirtualMachineKit

/// The Clipboard page's history: what it lists, in which order, and how Send
/// Again and Clear treat it.
@MainActor
@Suite("Guest clipboard history")
struct VPhoneGuestClipboardHistoryTests {
    private func content(_ text: String?, image: Data? = nil, change: Int = 1) -> VPhoneGuestControl.ClipboardContent {
        .init(
            text: text,
            types: text == nil ? ["public.png"] : ["public.utf8-plain-text"],
            hasImage: image != nil,
            changeCount: change,
            imageData: image,
        )
    }

    @Test
    func `entries are newest first, each with its source`() {
        var history = VPhoneGuestClipboardHistory()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        history.recordRead(content("from guest"), at: start)
        history.recordSent("sent", at: start.addingTimeInterval(1))
        history.recordTyped("typed", at: start.addingTimeInterval(2))

        #expect(history.entries.map(\.text) == ["typed", "sent", "from guest"])
        #expect(history.entries.map(\.kind) == [.typed, .sent, .fromGuest])
        #expect(history.entries.map(\.date) == [start.addingTimeInterval(2), start.addingTimeInterval(1), start])
        #expect(history.entries.first { $0.kind == .fromGuest }?.types == ["public.utf8-plain-text"])
        #expect(history.count == 3)
    }

    @Test
    func `a read is listed once until the guest clipboard changes`() {
        var history = VPhoneGuestClipboardHistory()
        history.recordRead(content("same"))
        history.recordRead(content("same", change: 2))
        #expect(history.count == 1)

        // A send in between does not make the same guest content new.
        history.recordSent("other")
        history.recordRead(content("same", change: 3))
        #expect(history.entries.map(\.kind) == [.sent, .fromGuest])

        history.recordRead(content("changed"))
        #expect(history.entries.map(\.text) == ["changed", "other", "same"])
    }

    @Test
    func `an empty guest clipboard is not listed, an image is`() {
        var history = VPhoneGuestClipboardHistory()
        history.recordRead(content(nil))
        #expect(history.isEmpty)

        let png = Data([0x89, 0x50, 0x4E, 0x47])
        history.recordRead(content(nil, image: png))
        #expect(history.count == 1)
        #expect(history.entries[0].text == nil)
        #expect(history.entries[0].imageData == png)
        #expect(history.entries[0].types == ["public.png"])
    }

    @Test
    func `Send Again types typed text and sets the clipboard for the rest`() {
        typealias Kind = VPhoneGuestClipboardHistory.Entry.Kind
        #expect(Kind.typed.resendMode == .typeKeystrokes)
        #expect(Kind.sent.resendMode == .setClipboard)
        #expect(Kind.fromGuest.resendMode == .setClipboard)
    }

    @Test
    func `Clear empties the history`() {
        var history = VPhoneGuestClipboardHistory()
        history.recordSent("a")
        history.recordTyped("b")
        history.clear()
        #expect(history.isEmpty)
    }

    @Test
    func `the model shows a read and records it`() {
        let model = VPhoneGuestClipboardModel(control: VPhoneGuestControl())
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        model.apply(read: content("hello", change: 42), recording: true, at: date)
        #expect(model.clipboard?.text == "hello")
        #expect(model.clipboard?.changeCount == 42)
        #expect(model.readDate == date)
        #expect(model.canCopyText)
        #expect(!model.canCopyImage)
        #expect(model.history.entries.map(\.kind) == [.fromGuest])

        // A read-back after a send updates On the Guest without a new entry.
        model.apply(read: content("sent text"), recording: false)
        #expect(model.clipboard?.text == "sent text")
        #expect(model.history.count == 1)

        model.clearHistory()
        #expect(model.history.isEmpty)
    }

    @Test
    func `Send Again of typed text needs the guest connected and adds nothing until it is`() async {
        let model = VPhoneGuestClipboardModel(control: VPhoneGuestControl())
        model.history.recordTyped("hunter2")
        let entry = model.history.entries[0]
        await model.sendAgain(entry)
        #expect(model.history.count == 1)
        #expect(model.status?.isError == true)
    }
}
