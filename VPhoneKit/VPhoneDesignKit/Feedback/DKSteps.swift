import SwiftUI

// MARK: - Status

/// Where a step stands. A list normally has done steps, then one active step,
/// then pending ones; a failed step replaces the active one. A skipped step
/// was passed over without running, as when its work was already done.
public enum DKStepStatus: String, Sendable, CaseIterable, Hashable {
    case done, active, pending, failed, skipped

    /// The glyph in the step's leading mark. The active step draws a live
    /// spinner in place of `.spinner`.
    public var glyph: DKGlyph {
        switch self {
        case .done: .check
        case .active: .spinner
        case .pending: .pending
        case .failed: .xCircle
        case .skipped: .minusCircle
        }
    }

    /// The tone of the mark and of the step's segment in a `DKStepStrip`.
    public var tone: DKTone {
        switch self {
        case .done: .success
        case .active: .warning
        case .pending: .idle
        case .failed: .danger
        case .skipped: .idle
        }
    }

    /// The spoken state.
    public var accessibilityText: String {
        switch self {
        case .done: "Done"
        case .active: "In progress"
        case .pending: "Pending"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
    }

    var markColor: Color {
        switch self {
        case .done: DK.Palette.success
        case .active: DK.Palette.muted
        case .pending: DK.Palette.inkDisabled
        case .failed: DK.Palette.danger
        case .skipped: DK.Palette.inkDisabled
        }
    }
}

// MARK: - Step

/// One step of a long operation: what it is, the command that runs it, how long
/// it took or has been running, and, for the active step, how far along it is.
public struct DKStep: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var command: String?
    public var elapsed: TimeInterval?
    public var status: DKStepStatus
    /// From 0 to 1. Shown only while the step is active.
    public var progress: Double?

    public init(
        _ title: String,
        command: String? = nil,
        elapsed: TimeInterval? = nil,
        status: DKStepStatus = .pending,
        progress: Double? = nil,
        id: String? = nil,
    ) {
        self.id = id ?? title
        self.title = title
        self.command = command
        self.elapsed = elapsed
        self.status = status
        self.progress = progress
    }

    /// The progress shown under the active step, clamped to 0...1, or nil when
    /// no bar is shown.
    public var visibleProgress: Double? {
        guard status == .active, let progress else {
            return nil
        }
        return DKStep.clamp(progress)
    }

    /// "0:41", "12:05", "1:02:09"; nil when there is no time to show.
    public var elapsedText: String? {
        elapsed.map(DKStep.elapsedText(_:))
    }

    /// The spoken state, with the percentage and time when there are any:
    /// "In progress, 42%, 2:32".
    public var accessibilityValue: String {
        var parts = [status.accessibilityText]
        if let visibleProgress {
            parts.append(DKStep.percentText(visibleProgress))
        }
        if let elapsedText {
            parts.append(elapsedText)
        }
        return parts.joined(separator: ", ")
    }

    /// A fraction as a whole percentage: 0.425 → "43%". Values outside 0...1 are clamped.
    public static func percentText(_ fraction: Double) -> String {
        "\(Int((clamp(fraction) * 100).rounded()))%"
    }

    /// A duration as minutes and seconds, with hours once it passes an hour.
    public static func elapsedText(_ interval: TimeInterval) -> String {
        let total = interval.isFinite ? max(0, Int(interval)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let ss = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        if hours > 0 {
            let mm = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(mm):\(ss)"
        }
        return "\(minutes):\(ss)"
    }

    static func clamp(_ value: Double) -> Double {
        value.isNaN ? 0 : min(1, max(0, value))
    }
}

// MARK: - Step list

/// The step list of the machine-creation sheet. VoiceOver reads it as a list,
/// one item per step with its state. Each row can end with an accessory view,
/// such as a button that shows the step's full command.
public struct DKSteps: View {
    public var steps: [DKStep]
    public var label: String
    let accessory: ((DKStep) -> AnyView)?

    public init(_ steps: [DKStep], label: String = "Steps") {
        self.steps = steps
        self.label = label
        accessory = nil
    }

    /// A step list whose rows end with `accessory`, after the elapsed time.
    public init(_ steps: [DKStep], label: String = "Steps", @ViewBuilder accessory: @escaping (DKStep) -> some View) {
        self.steps = steps
        self.label = label
        self.accessory = { AnyView(accessory($0)) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(steps) { step in
                DKStepRow(step: step, accessory: accessory?(step))
            }
        }
        .accessibilityRepresentation {
            List(steps) { step in
                Text(step.title)
                    .accessibilityValue(step.accessibilityValue)
                    .accessibilityHint(step.command ?? "")
            }
            .accessibilityLabel(label)
        }
    }
}

private struct DKStepRow: View {
    let step: DKStep
    var accessory: AnyView?

