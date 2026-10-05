import SwiftUI

// MARK: - Level filter

/// Which lines the Guest Console shows, by severity: all of them, errors and
/// faults, or faults alone. Lines carry severity as their tone (see
/// `DKLogLine.Tone.init(logLevel:)`): an error is `.warning`, a fault `.error`.
public enum DKLogLevelFilter: String, Sendable, CaseIterable, Hashable, Identifiable {
    case all
    case errors
    case faults

    public var id: Self {
        self
    }

    /// The segment title.
    public var title: String {
        switch self {
        case .all: "All"
        case .errors: "Errors"
        case .faults: "Faults"
        }
    }

    /// Whether a line of this tone passes the filter.
    public func admits(_ tone: DKLogLine.Tone) -> Bool {
        switch self {
        case .all: true
        case .errors: tone == .warning || tone == .error
        case .faults: tone == .error
        }
    }
}

// MARK: - Toolbar

/// The console's filter row: clear, level, auto-scroll, and search. The caller
/// owns the state; pair `following` with `DKLog(_:following:)` so the toggle
/// and the log's own scrolling stay in step, and filter lines with
/// `DKLogLevelFilter.admits(_:)` and `DKLogLine.matches(_:)`.
public struct DKLogToolbar: View {
    @Binding var searchText: String
    @Binding var level: DKLogLevelFilter
    @Binding var following: Bool
    let searchPrompt: String
    let isSearchFocused: Binding<Bool>?
    let onClear: () -> Void

    /// - Parameter isSearchFocused: The search field's keyboard focus, for a
    ///   Find command that focuses it.
    public init(
        searchText: Binding<String>,
        level: Binding<DKLogLevelFilter>,
        following: Binding<Bool>,
        searchPrompt: String = "Search",
        isSearchFocused: Binding<Bool>? = nil,
        onClear: @escaping () -> Void,
    ) {
        _searchText = searchText
        _level = level
        _following = following
        self.searchPrompt = searchPrompt
        self.isSearchFocused = isSearchFocused
        self.onClear = onClear
    }

    public var body: some View {
        HStack(spacing: DK.Space.s2) {
            DKButton("Clear", glyph: .trash, size: .icon, action: onClear)

            Picker("Level", selection: $level) {
                ForEach(DKLogLevelFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Toggle("Auto-Scroll", isOn: $following)
                .toggleStyle(DKLogIconToggleStyle(glyph: .download, title: "Auto-Scroll"))

            Spacer(minLength: DK.Space.s2)

            if let isSearchFocused {
                DKSearchField(searchPrompt, text: $searchText, isFocused: isSearchFocused, width: 180)
            } else {
                DKSearchField(searchPrompt, text: $searchText, width: 180)
            }
        }
        .padding(.horizontal, DK.Space.s3)
        .padding(.vertical, DK.Space.s2)
    }
}

/// A square icon toggle: pressed while on, plain while off. The label becomes
/// the accessibility label and tooltip.
struct DKLogIconToggleStyle: ToggleStyle {
    let glyph: DKGlyph
    let title: String

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            DKIcon(glyph, size: 15)
        }
        .buttonStyle(DKButtonStyle(variant: configuration.isOn ? .pressed : .secondary, size: .icon))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

// MARK: - Previews

private struct DKLogToolbarPreview: View {
    @State private var search = ""
    @State private var level = DKLogLevelFilter.all
    @State private var following = true

    var body: some View {
        DKLogToolbar(searchText: $search, level: $level, following: $following) {}
            .frame(width: 640)
            .background(DK.Palette.window)
    }
}

#Preview("Toolbar, light") {
    DKLogToolbarPreview()
        .preferredColorScheme(.light)
}

#Preview("Toolbar, dark") {
    DKLogToolbarPreview()
        .preferredColorScheme(.dark)
}
