import SwiftUI
import VPhoneDesignKit

/// The Preferences page: a header with the Read / Write mode, the result
/// style and the read tools; the domain and key fields; the values read, as
/// an outline or as JSON; a detail bar that writes a value; and a status bar.
struct VPhoneGuestPreferencesView: View {
    @Bindable var model: VPhoneGuestPreferencesModel
    @FocusState private var focus: VPhoneGuestPreferencesModel.Field?
    @State private var selection: VPhoneGuestPreferenceEntry.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            domainBar
            resultPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            detailBar
                .guestDetailBarSizing()
            DKStatusBar(
                isConnected: model.control.isConnected,
                text: model.activity?.title ?? model.status?.message,
                detail: resultCount,
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DK.Palette.window)
        .guestToolShortcuts([
            VPhoneGuestToolShortcut(key: "1") { model.mode = .read },
            VPhoneGuestToolShortcut(key: "2") { model.mode = .write },
            VPhoneGuestToolShortcut(key: "r", isEnabled: model.mode == .read && model.canRead) {
                Task { await model.read() }
            },
            VPhoneGuestToolShortcut(key: .return, isEnabled: isEditing && model.canWrite) {
                Task { await model.write() }
            },
        ])
        .onAppear(perform: applyFocusRequest)
        .onChange(of: model.focusRequest) { _, _ in applyFocusRequest() }
        .onChange(of: selection) { _, id in
            // A single click fills the editor; double-click also moves to Write.
            guard let id, let entry = entry(for: id) else { return }
            model.edit(entry, switchToWrite: false)
        }
    }

    private var resultCount: String? {
        guard let result = model.readResult, result.key == nil else { return nil }
        let count = result.entries.count
        return count == 1
            ? String(localized: "1 key", bundle: VPhoneLocalization.bundle)
            : String(localized: "\(count) keys", bundle: VPhoneLocalization.bundle)
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(
            String(localized: "Preferences", bundle: VPhoneLocalization.bundle),
            subtitle: String(localized: "Read or write a preferences domain in the guest", bundle: VPhoneLocalization.bundle),
        ) {
            DKSegmented(
                String(localized: "Mode", bundle: VPhoneLocalization.bundle),
                selection: $model.mode,
                options: VPhoneGuestToolMode.allCases.map { DKSegmentOption($0.title, value: $0) },
            )
            .help(String(localized: "Switch between reading from and writing to the guest (⌘1, ⌘2)", bundle: VPhoneLocalization.bundle))
            if model.mode == .read {
                DKSegmented(
                    String(localized: "Result Style", bundle: VPhoneLocalization.bundle),
                    selection: $model.resultStyle,
                    options: VPhoneGuestPreferencesModel.ResultStyle.allCases.map { DKSegmentOption($0.title, value: $0) },
                )
                .disabled(model.readResult == nil)
                .help(String(localized: "Show the result as an outline or as JSON", bundle: VPhoneLocalization.bundle))
                DKButton(DKButtonSpec(
                    String(localized: "Copy JSON", bundle: VPhoneLocalization.bundle),
                    glyph: .copy,
                    isEnabled: model.canCopyResult,
                    help: String(localized: "Copy the result as JSON", bundle: VPhoneLocalization.bundle),
                ) { model.copyResult() })
                DKButton(DKButtonSpec(
                    String(localized: "Read", bundle: VPhoneLocalization.bundle),
                    glyph: .refresh,
                    variant: .primary,
                    isEnabled: model.canRead,
                    help: String(localized: "Read the key, or every key in the domain when Key is empty (⌘R)", bundle: VPhoneLocalization.bundle),
                ) { Task { await model.read() } })
            }
        }
    }

    // MARK: - Domain

    private var domainBar: some View {
        HStack(spacing: DK.Space.s2) {
            fieldLabel(String(localized: "Domain", bundle: VPhoneLocalization.bundle))
            HStack(spacing: DK.Space.s1) {
                TextField(
                    String(localized: "Domain", bundle: VPhoneLocalization.bundle),
                    text: $model.domain,
                    prompt: Text(verbatim: "com.apple.springboard"),
                )
                .textFieldStyle(.dkFieldMono)
                .focused($focus, equals: .domain)
                .onSubmit(submit)
                Menu {
                    ForEach(VPhoneGuestPreferencesModel.suggestedDomains, id: \.self) { domain in
                        Button(domain) { model.domain = domain }
                    }
                } label: {
                    Image(systemName: DKGlyph.chevronDown.symbolName)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "Common preference domains", bundle: VPhoneLocalization.bundle))
                .accessibilityLabel(String(localized: "Common domains", bundle: VPhoneLocalization.bundle))
            }
            .layoutPriority(2)

            fieldLabel(String(localized: "Key", bundle: VPhoneLocalization.bundle))
                .padding(.leading, DK.Space.s1)
            Group {
                switch model.mode {
                case .read:
                    TextField(
                        String(localized: "Key", bundle: VPhoneLocalization.bundle),
                        text: $model.readKey,
                        prompt: Text("All keys", bundle: VPhoneLocalization.bundle),
                    )
                    .textFieldStyle(.dkFieldMono)
                    .focused($focus, equals: .readKey)
                case .write:
                    TextField(
                        String(localized: "Key", bundle: VPhoneLocalization.bundle),
                        text: $model.writeKey,
                        prompt: Text("Preference key", bundle: VPhoneLocalization.bundle),
                    )
                    .textFieldStyle(.dkFieldMono)
                    .focused($focus, equals: .writeKey)
                }
            }
            .onSubmit(submit)
            .frame(minWidth: 140, maxWidth: 260)
            .layoutPriority(1)
        }
        .labelsHidden()
        .padding(.vertical, DK.Space.s3)
        .padding(.horizontal, DK.Space.s4)
        .overlay(alignment: .bottom) {
            DK.Palette.divider.frame(height: DK.Metric.hairline)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(DK.Typeface.body)
            .foregroundStyle(DK.Palette.inkSecondary)
            .fixedSize()
    }

    // MARK: - Result

    @ViewBuilder
    private var resultPane: some View {
        if let result = model.readResult {
            if model.resultStyle == .json || result.entries.isEmpty {
                jsonView(result)
            } else {
                outline(result)
            }
        } else if model.activity == .reading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: DK.Space.s2) {
            DKIcon(.list, size: 28)
                .foregroundStyle(DK.Palette.muted)
            Text(model.mode == .read
                ? String(localized: "No Preferences Loaded", bundle: VPhoneLocalization.bundle)
                : String(localized: "Write a Preference", bundle: VPhoneLocalization.bundle))
                .font(DK.Typeface.bodyStrong)
                .foregroundStyle(DK.Palette.ink)
            Text(model.mode == .read
                ? String(localized: "Enter a domain, then choose Read. Leave Key empty to read every key in the domain.", bundle: VPhoneLocalization.bundle)
                : String(localized: "Enter a domain and a key, choose the type and value below, then choose Write.", bundle: VPhoneLocalization.bundle))
                .font(DK.Typeface.caption)
                .foregroundStyle(DK.Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(DK.Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func outline(_ result: VPhoneGuestPreferenceReadResult) -> some View {
        Table(result.entries, children: \.children, selection: $selection) {
            TableColumn("Key") { entry in
                DKTableCellView(.mono(entry.key))
                    .help(entry.key)
            }
            .width(min: 140, ideal: 240)

            TableColumn("Type") { entry in
                DKTableCellView(.muted(entry.typeTitle))
            }
            .width(min: 70, ideal: 100, max: 120)

            TableColumn("Value") { entry in
                DKTableCellView(entry.children == nil ? .mono(entry.summary) : .muted(entry.summary))
                    .help(entry.summary)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(DK.Palette.window)
        .contextMenu(forSelectionType: VPhoneGuestPreferenceEntry.ID.self) { ids in
            if let id = ids.first, let entry = entry(for: id) {
                Button("Edit Value…") { model.edit(entry, switchToWrite: true) }
                    .disabled(!model.canEdit(entry))
                Divider()
                Button("Copy Key") { copy(entry.key) }
                Button("Copy Value") { copy(entry.summary) }
                    .disabled(entry.children != nil)
            }
        } primaryAction: { ids in
            if let id = ids.first, let entry = entry(for: id) {
                model.edit(entry, switchToWrite: true)
            }
        }
        .accessibilityLabel("Preference values for \(result.title)")
    }

    private func jsonView(_ result: VPhoneGuestPreferenceReadResult) -> some View {
        ScrollView {
            Text(result.text.isEmpty ? String(localized: "No value.", bundle: VPhoneLocalization.bundle) : result.text)
                .font(DK.Typeface.log)
                .foregroundStyle(result.text.isEmpty ? DK.Palette.muted : DK.Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DK.Space.s3)
                .padding(.horizontal, DK.Space.s4)
        }
        .background(DK.Palette.window)
        .accessibilityLabel("Preference value for \(result.title)")
    }

    // MARK: - Editor

    /// Whether the detail bar shows the editor: in Write mode, or for a
    /// top-level scalar selected in Read mode.
    private var isEditing: Bool {
        if model.mode == .write {
            return true
        }
        guard let selection, let entry = entry(for: selection) else { return false }
        return model.canEdit(entry)
    }

    @ViewBuilder
    private var detailBar: some View {
        if isEditing {
            // In Read mode the selected row already shows the current value.
            DKDetailBar(
                model.trimmedWriteKey.isEmpty
                    ? String(localized: "New Value", bundle: VPhoneLocalization.bundle)
                    : model.trimmedWriteKey,
                note: model.mode == .write
                    ? model.currentWriteValue.map {
                        String(localized: "Current value: \($0.summary) (\($0.typeTitle))", bundle: VPhoneLocalization.bundle)
                    }
                    : nil,
                layout: .row,
            ) {
                editor
            }
        } else {
            DKDetailBar(layout: .row) {
                VPhoneGuestDetailNote(String(localized: "Select a String, Boolean, Integer or Float key to change its value here, or switch to Write to set any key.", bundle: VPhoneLocalization.bundle))
            }
        }
    }

    private var editor: some View {
        HStack(spacing: DK.Space.s2) {
            Picker(String(localized: "Type", bundle: VPhoneLocalization.bundle), selection: $model.writeType) {
                ForEach(VPhoneGuestPreferenceType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .dkFieldPicker()
            valueField
                .frame(maxWidth: .infinity, alignment: .leading)
            DKButton(DKButtonSpec(
                String(localized: "Write", bundle: VPhoneLocalization.bundle),
                glyph: .download,
                isEnabled: model.canWrite,
                help: String(localized: "Write this value to the guest (⌘↩)", bundle: VPhoneLocalization.bundle),
            ) { Task { await model.write() } })
        }
    }

    @ViewBuilder
    private var valueField: some View {
        if model.writeType == .bool {
            DKSegmented(
                String(localized: "Value", bundle: VPhoneLocalization.bundle),
                selection: $model.writeValue,
                options: [DKSegmentOption("true", value: "true"), DKSegmentOption("false", value: "false")],
            )
            .focusable()
            .focused($focus, equals: .value)
            .onAppear {
                if case .failure = model.writeType.parse(model.writeValue) {
                    model.writeValue = "true"
                }
            }
        } else {
            TextField(
                String(localized: "Value", bundle: VPhoneLocalization.bundle),
                text: $model.writeValue,
                prompt: Text(model.writeType.prompt),
            )
            .textFieldStyle(.dkFieldMono)
            .labelsHidden()
            .focused($focus, equals: .value)
            .onSubmit { Task { await model.write() } }
        }
    }

    // MARK: - Helpers

    private func submit() {
        switch model.mode {
        case .read: Task { await model.read() }
        case .write: Task { await model.write() }
        }
    }

    private func entry(for id: VPhoneGuestPreferenceEntry.ID) -> VPhoneGuestPreferenceEntry? {
        func find(_ entries: [VPhoneGuestPreferenceEntry]) -> VPhoneGuestPreferenceEntry? {
            for entry in entries {
                if entry.id == id {
                    return entry
                }
                if let match = entry.children.flatMap(find) {
                    return match
                }
            }
            return nil
        }
        return model.readResult.flatMap { find($0.entries) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func applyFocusRequest() {
        guard let request = model.focusRequest else { return }
        focus = request
        model.focusRequest = nil
    }
}
