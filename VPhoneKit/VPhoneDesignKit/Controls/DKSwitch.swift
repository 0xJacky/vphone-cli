import SwiftUI

// MARK: - Toggle style

/// The DesignKit switch: a 36×22 track, accent when on, with a white knob. Apply
/// it to any `Toggle`; the toggle keeps its native semantics, so VoiceOver still
/// reads and flips it as a switch. The label, when visible, leads the switch.
public struct DKSwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        DKSwitchBody(configuration: configuration)
    }

    static let trackSize = CGSize(width: 36, height: 22)
    static let knobDiameter: CGFloat = 18

    /// The knob's horizontal offset from the track's center.
    static func knobOffset(isOn: Bool) -> CGFloat {
        let travel = (trackSize.width - trackSize.height) / 2
        return isOn ? travel : -travel
    }
}

private struct DKSwitchBody: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.labelsVisibility) private var labelsVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DK.Space.s2) {
            if labelsVisibility != .hidden {
                configuration.label
                    .foregroundStyle(isEnabled ? DK.Palette.ink : DK.Palette.inkDisabled)
            }
            Button(action: toggle) {
                track
            }
            .buttonStyle(.plain)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) {
                    configuration.label
                }
            }
        }
    }

    private var track: some View {
        Capsule(style: .circular)
            .fill(configuration.isOn ? DK.Palette.accent : DK.Palette.lineStrong)
            .frame(width: DKSwitchToggleStyle.trackSize.width, height: DKSwitchToggleStyle.trackSize.height)
            .overlay {
                Circle()
                    .fill(DK.Palette.onAccent)
                    .frame(width: DKSwitchToggleStyle.knobDiameter, height: DKSwitchToggleStyle.knobDiameter)
                    .offset(x: DKSwitchToggleStyle.knobOffset(isOn: configuration.isOn))
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule(style: .circular))
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            configuration.isOn.toggle()
        }
    }
}

// MARK: - Switch

/// A DesignKit switch with a text label. In form rows the label usually sits in
/// the row's own label column, so by default the switch shows only the track and
/// keeps `label` for VoiceOver; pass `showsLabel: true` to draw it beside the switch.
public struct DKSwitch: View {
    let label: String
    @Binding var isOn: Bool
    let showsLabel: Bool

    public init(_ label: String, isOn: Binding<Bool>, showsLabel: Bool = false) {
        self.label = label
        _isOn = isOn
        self.showsLabel = showsLabel
    }

    public var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(DKSwitchToggleStyle())
            .labelsHidden(!showsLabel)
    }
}

private extension View {
    @ViewBuilder
    func labelsHidden(_ hidden: Bool) -> some View {
        if hidden {
            labelsHidden()
        } else {
            self
        }
    }
}

// MARK: - Previews

private struct DKSwitchPreview: View {
    @State private var menuBar = true
    @State private var updates = false

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s3) {
            HStack(spacing: DK.Space.s4) {
                DKSwitch("Keep in Menu Bar", isOn: $menuBar)
                DKSwitch("Check for Updates", isOn: $updates)
                DKSwitch("Disabled", isOn: .constant(true)).disabled(true)
                DKSwitch("Disabled", isOn: .constant(false)).disabled(true)
            }
            DKSwitch("Keep in Menu Bar", isOn: $menuBar, showsLabel: true)
            Toggle("Native Toggle with the style", isOn: $updates)
                .toggleStyle(DKSwitchToggleStyle())
        }
        .padding(DK.Space.s4)
        .background(DK.Palette.window)
    }
}

#Preview("Switch, light") {
    DKSwitchPreview().preferredColorScheme(.light)
}

#Preview("Switch, dark") {
    DKSwitchPreview().preferredColorScheme(.dark)
}
