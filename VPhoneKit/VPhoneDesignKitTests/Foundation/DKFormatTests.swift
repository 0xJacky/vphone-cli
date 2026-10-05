import Foundation
import Testing
@testable import VPhoneDesignKit

/// The format contract of `DKFormat`, ported from uAppKit's `UFormatTests`.
/// Every tiered format rounds first and picks the tier second, so each tier
/// boundary is tested on both sides: just across after rounding, and just short.
@Suite("DesignKit formatting")
struct DKFormatTests {

    private static let KiB: Int64 = 1024
    private static let MiB: Int64 = 1024 * 1024
    private static let GiB: Int64 = 1024 * 1024 * 1024
    private static let TiB: Int64 = 1024 * GiB
    private static let PiB: Int64 = 1024 * TiB

    // MARK: - bytes

    @Test
    func testBytesContractExamples() {
        #expect(DKFormat.bytes(512 as Int64?) == "512 B")
        #expect(DKFormat.bytes(1536 as Int64?) == "1.5 KB")
        #expect(DKFormat.bytes(1_048_575 as Int64?) == "1 MB")
        #expect(DKFormat.bytes(5_000_000 as Int64?) == "4.77 MB")
        #expect(DKFormat.bytes(3 * Self.GiB) == "3 GB")
        #expect(DKFormat.bytes(Int64(12.3 * Double(Self.GiB))) == "12.3 GB")
        #expect(DKFormat.bytes(123 * Self.GiB) == "123 GB")
        #expect(DKFormat.bytes(5 * Self.TiB) == "5 TB")
        #expect(DKFormat.bytes(Self.PiB) == "1 PB")
    }

    @Test
    func testBytesNilZeroAndIntOverload() {
        #expect(DKFormat.bytes(nil as Int64?) == "—")
        #expect(DKFormat.bytes(0 as Int64?) == "0 B")
        #expect(DKFormat.bytes(0) == "0 B")
        #expect(DKFormat.bytes(1536) == "1.5 KB")
        #expect(DKFormat.bytes(Int.max) == DKFormat.bytes(Int64.max))
    }

    @Test
    func testBytesByteTierBoundary() {
        #expect(DKFormat.bytes(1023) == "1023 B")
        #expect(DKFormat.bytes(1024) == "1 KB")
        #expect(DKFormat.bytes(1025) == "1 KB")
    }

    @Test
    func testBytesDecimalBoundariesRoundFirst() {
        // 10 KB: 9.994 is 9.99; 9.995 is 10.0, not "10.00".
        #expect(DKFormat.bytes(10_234) == "9.99 KB")
        #expect(DKFormat.bytes(10_235) == "10 KB")
        #expect(DKFormat.bytes(10 * Self.KiB) == "10 KB")
        // 100 KB: 99.949 is 99.9; 99.950 is 100, not "100.0".
        #expect(DKFormat.bytes(102_348) == "99.9 KB")
        #expect(DKFormat.bytes(102_349) == "100 KB")
        #expect(DKFormat.bytes(100 * Self.KiB) == "100 KB")
        #expect(DKFormat.bytes(101 * Self.KiB) == "101 KB")
    }

    @Test
    func testBytesUnitBoundariesRoundFirst() {
        // 1023.499 KB is 1023 KB; 1023.5 KB is 1.00 MB, never "1024 KB".
        #expect(DKFormat.bytes(1_048_063) == "1023 KB")
        #expect(DKFormat.bytes(1_048_064) == "1 MB")
        #expect(DKFormat.bytes(Self.MiB) == "1 MB")
        #expect(DKFormat.bytes(Self.MiB + 1) == "1 MB")
        #expect(DKFormat.bytes(Self.GiB - 1) == "1 GB")
        #expect(DKFormat.bytes(Self.GiB) == "1 GB")
        #expect(DKFormat.bytes(Self.TiB - 1) == "1 TB")
        #expect(DKFormat.bytes(Self.PiB - 1) == "1 PB")
        #expect(DKFormat.bytes(1023 * Self.MiB) == "1023 MB")
        #expect(DKFormat.bytes(10 * Self.GiB - 1) == "10 GB")
    }

