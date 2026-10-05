import VPhoneDesignKit

// MARK: - Section

/// One titled group of key-value rows in the Device Info readout.
struct VPhoneDeviceInfoSection: Identifiable {
    enum Kind: String {
        case device
        case power
        case security
        case agent
        case hardware
        case display
        case environment

        /// The page's two columns: what the device is and runs on the left,
        /// what it is built from on the right.
        var column: Column {
            switch self {
            case .device, .power, .security, .agent: .leading
            case .hardware, .display, .environment: .trailing
            }
        }
    }

    enum Column {
        case leading
        case trailing
    }

    let kind: Kind
    let title: String
    let rows: [VPhoneDeviceInfoRow]

    var id: Kind {
        kind
    }
}

// MARK: - Row

struct VPhoneDeviceInfoRow: Identifiable {
    let label: String
    let value: String
    /// A status dot before the value, for rows that report a state.
    var tone: DKTone?
    /// A 0...1 fill drawn as a thin capacity bar before the value.
    var gauge: Double?
    /// Identifiers, versions, hashes and sizes in monospace. Monospaced values
    /// truncate in the middle.
    var monospaced = false

    var id: String {
        label
    }

    var keyValue: DKKeyValue {
        DKKeyValue(label, value, monospaced: monospaced, tone: tone)
    }
}
