import AppKit
import SwiftUI
import VPhoneDesignKit

/// The Clipboard page: what the guest clipboard holds, a composer that sets
/// the guest clipboard or types the text as keystrokes, and a history of the
/// reads, sends and typed text since the VM window opened.
struct VPhoneGuestClipboardView: View {
    @Bindable var model: VPhoneGuestClipboardModel
    @FocusState private var composeFocused: Bool
    @State private var contentWidth: CGFloat = 0

    /// The two columns sit side by side once both get their basis width.
    private static let sideBySideWidth: CGFloat = 440 + 300 + DK.Space.s6 + 2 * DK.Space.s5

    var body: some View {
        VStack(spacing: 0) {
            DKPageHeader(
                String(localized: "Clipboard", bundle: VPhoneLocalization.bundle),
                subtitle: String(localized: "Read what the guest copied, or put text on its clipboard", bundle: VPhoneLocalization.bundle),
            ) {
                DKButton(DKButtonSpec(
                    String(localized: "Refresh", bundle: VPhoneLocalization.bundle),
                    glyph: .refresh,
                    isEnabled: !model.isBusy,
                    help: String(localized: "Read the guest clipboard again (⌘R)", bundle: VPhoneLocalization.bundle),
                ) { Task { await model.refresh() } })
            }
            ScrollView {
                columns
                    .padding(DK.Space.s5)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            DKStatusBar(
                isConnected: model.control.isConnected,
                text: model.activity?.title ?? model.status?.message,
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DK.Palette.window)
        .guestToolShortcuts([
            VPhoneGuestToolShortcut(key: "r", isEnabled: !model.isBusy) {
                Task { await model.refresh() }
            },
            VPhoneGuestToolShortcut(key: .return, isEnabled: model.canSend) {
                Task { await model.submit() }
            },
        ])
        .onAppear {
            applyFocusRequest()
            if model.clipboard == nil, model.mode == .read {
                Task { await model.refresh() }
            }
        }
        .onChange(of: model.focusComposeRequested) { _, _ in applyFocusRequest() }
        .onChange(of: model.mode) { _, mode in
            if mode == .write {
                composeFocused = true
            }
        }
    }

    @ViewBuilder
    private var columns: some View {
        if contentWidth == 0 || contentWidth >= Self.sideBySideWidth {
            HStack(alignment: .top, spacing: DK.Space.s6) {
                VStack(spacing: 28) {
                    guestSection
                    sendSection
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(3)
                historySection
                    .frame(minWidth: 300, maxWidth: .infinity)
                    .layoutPriority(2)
            }
        } else {
            VStack(spacing: 28) {
                guestSection
                sendSection
                historySection
            }
        }
    }

    // MARK: - On the Guest

    private var guestSection: some View {
        VStack(alignment: .leading, spacing: DK.Space.s2) {
            sectionHead(String(localized: "On the Guest", bundle: VPhoneLocalization.bundle)) {
                if let note = readNote {
                    Text(note)
                        .font(DK.Typeface.caption)
                        .foregroundStyle(DK.Palette.muted)
                }
            }
            DKCard {
                guestHead
                guestBody
                cardFooter(note: String(localized: "Copies made in the guest also reach the Mac when you leave the VM window.", bundle: VPhoneLocalization.bundle)) {
                    if model.canCopyText, model.canCopyImage {
                        DKButton(String(localized: "Copy Image", bundle: VPhoneLocalization.bundle), glyph: .image) {
                            model.copyImageToMac()
                        }
                    }
                    DKButton(DKButtonSpec(
                        String(localized: "Copy to Mac", bundle: VPhoneLocalization.bundle),
                        glyph: .copy,
                        variant: .primary,
                        isEnabled: model.canCopyText || model.canCopyImage,
                        help: String(localized: "Copy the guest clipboard to the Mac clipboard", bundle: VPhoneLocalization.bundle),
                    ) { model.copyToMac() })
                }
            }
        }
    }

    private var readNote: String? {
        guard let clipboard = model.clipboard else { return nil }
        let time = model.readDate?.formatted(date: .omitted, time: .standard) ?? "—"
        return String(localized: "Change \(clipboard.changeCount) · read at \(time)", bundle: VPhoneLocalization.bundle)
    }

    private var guestHead: some View {
        HStack(spacing: DK.Space.s2) {
            DKIcon(.clipboard, size: 16)
                .foregroundStyle(DK.Palette.inkSecondary)
            Text(contentTitle)
                .font(DK.Typeface.bodyStrong)
                .foregroundStyle(DK.Palette.ink)
                .padding(.trailing, DK.Space.s1)
            if let types = model.clipboard?.types {
                ForEach(types, id: \.self) { type in
                    DKBadge(type)
                }
            }
            Spacer(minLength: DK.Space.s2)
            if let text = model.clipboard?.text {
                Text(characterCount(text.count))
                    .font(DK.Typeface.caption)
                    .monospacedDigit()
                    .foregroundStyle(DK.Palette.muted)
            }
        }
        .lineLimit(1)
        .padding(.vertical, DK.Space.s3)
        .padding(.horizontal, DK.Space.s4)
    }

    private var contentTitle: String {
        guard let clipboard = model.clipboard else {
            return String(localized: "Not Read", bundle: VPhoneLocalization.bundle)
        }
        switch (clipboard.text != nil, clipboard.imageData != nil) {
        case (true, true): return String(localized: "Text and Image", bundle: VPhoneLocalization.bundle)
        case (true, false): return String(localized: "Text", bundle: VPhoneLocalization.bundle)
        case (false, true): return String(localized: "Image", bundle: VPhoneLocalization.bundle)
        case (false, false): return String(localized: "Empty", bundle: VPhoneLocalization.bundle)
        }
    }

    @ViewBuilder
    private var guestBody: some View {
        let image = model.clipboard?.imageData.flatMap(NSImage.init(data:))
        VStack(alignment: .leading, spacing: DK.Space.s3) {
            if let clipboard = model.clipboard {
                if let text = clipboard.text {
                    ScrollView {
                        Text(text)
                            .font(DK.Typeface.mono)
                            .lineSpacing(4)
                            .foregroundStyle(DK.Palette.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 88, maxHeight: 220)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Guest clipboard text")
                }
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220, alignment: .leading)
                        .accessibilityLabel("Guest clipboard image")
                }
                if clipboard.text == nil, image == nil {
                    placeholder(String(localized: "The guest clipboard holds no text or image. Copy something in the guest, then refresh.", bundle: VPhoneLocalization.bundle))
                }
            } else if model.activity == .reading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                placeholder(String(localized: "Choose Refresh to read the guest clipboard's text, image and types.", bundle: VPhoneLocalization.bundle))
            }
        }
        .padding(DK.Space.s4)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(DK.Typeface.body)
            .foregroundStyle(DK.Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Send to the Guest

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: DK.Space.s2) {
            sectionHead(String(localized: "Send to the Guest", bundle: VPhoneLocalization.bundle)) {
                DKSegmented(
                    String(localized: "How to send", bundle: VPhoneLocalization.bundle),
                    selection: $model.sendMode,
                    options: VPhoneGuestClipboardModel.SendMode.allCases.map { DKSegmentOption($0.title, value: $0) },
                )
            }
            DKCard(.rows) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(modeHelp)
                        .font(DK.Typeface.caption)
                        .foregroundStyle(DK.Palette.muted)
                        .padding(.top, DK.Space.s3)
                        .padding(.horizontal, DK.Space.s4)
                    VPhoneGuestTextEditor(
                        text: $model.composeText,
                        placeholder: String(localized: "Text to send", bundle: VPhoneLocalization.bundle),
                        accessibilityLabel: String(localized: "Text to send to the guest", bundle: VPhoneLocalization.bundle),
                        bordered: false,
                        focus: $composeFocused,
                    )
                    .frame(minHeight: 150)
                    .padding(.bottom, DK.Space.s2)
                }
                cardFooter(note: sendNote) {
                    DKButton(DKButtonSpec(
                        String(localized: "Paste from Mac", bundle: VPhoneLocalization.bundle),
                        glyph: .clipboard,
                        help: String(localized: "Replace the text above with the Mac clipboard text", bundle: VPhoneLocalization.bundle),
                    ) { model.pasteFromMac() })
                    DKButton(DKButtonSpec(
                        sendLabel,
                        glyph: .send,
                        variant: .primary,
                        isEnabled: model.canSend,
                        help: model.sendMode == .setClipboard
                            ? String(localized: "Set the guest clipboard to this text (⌘↩)", bundle: VPhoneLocalization.bundle)
                            : String(localized: "Type this text into the guest (⌘↩)", bundle: VPhoneLocalization.bundle),
                    ) { Task { await model.submit() } })
                }
            }
        }
    }

    private var modeHelp: String {
        switch model.sendMode {
        case .setClipboard:
            String(localized: "Replaces the guest clipboard. Paste it in the guest with ⌘V.", bundle: VPhoneLocalization.bundle)
        case .typeKeystrokes:
            String(localized: "Typed into the focused field in the guest, one key at a time.", bundle: VPhoneLocalization.bundle)
        }
    }

    private var sendNote: String {
        let count = characterCount(model.composeText.count)
        switch model.sendMode {
        case .setClipboard:
            return count
        case .typeKeystrokes:
            let skipped = VPhoneGuestKeystrokes(text: model.composeText).skipped
            let rule = String(localized: "ASCII only. Other characters are skipped.", bundle: VPhoneLocalization.bundle)
            return skipped == 0 ? rule : rule + " " + String(localized: "\(skipped) will be skipped.", bundle: VPhoneLocalization.bundle)
        }
    }

    private var sendLabel: String {
        model.sendMode == .setClipboard
            ? String(localized: "Send", bundle: VPhoneLocalization.bundle)
            : String(localized: "Type", bundle: VPhoneLocalization.bundle)
    }

    // MARK: - History

    private var historySection: some View {
        let history = model.history
        let note = history.isEmpty
            ? String(localized: "Nothing yet", bundle: VPhoneLocalization.bundle)
            : history.count == 1
            ? String(localized: "This VM window session · 1 item", bundle: VPhoneLocalization.bundle)
            : String(localized: "This VM window session · \(history.count) items", bundle: VPhoneLocalization.bundle)
        let clear = history.isEmpty ? nil : DKButtonSpec(String(localized: "Clear", bundle: VPhoneLocalization.bundle)) {
            model.clearHistory()
        }
        return DKSection(
            String(localized: "History", bundle: VPhoneLocalization.bundle),
            note: note,
            accessory: clear,
            items: history.isEmpty ? [emptyHistoryItem] : history.map(historyItem),
        )
    }

    private var emptyHistoryItem: DKListItem {
        DKListItem(
            String(localized: "No clipboard history", bundle: VPhoneLocalization.bundle),
            lines: [DKListItem.Line(String(localized: "Text read from or sent to the guest appears here while the VM window is open.", bundle: VPhoneLocalization.bundle))],
        )
    }

    private func historyItem(_ entry: VPhoneGuestClipboardModel.HistoryEntry) -> DKListItem {
        let badge = switch entry.kind {
        case .fromGuest: DKListItem.Badge(String(localized: "From guest", bundle: VPhoneLocalization.bundle), tone: .info)
        case .sent: DKListItem.Badge(String(localized: "Sent", bundle: VPhoneLocalization.bundle), tone: .success)
        case .typed: DKListItem.Badge(String(localized: "Typed", bundle: VPhoneLocalization.bundle), tone: .neutral)
        }
        let time = entry.date.formatted(date: .omitted, time: .standard)
        let action = switch entry.kind {
        case .fromGuest:
            DKButtonSpec(String(localized: "Copy to Mac", bundle: VPhoneLocalization.bundle), glyph: .copy) {
                model.copyToMac(entry)
            }
        case .sent, .typed:
            DKButtonSpec(String(localized: "Send Again", bundle: VPhoneLocalization.bundle), glyph: .send, isEnabled: !model.isBusy) {
                Task { await model.sendAgain(entry) }
            }
        }
        return DKListItem(
            entry.text.map(Self.preview) ?? String(localized: "Image", bundle: VPhoneLocalization.bundle),
            monospacedTitle: entry.text != nil,
            badges: [badge],
            lines: [DKListItem.Line("\(time) · \(meta(for: entry))")],
            actions: [action],
            id: entry.id.uuidString,
        )
    }

    private func meta(for entry: VPhoneGuestClipboardModel.HistoryEntry) -> String {
        if let text = entry.text {
            return characterCount(text.count)
        }
        var parts = entry.types.filter { $0.hasPrefix("public.") && $0 != "public.utf8-plain-text" }
        if let data = entry.imageData, let image = NSBitmapImageRep(data: data) {
            parts.append("\(image.pixelsWide) × \(image.pixelsHigh)")
        }
        return parts.joined(separator: " · ")
    }

    /// The first lines of a history item, short enough for a list row.
    private static func preview(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(3)
        var preview = lines.joined(separator: "\n")
        if preview.count > 160 {
            preview = String(preview.prefix(160))
        }
        return preview.count < text.count ? preview + "…" : preview
    }

    // MARK: - Parts

    private func sectionHead(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: DK.Space.s3) {
            Text(title)
                .font(DK.Typeface.sectionTitle)
                .foregroundStyle(DK.Palette.muted)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DK.Space.s2)
            trailing()
        }
        .padding(.horizontal, DK.Space.s1)
    }

    /// A note with buttons after it, or under it when the card is narrow.
    private func cardFooter(note: String, @ViewBuilder buttons: () -> some View) -> some View {
        let buttons = buttons()
        let text = Text(note)
            .font(DK.Typeface.caption)
            .foregroundStyle(DK.Palette.muted)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DK.Space.s2) {
                text
                    .lineLimit(2)
                    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                HStack(spacing: DK.Space.s2) { buttons }
            }
            VStack(alignment: .leading, spacing: DK.Space.s2) {
                text
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DK.Space.s2) { buttons }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, DK.Space.s4)
        .background(DK.Palette.window)
    }

    private func characterCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 character", bundle: VPhoneLocalization.bundle)
            : String(localized: "\(count) characters", bundle: VPhoneLocalization.bundle)
    }

    private func applyFocusRequest() {
        guard model.focusComposeRequested else { return }
        composeFocused = true
        model.focusComposeRequested = false
    }
}
