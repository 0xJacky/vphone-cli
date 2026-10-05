import Testing
@testable import VPhoneDesignKit

/// Banners, status bars, step lists and the step strip.
@Suite("DesignKit feedback")
struct DKFeedbackTests {
    // MARK: - Steps

    @Test
    func `each step status maps to its glyph and tone`() {
        #expect(DKStepStatus.done.glyph == .check)
        #expect(DKStepStatus.done.tone == .success)
        #expect(DKStepStatus.active.glyph == .spinner)
        #expect(DKStepStatus.active.tone == .warning)
        #expect(DKStepStatus.pending.glyph == .pending)
        #expect(DKStepStatus.pending.tone == .idle)
        #expect(DKStepStatus.failed.glyph == .xCircle)
        #expect(DKStepStatus.failed.tone == .danger)
    }

    @Test
    func `percentage text rounds to a whole percent and clamps`() {
        #expect(DKStep.percentText(0.42) == "42%")
        #expect(DKStep.percentText(0.425) == "43%")
        #expect(DKStep.percentText(0) == "0%")
        #expect(DKStep.percentText(1) == "100%")
        #expect(DKStep.percentText(1.7) == "100%")
        #expect(DKStep.percentText(-0.2) == "0%")
        #expect(DKStep.percentText(.nan) == "0%")
    }

    @Test
    func `elapsed time reads as minutes and seconds, with hours past an hour`() {
        #expect(DKStep.elapsedText(2) == "0:02")
        #expect(DKStep.elapsedText(41.9) == "0:41")
        #expect(DKStep.elapsedText(152) == "2:32")
        #expect(DKStep.elapsedText(725) == "12:05")
        #expect(DKStep.elapsedText(3729) == "1:02:09")
        #expect(DKStep.elapsedText(-5) == "0:00")
        #expect(DKStep("Restore").elapsedText == nil)
    }

    @Test
    func `only the active step shows its progress`() {
        #expect(DKStep("Restore", status: .active, progress: 0.42).visibleProgress == 0.42)
        #expect(DKStep("Restore", status: .active, progress: 1.4).visibleProgress == 1)
        #expect(DKStep("Restore", status: .active).visibleProgress == nil)
        #expect(DKStep("Restore", status: .done, progress: 0.42).visibleProgress == nil)
        #expect(DKStep("Restore", status: .pending, progress: 0.42).visibleProgress == nil)
    }

    @Test
    func `a step speaks its state, percentage and time`() {
        let active = DKStep("Restore", elapsed: 152, status: .active, progress: 0.42)
        #expect(active.accessibilityValue == "In progress, 42%, 2:32")
        #expect(DKStep("Stop machine").accessibilityValue == "Pending")
        #expect(DKStep("Restore", elapsed: 41, status: .failed).accessibilityValue == "Failed, 0:41")
    }

    // MARK: - Strip

    @Test
    func `strip segments fill done steps and the current one to its progress`() {
        let segments = DKStepSegment.segments(count: 9, current: 1, progress: 0.63)
        #expect(segments.count == 9)
        #expect(segments[0] == DKStepSegment(fraction: 1, tone: .success))
        #expect(segments[1] == DKStepSegment(fraction: 0.63, tone: .warning))
        #expect(segments[2...].allSatisfy { $0.fraction == 0 })
        #expect(DKStepSegment.accessibilityValue(segments) == "1 of 9 steps done")
    }

    @Test
    func `a current index past the end fills every segment`() {
        let segments = DKStepSegment.segments(count: 3, current: 3)
        #expect(segments.map(\.fraction) == [1, 1, 1])
        #expect(segments.allSatisfy { $0.tone == .success })
        #expect(DKStepSegment.segments(count: 0, current: 0).isEmpty)
        #expect(DKStepSegment.segments(count: -2, current: 0).isEmpty)
    }

    @Test
    func `strip segments follow each step's status`() {
        let steps = [
            DKStep("Patch boot chain", status: .done),
            DKStep("Restore", status: .failed),
            DKStep("First boot", status: .active, progress: 0.25),
            DKStep("Stop machine"),
        ]
        let segments = DKStepSegment.segments(for: steps)
        #expect(segments.map(\.fraction) == [1, 1, 0.25, 0])
        #expect(segments.map(\.tone) == [.success, .danger, .warning, .warning])
        #expect(DKStepSegment(fraction: 2, tone: .warning).fraction == 1)
    }

    // MARK: - Banner

    @Test
    func `banner tones take the warning triangle except for notes`() {
        #expect(DKBannerTone.warning.glyph == .warning)
        #expect(DKBannerTone.danger.glyph == .warning)
        #expect(DKBannerTone.info.glyph == .info)
        #expect(DKBannerTone.allCases.map(\.tone) == [.warning, .danger, .info])
    }

    // MARK: - Status bar

    @Test
    func `the connection state picks the dot tone and default text`() {
        #expect(DKConnectionState(isConnected: true) == .connected)
        #expect(DKConnectionState.connected.tone == .success)
        #expect(DKConnectionState.connected.defaultText == "Connected")
        #expect(DKConnectionState.disconnected.tone == .warning)
        #expect(DKConnectionState.disconnected.defaultText == "Guest not connected")
    }

    @Test
    func `a status item speaks its title before its text`() {
        #expect(DKStatusItem("12%", glyph: .cpu, title: "CPU").accessibilityText == "CPU: 12%")
        #expect(DKStatusItem("vphoned 2.6.0").accessibilityText == "vphoned 2.6.0")
        #expect(DKStatusBar.height(compact: false) == DK.Metric.statusBarHeight)
        #expect(DKStatusBar.height(compact: true) == 22)
    }
}