    @Test
    func testBytesNeverPrintsFourDigitsInScaledTiers() {
        // Around the top of each unit: a scaled unit never shows 1024 or more.
        for unit: Int64 in [Self.KiB, Self.MiB, Self.GiB, Self.TiB] {
            for delta: Int64 in [-unit, -unit / 2, -unit / 1000, -1, 0, 1] {
                let s = DKFormat.bytes(1024 * unit + delta)
                #expect(!(s.hasPrefix("1024")), "\(s)")
                #expect(!(s.hasPrefix("1023.")), "\(s)")
            }
        }
    }

    @Test
    func testBytesNegative() {
        #expect(DKFormat.bytes(-512) == "-512 B")
        #expect(DKFormat.bytes(-1536) == "-1.5 KB")
        #expect(DKFormat.bytes(-1_048_575) == "-1 MB")
    }

    @Test
    func testBytesExtremes() {
        // Int64.max is about 8 EiB: the extra EB unit, never "8192 PB", and no crash.
        #expect(DKFormat.bytes(Int64.max) == "8 EB")
        #expect(DKFormat.bytes(Int64.min) == "-8 EB")
        #expect(DKFormat.bytes(1024 * Self.PiB) == "1 EB")
    }

    // MARK: - count

    @Test
    func testCount() {
        #expect(DKFormat.count(nil as Int64?) == "—")
        #expect(DKFormat.count(0) == "0")
        #expect(DKFormat.count(7) == "7")
        #expect(DKFormat.count(999) == "999")
        #expect(DKFormat.count(1000) == "1,000")
        #expect(DKFormat.count(12_345) == "12,345")
        #expect(DKFormat.count(123_456) == "123,456")
        #expect(DKFormat.count(1_234_567) == "1,234,567")
        #expect(DKFormat.count(1_234_567 as Int64?) == "1,234,567")
        #expect(DKFormat.count(-999) == "-999")
        #expect(DKFormat.count(-1000) == "-1,000")
        #expect(DKFormat.count(-1234) == "-1,234")
    }

    @Test
    func testCountExtremes() {
        #expect(DKFormat.count(Int64.max) == "9,223,372,036,854,775,807")
        #expect(DKFormat.count(Int64.min) == "-9,223,372,036,854,775,808")
        #expect(DKFormat.count(Int.min) == "-9,223,372,036,854,775,808")
    }

    // MARK: - compact

    @Test
    func testCompactContractExamples() {
        #expect(DKFormat.compact(9_999) == "9,999")
        #expect(DKFormat.compact(12_345) == "12K")
        #expect(DKFormat.compact(15_600) == "16K")
        #expect(DKFormat.compact(999_700) == "1.0M")
        #expect(DKFormat.compact(1_234_567) == "1.2M")
        #expect(DKFormat.compact(12_345_678) == "12M")
        #expect(DKFormat.compact(9_960_000) == "10M")
        #expect(DKFormat.compact(8_420_000_000) == "8.4B")
    }

    @Test
    func testCompactSmallValuesUseCount() {
        #expect(DKFormat.compact(0) == "0")
        #expect(DKFormat.compact(42) == "42")
        #expect(DKFormat.compact(1_000) == "1,000")
        #expect(DKFormat.compact(-9_999) == "-9,999")
        #expect(DKFormat.compact(10_000) == "10K")
        #expect(DKFormat.compact(10_001) == "10K")
    }

    @Test
    func testCompactBoundariesRoundFirst() {
        #expect(DKFormat.compact(15_500) == "16K")          // rounded, not truncated
        #expect(DKFormat.compact(99_999) == "100K")
        #expect(DKFormat.compact(999_499) == "999K")
        #expect(DKFormat.compact(999_500) == "1.0M")        // not "1000K"
        #expect(DKFormat.compact(999_950) == "1.0M")        // not "1000.0K"
        #expect(DKFormat.compact(1_000_000) == "1.0M")
        #expect(DKFormat.compact(9_940_000) == "9.9M")
        #expect(DKFormat.compact(10_000_000) == "10M")
        #expect(DKFormat.compact(999_499_999) == "999M")
        #expect(DKFormat.compact(999_500_000) == "1.0B")
        #expect(DKFormat.compact(999_999_999_999) == "1.0T")
        #expect(DKFormat.compact(1_000_000_000_000) == "1.0T")
        #expect(DKFormat.compact(12_300_000_000_000) == "12T")
    }

