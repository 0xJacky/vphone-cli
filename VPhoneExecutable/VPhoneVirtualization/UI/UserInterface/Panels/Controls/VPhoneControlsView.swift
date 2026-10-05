import SwiftUI
import VPhoneDesignKit

struct VPhoneControlsView: View {
    @Bindable var model: VPhoneControlsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            VPhoneGuestToolContent {
                VPhoneGuestToolColumns {
                    displaySection
                    audioSection
                    buttonsSection
                } trailing: {
                    keyboardSection
                    notificationSection
                }
            }
            .disabled(!model.isConnected)
            DKStatusBar(isConnected: model.isConnected, activity: model.activity?.title, status: model.status)
        }
        .guestToolShortcuts([
            VPhoneGuestToolShortcut(key: "r", isEnabled: !model.isBusy) {
                Task { await model.refresh() }
            },
            VPhoneGuestToolShortcut(key: .return, isEnabled: model.canSendText) {
                Task { await model.typeText() }
            },
        ])
        .task { await model.run() }
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(
            String(localized: "Controls", bundle: VPhoneLocalization.bundle),
            subtitle: model.readAt.map {
                String(localized: "Values read from the guest at \($0.formatted(date: .omitted, time: .standard))", bundle: VPhoneLocalization.bundle)
            },
            actions: [
                DKButtonSpec(
                    String(localized: "Refresh", bundle: VPhoneLocalization.bundle),
                    glyph: .refresh,
                    isEnabled: !model.isBusy,
                    help: String(localized: "Read the guest's current values again (⌘R)", bundle: VPhoneLocalization.bundle),
                ) { Task { await model.refresh() } },
            ],
        )
    }

    // MARK: - Display and Power

    private var displaySection: some View {
        DKSection(String(localized: "Display and Power", bundle: VPhoneLocalization.bundle)) {
            DKFormRow(String(localized: "Orientation", bundle: VPhoneLocalization.bundle)) {
                if let orientation = model.orientation {
                    DKSegmented(
                        String(localized: "Orientation", bundle: VPhoneLocalization.bundle),
                        selection: orientationBinding(orientation),
                        options: VPhoneControlsOrientation.allCases.map { DKSegmentOption($0.shortTitle, value: $0) },
                    )
                    .disabled(!model.canWrite)
                    .help(String(localized: "Rotate the guest interface", bundle: VPhoneLocalization.bundle))
                } else {
                    unavailable
                }
            }
            DKFormRow(String(localized: "Rotation Lock", bundle: VPhoneLocalization.bundle)) {
                switchControl(
                    String(localized: "Rotation Lock", bundle: VPhoneLocalization.bundle),
                    value: model.rotationLocked,
                    help: String(localized: "Keep the guest interface from rotating with the device", bundle: VPhoneLocalization.bundle),
                ) { await model.setRotationLocked($0) }
            }
            DKFormRow(String(localized: "Low Power Mode", bundle: VPhoneLocalization.bundle)) {
                switchControl(
                    String(localized: "Low Power Mode", bundle: VPhoneLocalization.bundle),
                    value: model.lowPowerMode,
                    help: String(localized: "Turn Low Power Mode on or off", bundle: VPhoneLocalization.bundle),
                ) { await model.setLowPowerMode($0) }
            }
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        DKSection(String(localized: "Audio", bundle: VPhoneLocalization.bundle)) {
            DKFormRow(String(localized: "Category", bundle: VPhoneLocalization.bundle)) {
                DKSegmented(
                    String(localized: "Category", bundle: VPhoneLocalization.bundle),
                    selection: categoryBinding,
                    options: VPhoneControlsVolumeCategory.allCases.map { DKSegmentOption($0.title, value: $0) },
                )
                .disabled(!model.canWrite)
                .help(String(localized: "Choose which volume the slider below reads and sets", bundle: VPhoneLocalization.bundle))
            }
            DKFormRow(String(localized: "Volume", bundle: VPhoneLocalization.bundle)) {
                Slider(value: $model.volume, in: 0 ... 1) { editing in
                    if !editing {
                        Task { await model.commitVolume() }
                    }
                }
                .labelsHidden()
                .tint(DK.Palette.accent)
                .frame(width: 160)
                .accessibilityLabel(String(localized: "Volume", bundle: VPhoneLocalization.bundle))
                .disabled(!model.canWrite || model.guestVolume == nil)
                Text(model.guestVolume == nil ? "—" : VPhonePanelFormat.percent(model.volume))
                    .font(DK.Typeface.mono)
                    .monospacedDigit()
                    .foregroundStyle(DK.Palette.ink)
                    .frame(width: 36, alignment: .trailing)
            }
            DKFormRow(String(localized: "Active Session", bundle: VPhoneLocalization.bundle)) {
                Text(activeSession)
                    .font(DK.Typeface.body)
                    .foregroundStyle(DK.Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(activeSession)
            }
        }
    }

    private var activeSession: String {
        model.activeSessionText
    }

    // MARK: - Hardware Buttons

    private var buttonsSection: some View {
        DKSection(String(localized: "Hardware Buttons", bundle: VPhoneLocalization.bundle)) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: DK.Space.s2), count: 3), spacing: DK.Space.s2) {
                ForEach(VPhoneControlsButton.allCases) { button in
                    DKButton(DKButtonSpec(
                        button.title,
                        glyph: button.glyph,
                        size: .tile,
                        isEnabled: model.canWrite,
                        help: button.help,
                    ) { Task { await model.press(button) } })
                }
            }
            .padding(DK.Space.s3)
        }
    }

    // MARK: - Keyboard

    private var keyboardSection: some View {
        DKSection(String(localized: "Keyboard", bundle: VPhoneLocalization.bundle), card: false) {
            DKCard(.padded) {
                VPhoneControlsTextArea(
                    text: $model.keyboardText,
                    prompt: String(localized: "Text to send to the guest", bundle: VPhoneLocalization.bundle),
                )

                HStack(spacing: DK.Space.s2) {
                    Text(model.keyboardText.count == 1
                        ? String(localized: "1 character", bundle: VPhoneLocalization.bundle)
                        : String(localized: "\(model.keyboardText.count) characters", bundle: VPhoneLocalization.bundle))
                        .font(DK.Typeface.caption)
                        .monospacedDigit()
                        .foregroundStyle(DK.Palette.muted)
                    Spacer(minLength: DK.Space.s2)
                    DKButton(DKButtonSpec(
                        String(localized: "Paste", bundle: VPhoneLocalization.bundle),
                        isEnabled: model.canSendText,
                        help: String(localized: "Insert the whole text at once", bundle: VPhoneLocalization.bundle),
                    ) { Task { await model.pasteText() } })
                    DKButton(DKButtonSpec(
                        String(localized: "Type", bundle: VPhoneLocalization.bundle),
                        variant: .primary,
                        isEnabled: model.canSendText,
                        help: String(localized: "Type the text one character at a time (⌘↩)", bundle: VPhoneLocalization.bundle),
                    ) { Task { await model.typeText() } })
                }

                VStack(alignment: .leading, spacing: 6) {
                    keyRow(VPhoneControlsKey.allCases.filter { !$0.isArrow }.map { .key($0) })
                    keyRow(VPhoneControlsKey.allCases.filter(\.isArrow).map { .key($0) }
                        + VPhoneControlsModifier.allCases.map { .modifier($0) })
                }
                .padding(.top, DK.Space.s3)
                .overlay(alignment: .top) {
                    Rectangle().fill(DK.Palette.dividerSoft).frame(height: DK.Metric.hairline)
                }

                Text("Modifiers stay held while a special key is sent.", bundle: VPhoneLocalization.bundle)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
            }
        }
    }

    private enum KeyCell: Identifiable {
        case key(VPhoneControlsKey)
        case modifier(VPhoneControlsModifier)

        var id: String {
            switch self {
            case let .key(key): "key-\(key.rawValue)"
            case let .modifier(modifier): "modifier-\(modifier.rawValue)"
            }
        }
    }

    /// One row of equal-width small keys.
    private func keyRow(_ cells: [KeyCell]) -> some View {
        HStack(spacing: 6) {
            ForEach(cells) { cell in
                switch cell {
                case let .key(key): keyButton(key)
                case let .modifier(modifier): modifierButton(modifier)
                }
            }
        }
    }

    private func keyButton(_ key: VPhoneControlsKey) -> some View {
        Button {
            Task { await model.send(key) }
        } label: {
            Text(key.isArrow ? key.arrowSymbol : key.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DKButtonStyle(size: .small))
        .disabled(!model.canWrite)
        .help(String(localized: "Send \(model.keyName(key)) to the guest", bundle: VPhoneLocalization.bundle))
        .accessibilityLabel(key.title)
    }

    private func modifierButton(_ modifier: VPhoneControlsModifier) -> some View {
        let isOn = model.modifiers.contains(modifier)
        return Button {
            if isOn {
                model.modifiers.remove(modifier)
            } else {
                model.modifiers.insert(modifier)
            }
        } label: {
            Text(modifier.symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DKButtonStyle(variant: isOn ? .ghostOn : .secondary, size: .small))
        .help(modifier.help)
        .accessibilityLabel(modifier.help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Darwin Notification

    private var notificationSection: some View {
        DKSection(String(localized: "Darwin Notification", bundle: VPhoneLocalization.bundle), card: false) {
            DKCard(.padded) {
                HStack(spacing: DK.Space.s2) {
                    fieldLabel(String(localized: "Name", bundle: VPhoneLocalization.bundle))
                    TextField(
                        String(localized: "Name", bundle: VPhoneLocalization.bundle),
                        text: $model.notificationName,
                        prompt: Text(verbatim: "com.apple.springboard.lockcomplete").foregroundStyle(DK.Palette.muted),
                    )
                    .textFieldStyle(.dkFieldMono)
                    .labelsHidden()
                    presetsMenu
                }

                HStack(spacing: DK.Space.s2) {
                    fieldLabel(String(localized: "State", bundle: VPhoneLocalization.bundle))
                    TextField(
                        String(localized: "State", bundle: VPhoneLocalization.bundle),
                        text: $model.notificationState,
                        prompt: Text("None", bundle: VPhoneLocalization.bundle).foregroundStyle(DK.Palette.muted),
                    )
                    .textFieldStyle(.dkFieldMono)
                    .labelsHidden()
                }

                Text("A UInt64 the guest stores before posting. Leave empty to post without a state.", bundle: VPhoneLocalization.bundle)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DK.Space.s2) {
                    Spacer(minLength: DK.Space.s2)
                    DKButton(DKButtonSpec(
                        String(localized: "Read State", bundle: VPhoneLocalization.bundle),
                        isEnabled: model.canUseNotification,
                        help: String(localized: "Read the notification's current state from the guest", bundle: VPhoneLocalization.bundle),
                    ) { Task { await model.readNotificationState() } })
                    DKButton(DKButtonSpec(
                        String(localized: "Post", bundle: VPhoneLocalization.bundle),
                        variant: .primary,
                        isEnabled: model.canUseNotification,
                        help: String(localized: "Post the notification in the guest", bundle: VPhoneLocalization.bundle),
                    ) { Task { await model.postNotification() } })
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(DK.Typeface.body)
            .foregroundStyle(DK.Palette.inkSecondary)
            .frame(width: 48, alignment: .leading)
    }

    private var presetsMenu: some View {
        let shape = RoundedRectangle(cornerRadius: DK.Radius.field, style: .continuous)
        return Menu(String(localized: "Presets", bundle: VPhoneLocalization.bundle)) {
            ForEach(VPhoneControlsNotification.presets, id: \.self) { group in
                Section {
                    ForEach(group, id: \.self) { name in
                        Button(name) { model.notificationName = name }
                    }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .tint(DK.Palette.ink)
        .fixedSize()
        .padding(.horizontal, DK.Space.s2)
        .frame(height: 28)
        .background(shape.fill(DK.Palette.window))
        .overlay(shape.strokeBorder(DK.Palette.lineStrong, lineWidth: DK.Metric.hairline))
        .help(String(localized: "Choose a notification name the system posts or observes", bundle: VPhoneLocalization.bundle))
    }

    // MARK: - Controls

    private var unavailable: some View {
        Text("Unavailable", bundle: VPhoneLocalization.bundle)
            .font(DK.Typeface.body)
            .foregroundStyle(DK.Palette.muted)
    }

    /// A switch for a guest value; a value the guest did not report reads Unavailable.
    @ViewBuilder
    private func switchControl(
        _ label: String,
        value: Bool?,
        help: String,
        set: @escaping @MainActor (Bool) async -> Void,
    ) -> some View {
        if let value {
            DKSwitch(label, isOn: Binding {
                value
            } set: { newValue in
                Task { await set(newValue) }
            })
            .disabled(!model.canWrite)
            .help(help)
        } else {
            unavailable
        }
    }

    // MARK: - Bindings

    private func orientationBinding(_ current: VPhoneControlsOrientation) -> Binding<VPhoneControlsOrientation> {
        Binding {
            current
        } set: { orientation in
            Task { await model.setOrientation(orientation) }
        }
    }

    private var categoryBinding: Binding<VPhoneControlsVolumeCategory> {
        Binding {
            model.volumeCategory
        } set: { category in
            Task { await model.selectVolumeCategory(category) }
        }
    }
}

// MARK: - Text Area

/// A multi-line monospaced text field (`.dk-textarea`) with a placeholder.
private struct VPhoneControlsTextArea: View {
    @Binding var text: String
    let prompt: String

    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
        TextEditor(text: $text)
            .font(DK.Typeface.mono)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .focusEffectDisabled()
            .padding(.horizontal, 5)
            .padding(.vertical, DK.Space.s2)
            .frame(height: 72)
            .background(shape.fill(DK.Palette.window))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(prompt)
                        .font(DK.Typeface.mono)
                        .foregroundStyle(DK.Palette.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, DK.Space.s2)
                        .allowsHitTesting(false)
                }
            }
            .overlay(shape.strokeBorder(isFocused ? DK.Palette.accent : DK.Palette.lineStrong, lineWidth: DK.Metric.hairline))
            .accessibilityLabel(prompt)
    }
}
