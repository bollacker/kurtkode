import Foundation

/// Machine dates (`2026-10-17`, `2026-10-17 09:30:00`) in the Gregorian calendar whatever the user's region: with a
/// Buddhist or Japanese calendar, a plain DateFormatter reads and writes other years.
public enum DayFormat {
    public static func formatter(_ format: String = "yyyy-MM-dd", zone: TimeZone = TimeZone(identifier: "UTC")!) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar(zone)
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    public static func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    /// The day that starts at `start` in `zone`, as a half-open range: 23 or 25 hours long when the clocks change.
    public static func day(starting start: Date, zone: TimeZone) -> Range<Date> {
        start..<(calendar(zone).date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
    }
}
