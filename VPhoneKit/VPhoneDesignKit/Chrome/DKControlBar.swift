import SwiftUI

/// The bar under the guest display: three groups of buttons, with the center
/// group centered on the bar whatever the side groups hold. The display window
/// puts rotate and screenshot on the leading side, Home (a `largeIcon`) in the
/// center and the recording timer on the trailing side.
///
/// `accessory` follows the trailing buttons, for a control that is not a button.
public struct DKControlBar<Accessory: View>: View {
    public var leading: [DKButtonSpec]
    public var center: [DKButtonSpec]
    public var trailing: [DKButtonSpec]
    let accessory: Accessory

    public init(
        leading: [DKButtonSpec] = [],
        center: [DKButtonSpec] = [],
        trailing: [DKButtonSpec] = [],
        @ViewBuilder accessory: () -> Accessory,
    ) {
        self.leading = leading
        self.center = center
        self.trailing = trailing
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: DK.Space.s3) {
            group(leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            group(center)
                .fixedSize()
            HStack(spacing: DK.Space.s2) {
                group(trailing)
                accessory
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, DK.Space.s4)
        .padding(.vertical, DK.Space.s3)
        .background(DK.Palette.window)
        .overlay(alignment: .top) {
            DK.Palette.divider.frame(height: DK.Metric.hairline)
        }
    }

    private func group(_ specs: [DKButtonSpec]) -> some View {
        HStack(spacing: DK.Space.s2) {
            ForEach(specs) { spec in
                DKButton(spec)
            }
        }
    }
}

public extension DKControlBar where Accessory == EmptyView {
    init(
        leading: [DKButtonSpec] = [],
        center: [DKButtonSpec] = [],
        trailing: [DKButtonSpec] = [],
    ) {
        self.init(leading: leading, center: center, trailing: trailing, accessory: { EmptyView() })
    }
}