    @Test
    func testCompactNegativeAndIntOverload() {
        #expect(DKFormat.compact(-12_345) == "-12K")
        #expect(DKFormat.compact(-999_700) == "-1.0M")
        #expect(DKFormat.compact(12_345 as Int) == "12K")
    }

    @Test
    func testCompactExtremes() {
        #expect(DKFormat.compact(Int64.max) == "9,223,372T")
        #expect(DKFormat.compact(Int64.min) == "-9,223,372T")
        #expect(DKFormat.compact(Int.max) == DKFormat.compact(Int64.max))
    }

    @Test
    func testApprox() {
        #expect(DKFormat.approx("12K") == "≈12K")
        #expect(DKFormat.approx(DKFormat.compact(1_234_567)) == "≈1.2M")
        #expect(DKFormat.approx("") == "≈")
    }

    // MARK: - duration

    @Test
    func testDurationMicroseconds() {
        #expect(DKFormat.duration(seconds: 0) == "0 µs")
        #expect(DKFormat.duration(seconds: -0.0) == "0 µs")
        #expect(DKFormat.duration(seconds: 0.000412) == "412 µs")
        #expect(DKFormat.duration(seconds: 0.0000004) == "0 µs")
        #expect(DKFormat.duration(seconds: 0.0009994) == "999 µs")
        // µ is U+00B5 MICRO SIGN, not the Greek letter U+03BC.
        #expect(DKFormat.duration(seconds: 0.000412).unicodeScalars.contains("\u{00B5}"))
        #expect(!(DKFormat.duration(seconds: 0.000412).unicodeScalars.contains("\u{03BC}")))
    }

    @Test
    func testDurationMillisecondsAndSeconds() {
        #expect(DKFormat.duration(seconds: 0.00123) == "1.23 ms")
        #expect(DKFormat.duration(seconds: 0.0123) == "12.3 ms")
        #expect(DKFormat.duration(seconds: 0.123) == "123 ms")
        #expect(DKFormat.duration(seconds: 1.23) == "1.23 s")
        #expect(DKFormat.duration(seconds: 12.3) == "12.3 s")
        #expect(DKFormat.duration(seconds: 59.94) == "59.9 s")
    }

    @Test
    func testDurationBoundariesRoundFirst() {
        #expect(DKFormat.duration(seconds: 0.0009996) == "1.00 ms")   // not "1000 µs"
        #expect(DKFormat.duration(seconds: 0.001) == "1.00 ms")
        #expect(DKFormat.duration(seconds: 0.009994) == "9.99 ms")
        #expect(DKFormat.duration(seconds: 0.009996) == "10.0 ms")    // not "10.00 ms"
        #expect(DKFormat.duration(seconds: 0.09994) == "99.9 ms")
        #expect(DKFormat.duration(seconds: 0.09996) == "100 ms")      // not "100.0 ms"
        #expect(DKFormat.duration(seconds: 0.9994) == "999 ms")
        #expect(DKFormat.duration(seconds: 0.99996) == "1.00 s")      // not "1000 ms"
        #expect(DKFormat.duration(seconds: 1) == "1.00 s")
        #expect(DKFormat.duration(seconds: 9.996) == "10.0 s")
        #expect(DKFormat.duration(seconds: 59.96) == "1m 00s")
        #expect(DKFormat.duration(seconds: 59.996) == "1m 00s")       // not "60.00 s"
        #expect(DKFormat.duration(seconds: 60) == "1m 00s")
    }

