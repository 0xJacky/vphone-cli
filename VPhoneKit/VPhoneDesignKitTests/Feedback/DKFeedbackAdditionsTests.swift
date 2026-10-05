import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// Skipped steps and the status bar's toned text.
@MainActor
@Suite("DesignKit feedback additions")
struct DKFeedbackAdditionsTests {
    @Test
    func `a skipped step reads as skipped and fills its segment in gray`() {
        #expect(DKStepStatus.skipped.glyph == .minusCircle)
        #expect(DKStepStatus.skipped.tone == .idle)
        #expect(DKStepStatus.skipped.accessibilityText == "Skipped")
        let steps = [DKStep("Download", status: .skipped), DKStep("Patch", status: .done), DKStep("Restore")]
        let segments = DKStepSegment.segments(for: steps)
        #expect(segments[0] == DKStepSegment(fraction: 1, tone: .idle))
        #expect(DKStepSegment.accessibilityValue(segments) == "1 of 3 steps done")
        #expect(DKStep("Download", status: .skipped, progress: 0.5).visibleProgress == nil)
    }

    @Test
    func `the status bar's text takes its tone's text color, muted without one`() {
        #expect(DKStatusBar.textColor(for: .danger) == DKTone.danger.text)
        #expect(DKStatusBar.textColor(for: .success) == DKTone.success.text)
        #expect(DKStatusBar.textColor(for: nil) == DK.Palette.muted)
        #expect(DKStatusBar(text: "Copy failed", textTone: .danger).textTone == .danger)
    }
}