    var body: some View {
        HStack(alignment: .top, spacing: DK.Space.s3) {
            mark
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(step.status == .active ? DK.Typeface.bodyStrong : DK.Typeface.body)
                    .foregroundStyle(step.status == .pending || step.status == .skipped ? DK.Palette.muted : DK.Palette.ink)
                if let command = step.command, !command.isEmpty {
                    Text(command)
                        .font(DK.Typeface.mono)
                        .foregroundStyle(DK.Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let progress = step.visibleProgress {
                    HStack(spacing: DK.Space.s2) {
                        DKStepBar(value: progress, tone: .warning)
                        Text(DKStep.percentText(progress))
                            .font(DK.Typeface.caption)
                            .monospacedDigit()
                            .foregroundStyle(DK.Palette.muted)
                    }
                    .padding(.top, DK.Space.s1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let elapsedText = step.elapsedText {
                Text(elapsedText)
                    .font(DK.Typeface.caption)
                    .monospacedDigit()
                    .foregroundStyle(DK.Palette.muted)
            }
            if let accessory {
                accessory
            }
        }
        .padding(DK.Space.s2)
        .background {
            if step.status == .active {
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .fill(DK.Palette.warningSurface)
            }
        }
    }

    @ViewBuilder
    private var mark: some View {
        if step.status == .active {
            // Core Animation, not `ProgressView`: the system spinner stops when
            // a row around it redraws, and SwiftUI animation redraws the window.
            DKSpinner(size: 16, label: step.status.accessibilityText)
        } else {
            DKIcon(step.status.glyph, size: 18)
                .foregroundStyle(step.status.markColor)
        }
    }
}

// MARK: - Strip

/// One segment of a `DKStepStrip`: how full it is and the tone of its fill.
public struct DKStepSegment: Hashable, Sendable {
    public var fraction: Double
    public var tone: DKTone

    public init(fraction: Double, tone: DKTone) {
        self.fraction = DKStep.clamp(fraction)
        self.tone = tone
    }

    /// Segments for a list of steps: done and failed steps fill their segment,
    /// skipped ones fill it in gray, the active one fills to its progress,
    /// pending ones stay empty.
    public static func segments(for steps: [DKStep]) -> [DKStepSegment] {
        steps.map { step in
            switch step.status {
            case .done: DKStepSegment(fraction: 1, tone: .success)
            case .failed: DKStepSegment(fraction: 1, tone: .danger)
            case .skipped: DKStepSegment(fraction: 1, tone: .idle)
            case .active: DKStepSegment(fraction: step.progress ?? 0, tone: .warning)
            case .pending: DKStepSegment(fraction: 0, tone: .warning)
            }
        }
    }

    /// Segments for `count` steps where steps before `current` are done and
    /// `current` is `progress` of the way through. A `current` of `count` or
    /// more means every step is done.
    public static func segments(count: Int, current: Int, progress: Double? = nil) -> [DKStepSegment] {
        (0 ..< max(0, count)).map { index in
            if index < current {
                DKStepSegment(fraction: 1, tone: .success)
            } else if index == current {
                DKStepSegment(fraction: progress ?? 0, tone: .warning)
            } else {
                DKStepSegment(fraction: 0, tone: .warning)
            }
        }
    }

    /// The spoken summary of a strip: "1 of 9 steps done".
    public static func accessibilityValue(_ segments: [DKStepSegment]) -> String {
        let done = segments.count(where: { $0.tone == .success && $0.fraction >= 1 })
        return "\(done) of \(segments.count) steps done"
    }
}

/// The segmented strip across the top of the Creation sheet: one thin bar per
/// step, green when done, amber and partly filled for the current step.
public struct DKStepStrip: View {
    public var segments: [DKStepSegment]
    public var label: String

    public init(segments: [DKStepSegment], label: String = "Overall progress") {
        self.segments = segments
        self.label = label
    }

    public init(_ steps: [DKStep], label: String = "Overall progress") {
        self.init(segments: DKStepSegment.segments(for: steps), label: label)
    }

    public init(count: Int, current: Int, progress: Double? = nil, label: String = "Overall progress") {
        self.init(segments: DKStepSegment.segments(count: count, current: current, progress: progress), label: label)
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(segments.indices, id: \.self) { index in
                DKStepBar(value: segments[index].fraction, tone: segments[index].tone, thin: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(DKStepSegment.accessibilityValue(segments))
    }
}

// MARK: - Bar

/// The design's progress bar (`.dk-progress`), kept private to this group: a
/// rounded track with a tone fill.
struct DKStepBar: View {
    var value: Double
    var tone: DKTone
    var thin = true

    var body: some View {
        let height: CGFloat = thin ? 4 : 6
        let shape = RoundedRectangle(cornerRadius: height / 2, style: .continuous)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                shape.fill(DK.Palette.track)
                shape.fill(tone.color)
                    .frame(width: proxy.size.width * DKStep.clamp(value))
            }
        }
        .frame(height: height)
        .frame(minWidth: 40, maxWidth: .infinity)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

private struct DKStepsPreviewBoard: View {
    private let steps = [
        DKStep("Create machine", command: "vm new pcc-research-2 --cpu 8 --memory 8192 --disk-size 64", elapsed: 2, status: .done),
        DKStep("Download and prepare firmware", command: "fw prepare pcc-research-2 --device iPhone17,3 · iPhone IPSW 5.9 of 9.4 GB", elapsed: 149, status: .active, progress: 0.63),
        DKStep("Patch boot chain", command: "fw patch pcc-research-2"),
        DKStep("Boot into DFU", command: "vm launch pcc-research-2 --dfu"),
        DKStep("Restore", command: "restore pcc-research-2"),
    ]

    private let failed = [
        DKStep("Patch boot chain", command: "fw patch pcc-research-2", elapsed: 41, status: .done),
        DKStep("Restore", command: "restore pcc-research-2", elapsed: 152, status: .failed),
        DKStep("Stop machine", command: "vm stop pcc-research-2"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s4) {
            DKStepStrip(count: 9, current: 1, progress: 0.63)
            DKSteps(steps)
            Divider()
            DKStepStrip(failed)
            DKSteps(failed)
        }
        .padding(DK.Space.s6)
        .frame(width: 640)
        .background(DK.Palette.window)
    }
}

#Preview("Steps – Light") {
    DKStepsPreviewBoard().preferredColorScheme(.light)
}

#Preview("Steps – Dark") {
    DKStepsPreviewBoard().preferredColorScheme(.dark)
}