    @Test
    func testDurationMinutesAndHours() {
        #expect(DKFormat.duration(seconds: 125) == "2m 05s")
        #expect(DKFormat.duration(seconds: 125.43) == "2m 05s")
        #expect(DKFormat.duration(seconds: 125.5) == "2m 06s")
        #expect(DKFormat.duration(seconds: 3599.4) == "59m 59s")
        #expect(DKFormat.duration(seconds: 3599.5) == "1h 00m")       // not "60m 00s"
        #expect(DKFormat.duration(seconds: 3600) == "1h 00m")
        #expect(DKFormat.duration(seconds: 3720) == "1h 02m")
        #expect(DKFormat.duration(seconds: 7500) == "2h 05m")
        #expect(DKFormat.duration(seconds: 7229) == "2h 00m")
        #expect(DKFormat.duration(seconds: 7230) == "2h 01m")
        #expect(DKFormat.duration(seconds: 2 * 3600 + 59 * 60 + 45) == "3h 00m")
        #expect(DKFormat.duration(seconds: 100 * 3600) == "4d 04h")
    }

    @Test
    func testDurationDayTier() {
        #expect(DKFormat.duration(seconds: 86_369) == "23h 59m")   // 23h 59m 29s
        #expect(DKFormat.duration(seconds: 86_370) == "1d 00h")      // a full day after rounding, not "24h 00m"
        #expect(DKFormat.duration(seconds: 86_400) == "1d 00h")
        #expect(DKFormat.duration(seconds: 3 * 86_400 + 4 * 3600) == "3d 04h")
        #expect(DKFormat.duration(seconds: 3 * 86_400 + 23 * 3600 + 1800) == "4d 00h")
        #expect(DKFormat.duration(seconds: 400 * 86_400) == "400d 00h")
    }

    @Test
    func testDurationWholeSeconds() {
        #expect(DKFormat.duration(wholeSeconds: 0) == "0 s")
        #expect(DKFormat.duration(wholeSeconds: 45) == "45 s")
        #expect(DKFormat.duration(wholeSeconds: 59) == "59 s")
        #expect(DKFormat.duration(wholeSeconds: 60) == "1m 00s")
        #expect(DKFormat.duration(wholeSeconds: 125) == "2m 05s")
        #expect(DKFormat.duration(wholeSeconds: 3600) == "1h 00m")
        #expect(DKFormat.duration(wholeSeconds: 3 * 86_400 + 4 * 3600) == "3d 04h")
        #expect(DKFormat.duration(wholeSeconds: -1) == "—")
        #expect(DKFormat.duration(wholeSeconds: .max).hasSuffix("h"))
    }

    @Test
    func testDurationInvalidInputs() {
        #expect(DKFormat.duration(seconds: -1) == "—")
        #expect(DKFormat.duration(seconds: -0.000001) == "—")
        #expect(DKFormat.duration(seconds: .nan) == "—")
        #expect(DKFormat.duration(seconds: .infinity) == "—")
        #expect(DKFormat.duration(seconds: -.infinity) == "—")
        #expect(DKFormat.duration(milliseconds: .nan) == "—")
        #expect(DKFormat.duration(milliseconds: -5) == "—")
    }

    @Test
    func testDurationHugeValuesDoNotCrash() {
        #expect(DKFormat.duration(seconds: 1e300).hasSuffix("h"))
        #expect(DKFormat.duration(seconds: .greatestFiniteMagnitude).hasSuffix("h"))
        #expect(DKFormat.duration(.seconds(Int64.max)).hasSuffix("h"))
    }

    @Test
    func testDurationOverloads() {
        #expect(DKFormat.duration(.microseconds(412)) == "412 µs")
        #expect(DKFormat.duration(.milliseconds(1500)) == "1.50 s")
        #expect(DKFormat.duration(.seconds(125)) == "2m 05s")
        #expect(DKFormat.duration(.zero) == "0 µs")
        #expect(DKFormat.duration(.seconds(-1)) == "—")
        #expect(DKFormat.duration(milliseconds: 0.412) == "412 µs")
        #expect(DKFormat.duration(milliseconds: 12.3) == "12.3 ms")
        #expect(DKFormat.duration(milliseconds: 0.9996) == "1.00 ms")
        #expect(DKFormat.duration(milliseconds: 999.96) == "1.00 s")
        #expect(DKFormat.duration(milliseconds: 59_996) == "1m 00s")
    }

