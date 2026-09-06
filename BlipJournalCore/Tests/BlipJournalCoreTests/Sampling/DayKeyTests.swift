import Foundation
import Testing
@testable import OpenBlipCore

@Suite("DayKey")
struct DayKeyTests {
    typealias F = SamplingFixtures

    @Test("formats as yyyy-MM-dd with zero padding")
    func format() {
        #expect(DayKey.string(for: F.date(2026, 3, 8, 14, 30), calendar: F.toronto) == "2026-03-08")
        #expect(DayKey.string(for: F.date(2026, 11, 1), calendar: F.toronto) == "2026-11-01")
    }

    @Test("round-trips through date(from:) to the start of the same day")
    func roundTrip() {
        let noon = F.date(2026, 9, 5, 12, 0)
        let key = DayKey.string(for: noon, calendar: F.toronto)
        let parsed = DayKey.date(from: key, calendar: F.toronto)
        #expect(parsed == F.date(2026, 9, 5))
        #expect(parsed.map { DayKey.string(for: $0, calendar: F.toronto) } == key)
    }

    @Test("23:59 and 00:01 the next day are different keys")
    func midnightBoundary() {
        let before = DayKey.string(for: F.date(2026, 9, 5, 23, 59), calendar: F.toronto)
        let after = DayKey.string(for: F.date(2026, 9, 6, 0, 1), calendar: F.toronto)
        #expect(before == "2026-09-05")
        #expect(after == "2026-09-06")
    }

    @Test("the key follows the calendar's time zone, not UTC")
    func followsCalendarZone() {
        // 23:30 in Toronto on the 5th is 03:30 UTC on the 6th.
        let lateEvening = F.date(2026, 9, 5, 23, 30)
        #expect(DayKey.string(for: lateEvening, calendar: F.toronto) == "2026-09-05")
        #expect(DayKey.string(for: lateEvening, calendar: F.utc) == "2026-09-06")

        #expect(DayKey.date(from: "2026-09-05", calendar: F.toronto) == F.date(2026, 9, 5))
        #expect(DayKey.date(from: "2026-09-05", calendar: F.utc) == F.date(2026, 9, 5, calendar: F.utc))
    }

    @Test("a non-Gregorian calendar still yields a Gregorian key")
    func gregorianRegardlessOfCalendar() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = F.toronto.timeZone
        let date = F.date(2026, 9, 5, 12, 0)
        #expect(DayKey.string(for: date, calendar: buddhist) == "2026-09-05")
        #expect(DayKey.date(from: "2026-09-05", calendar: buddhist) == F.date(2026, 9, 5))
    }

    @Test("malformed keys parse to nil", arguments: [
        "", "2026-9-5", "2026/09/05", "20260905", "2026-09-05T00:00", "abcd-ef-gh",
        "2026-13-01", "2026-00-10", "2026-02-30", "2026-09-05-", "-2026-09-05", "２０２６-09-05",
    ])
    func malformed(key: String) {
        #expect(DayKey.date(from: key, calendar: F.toronto) == nil)
    }

    @Test("days around DST transitions parse to local midnight")
    func dstDays() {
        #expect(DayKey.date(from: "2026-03-08", calendar: F.toronto) == F.date(2026, 3, 8))
        #expect(DayKey.date(from: "2026-11-01", calendar: F.toronto) == F.date(2026, 11, 1))
    }
}
