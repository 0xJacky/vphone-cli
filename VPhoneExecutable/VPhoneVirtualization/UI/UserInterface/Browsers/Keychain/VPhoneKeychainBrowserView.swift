import AppKit
import SwiftUI
import VPhoneDesignKit

/// The Keychain page: a header with the item type filter, Reveal Value, an
/// actions menu, Refresh and search; the items table; a detail bar for the
/// selection; an optional diagnostics log; and a status bar.
struct VPhoneKeychainBrowserView: View {
    @Bindable var model: VPhoneKeychainBrowserModel

    var body: some View {
        VStack(spacing: 0) {
            header
            tableView
            if model.showDiagnostics {
                diagnosticsPanel
            }
            detailBar
                .guestDetailBarSizing()
            DKStatusBar(
                isConnected: model.control.isConnected,
                text: model.isLoading ? VPhoneLocalization.text("Loading keychain items…") : nil,
                detail: model.statusText,
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DK.Palette.window)
        .task { await model.refresh() }
        .onChange(of: model.control.isConnected) { _, connected in
            if connected, model.items.isEmpty {
                Task { await model.refresh() }
            }
        }
        .onChange(of: model.filterClass) { _, _ in model.selection.removeAll() }
        .onChange(of: model.searchText) { _, _ in model.selection.removeAll() }
        .alert(
            "Error",
            isPresented: .init(
                get: { model.error != nil },
                set: {
                    if !$0 {
                        model.error = nil
                    }
                },
            ),
        ) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
        .confirmationDialog(
            "Delete the selected keychain items?",
            isPresented: .init(
                get: { model.pendingDeletion != nil },
                set: {
                    if !$0 {
                        model.pendingDeletion = nil
                    }
                },
            ),
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                let ids = model.pendingDeletion ?? []
                model.pendingDeletion = nil
                Task { await model.delete(ids: ids) }
            }
            Button("Cancel", role: .cancel) { model.pendingDeletion = nil }
        } message: {
            Text("The guest removes them from its keychain. This cannot be undone.")
        }
        .sheet(item: $model.editing) { _ in
            editSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(VPhoneLocalization.text("Keychain"), subtitle: model.statusText) {
            DKSegmented(
                VPhoneLocalization.text("Item Type"),
                selection: $model.filterClass,
                options: VPhoneKeychainBrowserModel.classFilters.map {
                    DKSegmentOption(VPhoneLocalization.text($0.label), value: $0.value)
                },
            )
            .help(VPhoneLocalization.text("Filter keychain items by type"))
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Reveal Value"),
                isEnabled: model.canEdit && !model.editableItems(ids: model.selection).isEmpty,
                help: VPhoneLocalization.text("Ask the guest for the selected items' values"),
            ) {
                Task { await model.reveal(ids: model.selection) }
            })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Actions"),
                glyph: .ellipsis,
                size: .icon,
                action: showActionsMenu,
            ))
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Refresh"),
                glyph: .refresh,
                size: .icon,
                isEnabled: !model.isLoading,
                help: VPhoneLocalization.text("Refresh (⌘R)"),
            ) {
                Task { await model.refresh() }
            })
            .keyboardShortcut("r", modifiers: .command)
            VPhoneKeychainSearchField(placeholder: VPhoneLocalization.text("Search Keychain"), text: $model.searchText)
        }
    }

    private var actionsMenu: [DKMenuItem] {
        [
            DKMenuItem(VPhoneLocalization.text("Refresh"), glyph: .refresh) { [model] in
                Task { await model.refresh() }
            },
            DKMenuItem(
                VPhoneLocalization.text("Copy Selected Rows"),
                glyph: .copy,
                isEnabled: !model.selection.isEmpty,
            ) { [model] in
                model.copyRows(ids: model.selection)
            },
            DKMenuItem(
                VPhoneLocalization.text(model.showDiagnostics ? "Hide Diagnostics" : "Show Diagnostics"),
                glyph: .list,
            ) { [model] in
                model.showDiagnostics.toggle()
            },
            .separator,
            DKMenuItem(VPhoneLocalization.text("Add Test Item"), glyph: .plus) { [model] in
                Task { await model.addTestItem() }
            },
            DKMenuItem(VPhoneLocalization.text("Remove Test Item"), glyph: .minus) { [model] in
                Task { await model.removeTestItem() }
            },
        ]
    }

    /// Opens the actions menu under the pointer, where the Actions button was clicked.
    private func showActionsMenu() {
        let menu = actionsMenu.makeNSMenu(title: VPhoneLocalization.text("Keychain Actions"))
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Table

    private var tableView: some View {
        Table(of: VPhoneKeychainItem.self, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Class", value: \.itemClass) { item in
                DKTableCellView(.title(item.displayClass, leading: .glyph(item.classGlyph), strong: false))
                    .help(item.displayClass)
            }
            .width(min: 120, ideal: 150, max: 200)

            TableColumn("Account", value: \.account) { item in
                attributeCell(item.account, protected: item.protectedMetadata)
            }
            .width(min: 80, ideal: 150, max: .infinity)

            TableColumn("Service", value: \.service) { item in
                attributeCell(item.service.isEmpty ? item.server : item.service, protected: item.protectedMetadata)
            }
            .width(min: 80, ideal: 150, max: .infinity)

            TableColumn("Access Group", value: \.accessGroup) { item in
                attributeCell(item.accessGroup, protected: false)
            }
            .width(min: 80, ideal: 160, max: .infinity)

            TableColumn("Protection", value: \.protection) { item in
                DKTableCellView(.muted(item.protection.isEmpty ? "—" : item.protectionDescription))
                    .help(item.protection)
            }
            .width(min: 90, ideal: 130, max: 200)

            TableColumn("Value", value: \.value) { item in
                DKTableCellView(item.value.isEmpty ? .muted(item.displayValue) : .mono(item.displayValue))
                    .help(item.displayValue)
            }
            .width(min: 80, ideal: 130, max: .infinity)
        } rows: {
            ForEach(model.filteredItems) { item in
                TableRow(item)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(DK.Palette.window)
        .contextMenu(forSelectionType: VPhoneKeychainItem.ID.self) { ids in
            contextMenu(for: ids)
        }
        .overlay {
            if model.filteredItems.isEmpty, !model.isLoading {
                Text(emptyText)
                    .font(DK.Typeface.body)
                    .foregroundStyle(DK.Palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(DK.Space.s6)
                    .allowsHitTesting(false)
            }
        }
    }

    private var emptyText: String {
        if !model.items.isEmpty {
            return VPhoneLocalization.text("No items match the filter.")
        }
        if !model.diagnostics.isEmpty {
            return VPhoneLocalization.text("The guest returned no keychain items. Choose Show Diagnostics in the actions menu to see why.")
        }
        return VPhoneLocalization.text("No keychain items.")
    }

    private func attributeCell(_ value: String, protected: Bool) -> some View {
        Group {
            if value.isEmpty {
                DKTableCellView(.muted(protected ? VPhoneLocalization.text("Protected") : "—"))
            } else {
                DKTableCellView(.mono(value))
            }
        }
        .help(value)
    }

    // MARK: - Detail Bar

    private var detailBar: some View {
        let selected = model.filteredItems.filter { model.selection.contains($0.id) }
        let editable = model.editableItems(ids: model.selection)
        let actions = [
            DKButtonSpec(VPhoneLocalization.text("Copy Row (TSV)"), glyph: .copy, isEnabled: !selected.isEmpty) {
                model.copyRows(ids: model.selection)
            },
            DKButtonSpec(VPhoneLocalization.text("Edit Value…"), isEnabled: model.canEdit && editable.count == 1) {
                Task { await model.beginEditing(ids: model.selection) }
            },
            DKButtonSpec(
                VPhoneLocalization.text("Delete…"),
                glyph: .trash,
                variant: .danger,
                isEnabled: model.canEdit && !editable.isEmpty,
            ) {
                model.pendingDeletion = model.selection
            },
        ]
        return Group {
            if selected.count == 1, let item = selected.first {
                DKDetailBar(
                    item.displayClass,
                    subtitle: item.displayName,
                    note: note(for: item),
                    actions: actions,
                    layout: .row,
                )
            } else if selected.isEmpty {
                DKDetailBar(
                    note: VPhoneLocalization.text("Select an item to copy, reveal, edit or delete it."),
                    actions: actions,
                    layout: .row,
                )
            } else {
                DKDetailBar(
                    VPhoneLocalization.format("%@ items selected", String(selected.count)),
                    note: editable.count == selected.count
                        ? nil
                        : VPhoneLocalization.format(
                            "The guest can act on %@ of them; the others came from the keychain database.",
                            String(editable.count),
                        ),
                    actions: actions,
                    layout: .row,
                )
            }
        }
    }

    private func note(for item: VPhoneKeychainItem) -> String {
        guard item.isAccessible else {
            return VPhoneLocalization.text("This row came from the keychain database. The guest cannot read, edit or delete it.")
        }
        guard model.canEdit else {
            return VPhoneLocalization.text("Update the guest agent to reveal, edit or delete keychain items.")
        }
        let modified = item.displayDate == "-" ? "" : " " + VPhoneLocalization.format("Modified %@.", item.displayDate)
        if item.value.isEmpty {
            return VPhoneLocalization.text("Value is protected. Reveal asks the guest for it; Edit stores the text as its UTF-8 bytes.") + modified
        }
        return VPhoneLocalization.text("Edit stores the text as its UTF-8 bytes.") + modified
    }

    // MARK: - Edit Sheet

    @ViewBuilder
    var editSheet: some View {
        if let editing = model.editing {
            VStack(alignment: .leading, spacing: DK.Space.s3) {
                Text("Edit Value")
                    .font(DK.Typeface.sheetTitle)
                    .foregroundStyle(DK.Palette.ink)

                Text(editing.item.displayName)
                    .font(DK.Typeface.mono)
                    .foregroundStyle(DK.Palette.muted)
                    .lineLimit(2)

                VPhoneGuestTextEditor(
                    text: .init(
                        get: { model.editing?.value ?? "" },
                        set: { model.editing?.value = $0 },
                    ),
                    accessibilityLabel: VPhoneLocalization.text("Value"),
                )
                .frame(width: 380, height: 120)

                Text("The value is stored as its UTF-8 bytes.")
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)

                HStack(spacing: DK.Space.s2) {
                    Spacer()
                    DKButton(VPhoneLocalization.text("Cancel")) { model.editing = nil }
                        .keyboardShortcut(.cancelAction)
                    DKButton(VPhoneLocalization.text("Save"), variant: .primary) {
                        Task { await model.commitEditing() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(DK.Space.s5)
            .background(DK.Palette.sidebar)
        }
    }

    // MARK: - Diagnostics Panel

    var diagnosticsPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: DK.Space.s2) {
                Text("Diagnostics")
                    .font(DK.Typeface.sectionTitle)
                    .foregroundStyle(DK.Palette.muted)
                Spacer()
                Text(VPhoneLocalization.format("%@ entries", String(model.diagnostics.count)))
                    .font(DK.Typeface.monoSmall)
                    .foregroundStyle(DK.Palette.muted)
                DKButton(DKButtonSpec(
                    VPhoneLocalization.text("Copy diagnostics to clipboard"),
                    glyph: .copy,
                    variant: .ghost,
                    size: .icon,
                    isEnabled: !model.diagnostics.isEmpty,
                ) {
                    let text = model.diagnostics.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                })
                DKButton(DKButtonSpec(
                    VPhoneLocalization.text("Hide Diagnostics"),
                    glyph: .close,
                    variant: .ghost,
                    size: .icon,
                ) {
                    model.showDiagnostics = false
                })
            }
            .padding(.horizontal, DK.Space.s4)
            .padding(.vertical, DK.Space.s1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(DK.Typeface.log)
                                .foregroundStyle(DK.Palette.inkSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DK.Space.s4)
                                .padding(.vertical, 1)
                                .id(index)
                        }
                    }
                    .padding(.vertical, DK.Space.s1)
                }
                .onChange(of: model.diagnostics.count) { _, newCount in
                    if newCount > 0 {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
            .frame(height: 140)
            .background(DK.Palette.surfaceSunken)
        }
        .background(DK.Palette.surfaceRaised)
        .overlay(alignment: .top) {
            DK.Palette.divider.frame(height: DK.Metric.hairline)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    func contextMenu(for ids: Set<VPhoneKeychainItem.ID>) -> some View {
        let editable = model.editableItems(ids: ids)
        if model.canEdit, !editable.isEmpty {
            Button("Reveal Value") { Task { await model.reveal(ids: ids) } }
            Button("Edit Value…") { Task { await model.beginEditing(ids: ids) } }
                .disabled(editable.count != 1)
            Button("Delete…", role: .destructive) { model.pendingDeletion = ids }
            Divider()
        }
        Button("Copy Account") { copyField(ids: ids, keyPath: \.account) }
        Button("Copy Service") { copyField(ids: ids, keyPath: \.service) }
        Button("Copy Value") { copyField(ids: ids, keyPath: \.value) }
        Button("Copy Access Group") { copyField(ids: ids, keyPath: \.accessGroup) }
        Button("Copy Protection") { copyField(ids: ids, keyPath: \.protection) }
        Divider()
        Button("Copy Row (TSV)") { model.copyRows(ids: ids) }
        Divider()
        Button("Refresh") { Task { await model.refresh() } }
    }

    // MARK: - Copy Actions

    func copyField(ids: Set<VPhoneKeychainItem.ID>, keyPath: KeyPath<VPhoneKeychainItem, String>) {
        let values = model.filteredItems
            .filter { ids.contains($0.id) }
            .map { $0[keyPath: keyPath] }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !values.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(values, forType: .string)
    }
}

// MARK: - Class Glyph

extension VPhoneKeychainItem {
    /// The design glyph for the item class.
    var classGlyph: DKGlyph {
        switch itemClass {
        case "genp", "idnt": .key
        case "inet": .globe
        case "cert": .seal
        case "keys": .lock
        default: .doc
        }
    }
}