    // MARK: - percent

    @Test
    func testPercent() {
        #expect(DKFormat.percent(0.42) == "42%")
        #expect(DKFormat.percent(0.987, decimals: 1) == "98.7%")
        #expect(DKFormat.percent(0) == "0%")
        #expect(DKFormat.percent(1) == "100%")
        #expect(DKFormat.percent(0.994) == "99%")
        #expect(DKFormat.percent(0.999) == "100%")          // rounded, not truncated to 99%
        #expect(DKFormat.percent(0.004) == "0%")
        #expect(DKFormat.percent(0.006) == "1%")
        #expect(DKFormat.percent(0.123456, decimals: 2) == "12.35%")
        #expect(DKFormat.percent(0.5, decimals: 1) == "50.0%")
        #expect(DKFormat.percent(0.42, decimals: -3) == "42%")
    }

    @Test
    func testPercentDoesNotClampAndHasNoNegativeZero() {
        #expect(DKFormat.percent(1.5) == "150%")
        #expect(DKFormat.percent(-0.25) == "-25%")
        #expect(DKFormat.percent(-0.001) == "0%")
        #expect(DKFormat.percent(-0.0001, decimals: 1) == "0.0%")
    }

    @Test
    func testPercentNonFinite() {
        #expect(DKFormat.percent(.nan) == "—")
        #expect(DKFormat.percent(.infinity) == "—")
        #expect(DKFormat.percent(-.infinity, decimals: 1) == "—")
        #expect(DKFormat.percent(.greatestFiniteMagnitude) == "—")   // overflows when multiplied by 100
    }

    // MARK: - Timestamps

