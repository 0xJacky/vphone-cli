import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// The logic behind the segmented control, switch, search field, progress bar and form fields.
@Suite("DesignKit controls")
@MainActor
struct DKControlsTests {
    // MARK: - Segmented

    private let filters = [
        DKSegmentOption("All", value: "all", count: 4),
        DKSegmentOption("Running", value: "running", count: 1),
        DKSegmentOption("Stopped", value: "stopped"),
    ]

    @Test
    func `a segment is identified by its value`() {
        #expect(filters.map(\.id) == ["all", "running", "stopped"])
    }

    @Test
    func `a segment with a count reads the count after its label`() {
        #expect(filters[0].accessibilityLabel == "All, 4")
        #expect(filters[2].accessibilityLabel == "Stopped")
    }

    @Test
    func `an icon-only segment keeps its label for VoiceOver and the tooltip`() {
        let option = DKSegmentOption.icon(.list, label: "List", value: 0)
        #expect(option.isIconOnly)
        #expect(option.glyph == .list)
        #expect(option.label == "List")
        #expect(option.accessibilityLabel == "List")
        #expect(!DKSegmentOption("List", value: 0, glyph: .list).isIconOnly)
    }

    @Test
    func `arrow keys move the selection one segment and stop at the ends`() {
        #expect(DKSegmentedSelection.value(after: "all", step: 1, in: filters) == "running")
        #expect(DKSegmentedSelection.value(after: "running", step: -1, in: filters) == "all")
        #expect(DKSegmentedSelection.value(after: "all", step: -1, in: filters) == "all")
        #expect(DKSegmentedSelection.value(after: "stopped", step: 1, in: filters) == "stopped")
    }

    @Test
    func `an unknown selection moves to the first segment and no segments means no move`() {
        #expect(DKSegmentedSelection.value(after: "paused", step: 1, in: filters) == "all")
        #expect(DKSegmentedSelection.value(after: "all", step: 1, in: [DKSegmentOption<String>]()) == nil)
    }

    @Test
    func `fill mode splits the width into equal shares`() {
        #expect(DKEqualWidthLayout.segmentWidth(total: 300, count: 3) == 100)
        #expect(DKEqualWidthLayout.offsets(total: 300, count: 3) == [0, 100, 200])
        #expect(DKEqualWidthLayout.segmentWidth(total: 100, count: 0) == 0)
        #expect(DKEqualWidthLayout.offsets(total: 100, count: 0).isEmpty)
        #expect(DKEqualWidthLayout.segmentWidth(total: -20, count: 2) == 0)
        #expect(DKEqualWidthLayout.segmentWidth(total: .infinity, count: 2) == 0)
    }

    @Test
    func `the segmented track is as tall as a regular control`() {
        let height = DK.Metric.controlHeightSmall + 2 * DKSegmented<Int>.trackInset
        #expect(height == DK.Metric.controlHeight)
    }

    // MARK: - Switch

    @Test
    func `the switch knob rests against the leading end when off and the trailing end when on`() {
        let size = DKSwitchToggleStyle.trackSize
        #expect(size == CGSize(width: 36, height: 22))
        let inset = (size.height - DKSwitchToggleStyle.knobDiameter) / 2
        #expect(inset == 2)
        let center = size.width / 2
        let offLeading = center + DKSwitchToggleStyle.knobOffset(isOn: false) - DKSwitchToggleStyle.knobDiameter / 2
        let onTrailing = center + DKSwitchToggleStyle.knobOffset(isOn: true) + DKSwitchToggleStyle.knobDiameter / 2
        #expect(offLeading == inset)
        #expect(onTrailing == size.width - inset)
    }

    // MARK: - Search field

    @Test
    func `the search field offers a clear button only when there is text`() {
        #expect(!DKSearchField.showsClearButton(for: ""))
        #expect(DKSearchField.showsClearButton(for: "r"))
    }

    // MARK: - Progress

    @Test
    func `progress clamps to zero through one and treats NaN as no progress`() {
        #expect(DKProgress.clamped(-0.5) == 0)
        #expect(DKProgress.clamped(0.42) == 0.42)
        #expect(DKProgress.clamped(7) == 1)
        #expect(DKProgress.clamped(.nan) == 0)
        #expect(DKProgress.clamped(.infinity) == 1)
        #expect(DKProgress(value: 1.5).value == 1)
    }

    @Test
    func `an indeterminate bar has no value`() {
        let bar = DKProgress.indeterminate(tone: .warning, thin: true, label: "Preparing")
        #expect(bar.value == nil)
        #expect(bar.tone == .warning)
        #expect(bar.thin)
        #expect(bar.label == "Preparing")
    }

    @Test
    func `a thin bar is four points and a regular bar six`() {
        #expect(DKProgress.height(thin: true) == 4)
        #expect(DKProgress.height(thin: false) == 6)
    }

    // MARK: - Fields

    @Test
    func `form fields are 28 points tall and mono fields use the mono face`() {
        #expect(DKFieldMetrics.height == 28)
        #expect(DKFieldMetrics.font(mono: true) == DK.Typeface.mono)
        #expect(DKFieldMetrics.font(mono: false) == DK.Typeface.body)
        #expect(DKFieldStyle.dkFieldMono.mono)
        #expect(!DKFieldStyle.dkField.mono)
    }
}
