import Foundation

/// Formats and parses the `yyyy-MM-dd` string stored in ``Prompt/day``.
///
/// This is the only place in the codebase that knows the shape of a day key. Storage
/// and the app treat the string as opaque; the planner uses it to ask "does this survey
/// already have prompts for this day?" without redoing time zone arithmetic.
///
/// Keys are always Gregorian so they mean the same thing whatever calendar the device
/// is set to. Only the time zone of the supplied calendar is used: it decides where one
/// day ends and the next begins. Years 1 through 9999 of the current era round-trip;
/// nothing outside that range is expected to reach this code.
public enum DayKey {
    /// `yyyy-MM-dd` for the calendar day containing `date`, in `calendar`'s time zone.
    public static func string(for date: Date, calendar: Calendar) -> String {
        let gregorian = Self.gregorian(in: calendar.timeZone)
        let year = gregorian.component(.year, from: date)
        let month = gregorian.component(.month, from: date)
        let day = gregorian.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Start of the day named by `key` in `calendar`'s time zone, or nil if malformed.
    ///
    /// Malformed means anything but four digits, a hyphen, two digits, a hyphen, two
    /// digits, or a date that does not exist such as `2026-02-30`. Nothing is
    /// normalised: the key must round-trip through ``string(for:calendar:)`` exactly.
    public static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        let gregorian = Self.gregorian(in: calendar.timeZone)
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = gregorian.date(from: components),
              gregorian.component(.year, from: date) == year,
              gregorian.component(.month, from: date) == month,
              gregorian.component(.day, from: date) == day
        else { return nil }
        return gregorian.startOfDay(for: date)
    }

    private static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