    private static let utc = TimeZone(identifier: "UTC")!
    private static let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0,
                             ms: Int = 0, tz: TimeZone = utc) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let base = cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
        return base.addingTimeInterval(Double(ms) / 1000)
    }

    @Test
    func testTimestampFormats() {
        let d = Self.date(2026, 9, 28, 13, 5, 7, ms: 123)
        #expect(DKFormat.dateTime(d, timeZone: Self.utc) == "2026-09-28 13:05:07")
        #expect(DKFormat.dateTimeMillis(d, timeZone: Self.utc) == "2026-09-28 13:05:07.123")
        #expect(DKFormat.dateTimeMinutes(d, timeZone: Self.utc) == "2026-09-28 13:05")
        #expect(DKFormat.time(d, timeZone: Self.utc) == "13:05:07")
        #expect(DKFormat.timeMillis(d, timeZone: Self.utc) == "13:05:07.123")
        #expect(DKFormat.monthDayTime(d, timeZone: Self.utc) == "09/28 13:05:07")
    }

    @Test
    func testTimestampPaddingAnd24Hour() {
        let midnight = Self.date(2026, 1, 2, 0, 0, 0)
        #expect(DKFormat.dateTime(midnight, timeZone: Self.utc) == "2026-01-02 00:00:00")
        #expect(DKFormat.monthDayTime(midnight, timeZone: Self.utc) == "01/02 00:00:00")
        let evening = Self.date(2026, 12, 31, 23, 59, 59)
        #expect(DKFormat.time(evening, timeZone: Self.utc) == "23:59:59")
        let early = Self.date(999, 3, 4, 5, 6, 7)
        #expect(DKFormat.dateTime(early, timeZone: Self.utc) == "0999-03-04 05:06:07")
    }

    @Test
    func testMillisecondsPadAndTruncate() {
        #expect(DKFormat.timeMillis(Self.date(2026, 9, 28, 13, 5, 7, ms: 7), timeZone: Self.utc) == "13:05:07.007")
        #expect(DKFormat.timeMillis(Self.date(2026, 9, 28, 13, 5, 7, ms: 50), timeZone: Self.utc) == "13:05:07.050")
        #expect(DKFormat.timeMillis(Self.date(2026, 9, 28, 13, 5, 7, ms: 0), timeZone: Self.utc) == "13:05:07.000")
        #expect(DKFormat.timeMillis(Self.date(2026, 9, 28, 13, 5, 7, ms: 999), timeZone: Self.utc) == "13:05:07.999")
        // .9996 truncates to .999 and the second does not round up, so the two agree.
        let almost = Self.date(2026, 9, 28, 13, 5, 7).addingTimeInterval(0.9996)
        #expect(DKFormat.timeMillis(almost, timeZone: Self.utc) == "13:05:07.999")
        #expect(DKFormat.time(almost, timeZone: Self.utc) == "13:05:07")
        // Before 1970 (a negative interval) the second is still rounded down.
        let pre = Self.date(1960, 6, 1, 12, 0, 0, ms: 250)
        #expect(DKFormat.dateTimeMillis(pre, timeZone: Self.utc) == "1960-06-01 12:00:00.250")
    }

    @Test
    func testTimestampTimeZone() {
        let d = Self.date(2026, 9, 28, 20, 30, 0)
        #expect(DKFormat.dateTime(d, timeZone: Self.shanghai) == "2026-09-29 04:30:00")
        #expect(DKFormat.monthDayTime(d, timeZone: Self.shanghai) == "09/29 04:30:00")
        // The variant without a time zone is the one with TimeZone.current.
        #expect(DKFormat.dateTime(d) == DKFormat.dateTime(d, timeZone: .current))
        #expect(DKFormat.dateTimeMillis(d) == DKFormat.dateTimeMillis(d, timeZone: .current))
        #expect(DKFormat.dateTimeMinutes(d) == DKFormat.dateTimeMinutes(d, timeZone: .current))
        #expect(DKFormat.time(d) == DKFormat.time(d, timeZone: .current))
        #expect(DKFormat.timeMillis(d) == DKFormat.timeMillis(d, timeZone: .current))
        #expect(DKFormat.monthDayTime(d) == DKFormat.monthDayTime(d, timeZone: .current))
    }

    @Test
    func testTimestampExtremesDoNotCrash() {
        #expect(!(DKFormat.dateTime(.distantPast, timeZone: Self.utc).isEmpty))
        #expect(!(DKFormat.dateTimeMillis(.distantFuture, timeZone: Self.utc).isEmpty))
    }

    // MARK: - Locale independence

    /// Locale-independent by construction: the source calls no API that reads a
    /// locale, and the output uses "." for decimals and "," for grouping.
    @Test
    func testNoLocaleDependenceByConstruction() throws {
        let source = try String(contentsOf: Self.sourceURL, encoding: .utf8)
        let code = source
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        for banned in ["Locale", "DateFormatter", "NumberFormatter", "ByteCountFormatter",
                       ".formatted(", "String(format: \"%'", "localizedString", "Calendar.current"] {
            #expect(!(code.contains(banned)), "DKFormat must not depend on the locale: found \(banned)")
        }
        #expect(DKFormat.bytes(1536) == "1.5 KB")
        #expect(DKFormat.percent(0.987, decimals: 1) == "98.7%")
        #expect(DKFormat.count(1_234_567) == "1,234,567")
    }

    @Test
    func testSourceGuardCanReadTheSource() {
        #expect(FileManager.default.fileExists(atPath: Self.sourceURL.path), "DKFormat.swift not found, so the source guard checks nothing: \(Self.sourceURL.path)")
    }

    /// Concurrent calls do not interfere: there is no shared mutable state.
    @Test
    func testConcurrentUseIsSafe() {
        let d = Self.date(2026, 9, 28, 13, 5, 7, ms: 123)
        DispatchQueue.concurrentPerform(iterations: 2000) { i in
            #expect(DKFormat.dateTimeMillis(d, timeZone: Self.utc) == "2026-09-28 13:05:07.123")
            #expect(DKFormat.bytes(Int64(i) * 1024 + 1024 * 1024) == DKFormat.bytes(Int64(i) * 1024 + 1024 * 1024))
            #expect(DKFormat.compact(999_700) == "1.0M")
        }
    }

    private static var sourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Foundation
            .deletingLastPathComponent() // VPhoneDesignKitTests
            .deletingLastPathComponent() // VPhoneKit
            .appendingPathComponent("VPhoneDesignKit/Foundation/DKFormat.swift")
    }
}
