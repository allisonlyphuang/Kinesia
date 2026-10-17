import Foundation

nonisolated struct ExcludedSession: Equatable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let task: String
    let hand: CurrentHand
    let reason: String
}

nonisolated struct DataQuality: Equatable, Sendable {
    let daysInWindow: Int
    let daysWithSessions: Int
    let daysWithAtLeastOneDoseLogged: Int
    let sessionCount: Int
    let baselineState: BaselineState
    let excludedSessions: [ExcludedSession]
    let metricsVersionsInWindow: [Int]

    var isSparse: Bool { daysWithSessions < 5 }

    // if the rows in this window used 2 different metrics versions
    var definitionChanged: Bool { metricsVersionsInWindow.count > 1 }

    var daysWithoutSessions: Int { daysInWindow - daysWithSessions }
}

nonisolated enum DataQualityReport {

    static let tappingTask = "Tapping"
    static let fireflyTask = "Fireflies"
    static let tracingTask = "Constellation tracing"

    static func compute(
        sessions: [SessionSnapshot],
        doses: [DoseSnapshot],
        window: ReportWindow,
        baselineState: BaselineState
    ) -> DataQuality {
        let inWindow = sessions.filter { window.contains($0.startedAt) }
        let calendar = window.calendar

        let sessionDays = Set(inWindow.map { calendar.startOfDay(for: $0.dayStart) })
        let doseDays = Set(
            doses
                .filter { window.contains($0.dayStart) && !$0.wasSkipped }
                .map { calendar.startOfDay(for: $0.dayStart) }
        )

        return DataQuality(
            daysInWindow: window.dayCount,
            daysWithSessions: sessionDays.count,
            daysWithAtLeastOneDoseLogged: doseDays.count,
            sessionCount: inWindow.count,
            baselineState: baselineState,
            excludedSessions: excluded(in: inWindow),
            metricsVersionsInWindow: versions(in: inWindow)
        )
    }

    static func excluded(in sessions: [SessionSnapshot]) -> [ExcludedSession] {
        var result: [ExcludedSession] = []

        for session in sessions {
            for tapping in session.tapping where !tapping.isValid {
                result.append(
                    ExcludedSession(
                        id: session.id,
                        date: tapping.timestamp,
                        task: tappingTask,
                        hand: tapping.hand,
                        reason: tapping.invalidReason ?? unstatedReason
                    )
                )
            }
            if let firefly = session.firefly, !firefly.isValid {
                result.append(
                    ExcludedSession(
                        id: session.id,
                        date: firefly.timestamp,
                        task: fireflyTask,
                        hand: firefly.hand,
                        reason: firefly.invalidReason ?? unstatedReason
                    )
                )
            }
            if let tracing = session.tracing, !tracing.isValid {
                result.append(
                    ExcludedSession(
                        id: session.id,
                        date: tracing.timestamp,
                        task: tracingTask,
                        hand: tracing.hand,
                        reason: tracing.invalidReason ?? unstatedReason
                    )
                )
            }
        }

        return result.sorted { $0.date < $1.date }
    }

    static func versions(in sessions: [SessionSnapshot]) -> [Int] {
        var versions: Set<Int> = []
        for session in sessions {
            for tapping in session.tapping {
                versions.insert(tapping.metricsVersion)
            }
            if let firefly = session.firefly {
                versions.insert(firefly.metricsVersion)
            }
            if let tracing = session.tracing {
                versions.insert(tracing.metricsVersion)
            }
        }
        return versions.sorted()
    }

    static let unstatedReason = "no reason recorded"
}
