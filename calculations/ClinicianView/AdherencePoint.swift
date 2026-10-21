import Foundation

// one recorded dose
// x = dayStart, y = delayMinutes, color = dose slot, shape = skipped?
nonisolated struct AdherencePoint: Equatable, Sendable, Identifiable {
    let id: UUID
    let dayStart: Date
    let scheduledAt: Date
    let takenAt: Date
    let delayMinutes: Double? // nil for a skipped dose
    let wasSkipped: Bool
    // identifies the timeslot of the dose
    let slotMinutesIntoDay: Int
    let slotLabel: String?

    var slotTimeLabel: String {
        String(format: "%02d:%02d", slotMinutesIntoDay / 60, slotMinutesIntoDay % 60)
    }
}

nonisolated enum Adherence {

    // unscheduled doses are excluded
    static func points(doses: [DoseSnapshot], window: ReportWindow) -> [AdherencePoint] {
        doses
            .filter { window.contains($0.dayStart) }
            .compactMap { dose in
                guard let scheduledAt = dose.scheduledAt,
                      let slotMinutes = dose.slotMinutesIntoDay else {
                    return nil
                }
                return AdherencePoint(
                    id: dose.id,
                    dayStart: window.calendar.startOfDay(for: dose.dayStart),
                    scheduledAt: scheduledAt,
                    takenAt: dose.takenAt,
                    delayMinutes: dose.delayMinutes,
                    wasSkipped: dose.wasSkipped,
                    slotMinutesIntoDay: slotMinutes,
                    slotLabel: dose.slotLabel
                )
            }
            .sorted { first, second in
                if first.dayStart != second.dayStart {
                    return first.dayStart < second.dayStart
                }
                return first.slotMinutesIntoDay < second.slotMinutesIntoDay
            }
    }

    // the distinct slots present in time-of-day order for the chart legend
    static func slots(in points: [AdherencePoint]) -> [Int] {
        Array(Set(points.map(\.slotMinutesIntoDay))).sorted()
    }

    // doses taken more than `minutes` from their scheduled time
    // for the data quality section
    static func countOffSchedule(_ points: [AdherencePoint], byMoreThan minutes: Double) -> Int {
        points.filter { point in
            guard let delay = point.delayMinutes else { return false }
            return abs(delay) > minutes
        }
        .count
    }
}
