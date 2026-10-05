import Foundation

/// One way to write a figure everywhere: bytes, counts, durations, percentages
/// and timestamps.
///
/// - Pure functions, callable from any isolation.
/// - Independent of the system locale: the decimal point is always ".", the
///   grouping separator always ",", dates always Gregorian with a 24-hour clock.
///   Numbers go through `String(format:)` without a locale (POSIX) and hand-made
///   grouping; dates through Gregorian calendar components joined by hand, with
///   no `DateFormatter` and so no shared mutable state.
/// - Every tiered format rounds first and picks the tier second: 1,048,575 bytes
///   is "1.00 MB", not "1024.0 KB"; 999,950 is "1.0M", not "1000.0K"; 59.996
///   seconds is "1m 00s", not "60.00 s".
///
/// Ported from uAppKit's `UFormat`, rules and tests unchanged; its Chinese
/// relative-time phrases are left out.
public enum DKFormat {
    /// What a missing value reads as: nil, a negative duration, a value that is not finite.
    public static let placeholder = "—"

    // MARK: - Bytes

    private static let byteUnits = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]

    /// Bytes in powers of 1024: whole bytes, then three significant digits
    /// ("1.50 KB", "12.3 GB", "123 GB"). `Int64` tops out near 8 EiB, so the
    /// scale goes one step past PB to EB rather than printing "8192 PB".
    public static func bytes(_ value: Int64?) -> String {
        guard let value else {
            return placeholder
        }
        let sign = value < 0 ? "-" : ""
        let magnitude = value.magnitude
        if magnitude < 1024 {
            return "\(sign)\(magnitude) B"
        }
        var unit = 1
        var scaled = Double(magnitude) / 1024
        while scaled >= 1024, unit < byteUnits.count - 1 {
            scaled /= 1024
            unit += 1
        }
        var (rounded, decimals) = threeSignificant(scaled)
        // Rounding up to 1024 moves to the next unit: 1023.6 KB is 1.00 MB.
        if rounded >= 1024, unit < byteUnits.count - 1 {
            scaled /= 1024
            unit += 1
            (rounded, decimals) = threeSignificant(scaled)
        }
        // The design writes sizes without trailing zeros: "8 GB", "9.4 GB", "38.1 GB".
        return "\(sign)\(trimmed(fixed(rounded, decimals))) \(byteUnits[unit])"
    }

    public static func bytes(_ value: Int) -> String {
        bytes(Int64(value))
    }

    // MARK: - Counts

    /// A whole number with grouping: "1,234,567", "-1,234".
    public static func count(_ value: Int64?) -> String {
        guard let value else {
            return placeholder
        }
        return (value < 0 ? "-" : "") + grouped(value.magnitude)
    }

    public static func count(_ value: Int) -> String {
        count(Int64(value))
    }

    private static let compactUnits = ["", "K", "M", "B", "T"]

    /// A short count: below 10,000 as `count(_:)`, then K, M, B and T with one
    /// decimal under 10 and none from 10 up ("12K", "1.2M").
    public static func compact(_ value: Int64) -> String {
        let magnitude = value.magnitude
        if magnitude < 10000 {
            return count(value)
        }
        let sign = value < 0 ? "-" : ""
        var unit = 1
        var scaled = Double(magnitude) / 1000
        while scaled >= 1000, unit < compactUnits.count - 1 {
            scaled /= 1000
            unit += 1
        }
        var (rounded, decimals) = compactDigits(scaled)
        // Rounding up to 1000 moves to the next unit: 999.7K is 1.0M.
        if rounded >= 1000, unit < compactUnits.count - 1 {
            scaled /= 1000
            unit += 1
            (rounded, decimals) = compactDigits(scaled)
        }
        let digits = if decimals == 0, rounded >= 1000, rounded < 1e18 {
            // Only past T: "9,223,372T".
            grouped(UInt64(rounded))
        } else {
            fixed(rounded, decimals)
        }
        return "\(sign)\(digits)\(compactUnits[unit])"
    }

    public static func compact(_ value: Int) -> String {
        compact(Int64(value))
    }

    /// An estimate: "≈" before the text, with no space.
    public static func approx(_ text: String) -> String {
        "≈" + text
    }

    // MARK: - Durations

    /// A duration: whole µs, then ms and s at three significant digits, then
    /// "2m 05s", "1h 02m" and "3d 04h". Negative and non-finite values read "—".
    public static func duration(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return placeholder
        }
        if seconds < 1e-3 {
            let micros = (seconds * 1e6).rounded(.toNearestOrAwayFromZero)
            if micros < 1000 {
                return "\(Int(micros)) µs"
            }
        }
        if seconds < 1 {
            let (milliseconds, decimals) = threeSignificant(seconds * 1000)
            if milliseconds < 1000 {
                return "\(fixed(milliseconds, decimals)) ms"
            }
        }
        if seconds < 60 {
            let (rounded, decimals) = threeSignificant(seconds)
            if rounded < 60 {
                return "\(fixed(rounded, decimals)) s"
            }
        }
        let totalSeconds = seconds.rounded(.toNearestOrAwayFromZero)
        if totalSeconds < 3600 {
            return "\(Int(totalSeconds) / 60)m " + twoDigits(Int(totalSeconds) % 60) + "s"
        }
        let totalMinutes = (seconds / 60).rounded(.toNearestOrAwayFromZero)
        if totalMinutes < 24 * 60 {
            let hours = (totalMinutes / 60).rounded(.down)
            return String(format: "%.0fh ", hours) + twoDigits(Int(totalMinutes - hours * 60)) + "m"
        }
        // A day or more: "3d 04h". 23h 59m 40s rounds up to "1d 00h".
        let totalHours = (seconds / 3600).rounded(.toNearestOrAwayFromZero)
        let days = (totalHours / 24).rounded(.down)
        return String(format: "%.0fd ", days) + twoDigits(Int(totalHours - days * 24)) + "h"
    }

    /// A duration counted in whole seconds (a TTL, an uptime, time left): under a
    /// minute "45 s", without the decimals of `duration(seconds:)`; from a minute
    /// up the same as `duration(seconds:)`.
    public static func duration(wholeSeconds: Int64) -> String {
        guard wholeSeconds >= 0 else {
            return placeholder
        }
        if wholeSeconds < 60 {
            return "\(wholeSeconds) s"
        }
        return duration(seconds: Double(wholeSeconds))
    }

    public static func duration(_ duration: Duration) -> String {
        let components = duration.components
        return self.duration(seconds: Double(components.seconds) + Double(components.attoseconds) * 1e-18)
    }

    public static func duration(milliseconds: Double) -> String {
        duration(seconds: milliseconds / 1000)
    }

    // MARK: - Percentages

    /// A fraction of 0...1 as a percentage rounded to `decimals` places. Not
    /// clamped; never "-0%".
    public static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        let places = min(max(decimals, 0), 6)
        let rounded = round(fraction * 100, places)
        guard rounded.isFinite else {
            return placeholder
        }
        return fixed(rounded == 0 ? 0 : rounded, places) + "%"
    }

    // MARK: - Timestamps

    // Each format has a variant that takes the time zone, for tests and for
    // callers that need a fixed one such as UTC; the other uses the current one.

    private static let gregorian = Calendar(identifier: .gregorian)

    /// "2026-09-28 13:05:07"
    public static func dateTime(_ date: Date) -> String {
        dateTime(date, timeZone: .current)
    }

    public static func dateTime(_ date: Date, timeZone: TimeZone) -> String {
        let parts = parts(date, timeZone)
        return parts.ymd + " " + parts.hms
    }

    /// "2026-09-28 13:05:07.123", the milliseconds truncated so the second never rounds up.
    public static func dateTimeMillis(_ date: Date) -> String {
        dateTimeMillis(date, timeZone: .current)
    }

    public static func dateTimeMillis(_ date: Date, timeZone: TimeZone) -> String {
        let parts = parts(date, timeZone)
        return parts.ymd + " " + parts.hms + "." + parts.millis
    }

    /// "2026-09-28 13:05"
    public static func dateTimeMinutes(_ date: Date) -> String {
        dateTimeMinutes(date, timeZone: .current)
    }

    public static func dateTimeMinutes(_ date: Date, timeZone: TimeZone) -> String {
        let parts = parts(date, timeZone)
        return parts.ymd + " " + parts.hm
    }

    /// "13:05:07"
    public static func time(_ date: Date) -> String {
        time(date, timeZone: .current)
    }

    public static func time(_ date: Date, timeZone: TimeZone) -> String {
        parts(date, timeZone).hms
    }

    /// "13:05:07.123"
    public static func timeMillis(_ date: Date) -> String {
        timeMillis(date, timeZone: .current)
    }

    public static func timeMillis(_ date: Date, timeZone: TimeZone) -> String {
        let parts = parts(date, timeZone)
        return parts.hms + "." + parts.millis
    }

    /// "09/28 13:05:07"
    public static func monthDayTime(_ date: Date) -> String {
        monthDayTime(date, timeZone: .current)
    }

    public static func monthDayTime(_ date: Date, timeZone: TimeZone) -> String {
        let parts = parts(date, timeZone)
        return twoDigits(parts.month) + "/" + twoDigits(parts.day) + " " + parts.hms
    }

    // MARK: - Internals

    /// Three significant digits: two decimals under 10, one under 100, none
    /// above; a value that rounds across a step is rounded again with one
    /// decimal fewer (9.996 is 10.0, 99.96 is 100). `x` is not negative.
    private static func threeSignificant(_ x: Double) -> (value: Double, decimals: Int) {
        var decimals = x < 10 ? 2 : (x < 100 ? 1 : 0)
        var rounded = round(x, decimals)
        if decimals == 2, rounded >= 10 {
            decimals = 1
            rounded = round(x, 1)
        }
        if decimals == 1, rounded >= 100 {
            decimals = 0
            rounded = round(x, 0)
        }
        return (rounded, decimals)
    }

    /// One decimal under 10, none from 10 up; 9.96 is 10.
    private static func compactDigits(_ x: Double) -> (value: Double, decimals: Int) {
        if x < 10 {
            let rounded = round(x, 1)
            if rounded < 10 {
                return (rounded, 1)
            }
        }
        return (round(x, 0), 0)
    }

    private static func round(_ x: Double, _ decimals: Int) -> Double {
        guard decimals > 0 else {
            return x.rounded(.toNearestOrAwayFromZero)
        }
        let scale = pow(10, Double(decimals))
        return (x * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    /// Fixed decimals, always with "." (`String(format:)` without a locale is POSIX).
    private static func fixed(_ x: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", x)
    }

    /// Drops a fraction's trailing zeros and a bare point: "8.00" → "8", "1.50" → "1.5".
    private static func trimmed(_ text: String) -> String {
        guard text.contains(".") else {
            return text
        }
        var out = Substring(text)
        while out.hasSuffix("0") {
            out = out.dropLast()
        }
        if out.hasSuffix(".") {
            out = out.dropLast()
        }
        return String(out)
    }

    private static func grouped(_ magnitude: UInt64) -> String {
        let digits = String(magnitude)
        guard digits.count > 3 else {
            return digits
        }
        var out = ""
        out.reserveCapacity(digits.count + digits.count / 3)
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                out.append(",")
            }
            out.append(character)
        }
        return out
    }

    private static func twoDigits(_ n: Int) -> String {
        n >= 0 && n < 10 ? "0\(n)" : "\(n)"
    }

    private static func fourDigits(_ n: Int) -> String {
        let text = String(n)
        return text.count >= 4 ? text : String(repeating: "0", count: 4 - text.count) + text
    }

    private struct Parts {
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var minute: Int
        var second: Int
        var millisecond: Int

        var ymd: String {
            DKFormat.fourDigits(year) + "-" + DKFormat.twoDigits(month) + "-" + DKFormat.twoDigits(day)
        }

        var hm: String {
            DKFormat.twoDigits(hour) + ":" + DKFormat.twoDigits(minute)
        }

        var hms: String {
            hm + ":" + DKFormat.twoDigits(second)
        }

        var millis: String {
            millisecond < 10 ? "00\(millisecond)" : (millisecond < 100 ? "0\(millisecond)" : "\(millisecond)")
        }
    }

    /// Calendar components of the second rounded down, with the milliseconds
    /// truncated from the fraction, so the second and the milliseconds always
    /// agree and ".1000" never appears.
    private static func parts(_ date: Date, _ timeZone: TimeZone) -> Parts {
        let interval = date.timeIntervalSinceReferenceDate
        let whole = interval.rounded(.down)
        // +1 µs absorbs binary error (.123 stored as .12299999…).
        let milliseconds = min(999, max(0, Int(((interval - whole) * 1000 + 1e-3).rounded(.down))))
        var calendar = gregorian
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSinceReferenceDate: whole))
        return Parts(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            millisecond: milliseconds,
        )
    }
}
