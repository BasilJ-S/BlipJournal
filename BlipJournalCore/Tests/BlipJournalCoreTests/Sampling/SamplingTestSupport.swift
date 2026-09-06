import Foundation
@testable import OpenBlipCore

/// Fixed calendar and date builders shared by the sampling tests.
enum SamplingFixtures {
    static let toronto: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// A local Toronto date from components.
    static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        calendar: Calendar = toronto
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    /// Minutes after local midnight of the day containing `date`, in `calendar`.
    static func minuteOfDay(_ date: Date, calendar: Calendar = toronto) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func survey(
        id: String, sampling: SamplingConfig = .default, isArchived: Bool = false
    ) -> Survey {
        Survey(id: id, name: id, createdAt: date(2026, 1, 1), isArchived: isArchived, sampling: sampling)
    }

    static func prompt(
        id: String = Identifier.make(),
        survey: String,
        at scheduledAt: Date,
        expiryMinutes: Int = 20,
        status: PromptStatus = .pending,
        calendar: Calendar = toronto
    ) -> Prompt {
        Prompt(
            id: id,
            surveyId: survey,
            day: DayKey.string(for: scheduledAt, calendar: calendar),
            scheduledAt: scheduledAt,
            expiresAt: scheduledAt.addingTimeInterval(TimeInterval(expiryMinutes * 60)),
            status: status
        )
    }
}
