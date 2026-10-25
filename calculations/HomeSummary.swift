import Foundation

// The three tests that make up one daily check-in.
nonisolated enum CheckInTask: String, CaseIterable, Sendable {
    case fireflies
    case constellation
    case plants

    var title: String {
        switch self {
        case .fireflies:     return "Fireflies"
        case .constellation: return "Constellation"
        case .plants:       return "Plants"
        }
    }
}

// What the opening and home screens know about where the patient is.
//
// Every field is derived from stored sessions and the active medication schedule.
// Nothing is invented. When there is no data the field is nil or zero and the
// screen says so rather than showing a placeholder number.
nonisolated struct HomeSummary: Sendable, Equatable {
    let dayNumber: Int?            // days since the first recorded session, 1-based
    let streak: Int                // consecutive days ending today, or yesterday if today is not logged yet
    let doneToday: Set<CheckInTask>
    let nextDose: Date?

    static let empty = HomeSummary(dayNumber: nil, streak: 0, doneToday: [], nextDose: nil)

    var hasHistory: Bool { dayNumber != nil }
    var checkedInToday: Bool { doneToday.count == CheckInTask.allCases.count }
}

nonisolated enum HomeSummaryBuilder {

    static func make(
        sessions: [SessionSnapshot],
        slots: [MedicationScheduleSlot],
        now: Date,
        calendar: Calendar = .current
    ) -> HomeSummary {
        let today = calendar.startOfDay(for: now)
        let days = Set(sessions.map { calendar.startOfDay(for: $0.dayStart) })

        var dayNumber: Int?
        if let first = days.min(),
           let elapsed = calendar.dateComponents([.day], from: first, to: today).day {
            dayNumber = elapsed + 1
        }

        var done: Set<CheckInTask> = []
        for session in sessions where calendar.startOfDay(for: session.dayStart) == today {
            if session.firefly != nil { done.insert(.fireflies) }
            if session.tracing != nil { done.insert(.constellation) }
            if !session.tapping.isEmpty { done.insert(.plants) }
        }

        return HomeSummary(
            dayNumber: dayNumber,
            streak: streak(days: days, today: today, calendar: calendar),
            doneToday: done,
            nextDose: nextDose(slots: slots, now: now, calendar: calendar)
        )
    }

    // Counts back from today when today is already logged, and from yesterday when
    // it is not. A streak is only broken once a whole day has passed unlogged, so
    // opening the app in the morning does not show the streak reset to zero.
    static func streak(days: Set<Date>, today: Date, calendar: Calendar = .current) -> Int {
        guard !days.isEmpty else { return 0 }

        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            cursor = yesterday
        } else {
            return 0
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    // The next scheduled dose after now: later today if there is one, otherwise the
    // first slot tomorrow. nil when no schedule has been set.
    static func nextDose(
        slots: [MedicationScheduleSlot],
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard !slots.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)

        let todays = slots
            .compactMap { calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: today) }
            .sorted()
        if let next = todays.first(where: { $0 > now }) { return next }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        return slots
            .compactMap { calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: tomorrow) }
            .min()
    }
}
