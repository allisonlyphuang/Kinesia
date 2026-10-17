import Foundation


nonisolated struct DailyAggregate: Equatable, Sendable, Identifiable {
    let dayStart: Date
    let right: Double? // daily median of the primary metric, right hand
    let left: Double?
    let sessionCount: Int
    let doseCount: Int

    var id: Date { dayStart }

    func value(for hand: CurrentHand) -> Double? {
        switch hand {
        case .right: return right
        case .left: return left
        }
    }

    var hasSessions: Bool { sessionCount > 0 }
}

nonisolated enum DailyAggregation {

    // one aggregate per day within the window
    static func aggregate(
        sessions: [SessionSnapshot],
        doses: [DoseSnapshot],
        window: ReportWindow,
        metric: PrimaryMetric
    ) -> [DailyAggregate] {
        let sessionsByDay = group(sessions, window: window)
        let dosesByDay = Dictionary(grouping: doses) { dose in
            window.calendar.startOfDay(for: dose.dayStart)
        }

        return window.days.map { day in
            let daySessions = sessionsByDay[day] ?? []
            return DailyAggregate(
                dayStart: day,
                right: median(daySessions.compactMap { metric.value($0, hand: .right) }),
                left: median(daySessions.compactMap { metric.value($0, hand: .left) }),
                sessionCount: daySessions.count,
                doseCount: (dosesByDay[day] ?? []).filter { !$0.wasSkipped }.count
            )
        }
    }


    static func medians(
        sessions: [SessionSnapshot],
        window: ReportWindow,
        hand: CurrentHand,
        value: (SessionSnapshot, CurrentHand) -> Double?
    ) -> [Date: Double] {
        let sessionsByDay = group(sessions, window: window)
        var result: [Date: Double] = [:]
        for (day, daySessions) in sessionsByDay {
            if let median = median(daySessions.compactMap { value($0, hand) }) {
                result[day] = median
            }
        }
        return result
    }

    // groups by the window's calendar instead of dayStart to avoid timezone errors
    private static func group(
        _ sessions: [SessionSnapshot],
        window: ReportWindow
    ) -> [Date: [SessionSnapshot]] {
        Dictionary(grouping: sessions.filter { window.contains($0.startedAt) }) { session in
            window.calendar.startOfDay(for: session.dayStart)
        }
    }

    static func median(_ values: [Double]) -> Double? {
        let usable = values.filter(\.isFinite)
        guard !usable.isEmpty else { return nil }

        let sorted = usable.sorted()
        let count = sorted.count
        if count.isMultiple(of: 2) {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        }
        return sorted[count / 2]
    }
}
