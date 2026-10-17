import Foundation

nonisolated enum DoseBinKind: Equatable, Hashable, Sendable {
    // session has no medication context / no dose was taken on that day before this session
    case beforeFirstDose

    case sinceDose(startMinutes: Int)
    case fourHoursOrMore

    // position on the x axis
    var order: Int {
        switch self {
        case .beforeFirstDose: return 0
        case .sinceDose(let startMinutes): return startMinutes / DoseBinning.binWidthMinutes + 1
        case .fourHoursOrMore: return DoseBinning.halfHourBinCount + 1
        }
    }

    var label: String {
        switch self {
        case .beforeFirstDose:
            return "Before 1st dose"
        case .sinceDose(let startMinutes):
            return "\(Self.clock(startMinutes))–\(Self.clock(startMinutes + DoseBinning.binWidthMinutes))"
        case .fourHoursOrMore:
            return "4h+"
        }
    }

    // hour:minutes, axis is 0:00–0:30 up to 3:30–4:00.
    private static func clock(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

nonisolated struct DoseBinPoint: Equatable, Sendable, Identifiable {
    let sessionId: UUID
    let startedAt: Date
    let minutesSinceDose: Double? // nil in beforeFirstDose
    let value: Double

    var id: UUID { sessionId }
}

nonisolated struct DoseBin: Equatable, Sendable, Identifiable {
    let kind: DoseBinKind
    let points: [DoseBinPoint]
    let stats: SummaryStats?
    let median: Double?

    var id: Int { kind.order }
    var isEmpty: Bool { points.isEmpty }
    var sessionCount: Int { points.count }

    var p25: Double? { stats?.p25 }
    var p75: Double? { stats?.p75 }
    var hasWhisker: Bool { stats != nil }
}

nonisolated enum DoseBinning {

    static let binWidthMinutes = 30
    static let halfHourBinCount = 8
    static var longBinThresholdMinutes: Int { binWidthMinutes * halfHourBinCount }

    // bins in x-axis order, including those with no sessions
    static var orderedKinds: [DoseBinKind] {
        [.beforeFirstDose]
            + (0..<halfHourBinCount).map { .sinceDose(startMinutes: $0 * binWidthMinutes) }
            + [.fourHoursOrMore]
    }

    static func bins(
        sessions: [SessionSnapshot],
        window: ReportWindow,
        metric: PrimaryMetric,
        hand: CurrentHand
    ) -> [DoseBin] {
        var pointsByKind: [DoseBinKind: [DoseBinPoint]] = [:]

        for session in sessions where window.contains(session.startedAt) {
            guard let value = metric.value(session, hand: hand),
                  let kind = kind(forMinutesSinceDose: session.minutesSinceDose) else {
                continue
            }
            pointsByKind[kind, default: []].append(
                DoseBinPoint(
                    sessionId: session.id,
                    startedAt: session.startedAt,
                    minutesSinceDose: session.minutesSinceDose,
                    value: value
                )
            )
        }

        return orderedKinds.map { kind in
            let points = (pointsByKind[kind] ?? []).sorted { $0.startedAt < $1.startedAt }
            let values = points.map(\.value)
            return DoseBin(
                kind: kind,
                points: points,
                stats: SummaryStats.compute(values),
                median: DailyAggregation.median(values)
            )
        }
    }

    // nil if the session cannot be categorized; minutesSinceDose was negative or not finite
    static func kind(forMinutesSinceDose minutes: Double?) -> DoseBinKind? {
        guard let minutes else { return .beforeFirstDose }
        guard minutes.isFinite, minutes >= 0 else { return nil }

        if minutes >= Double(longBinThresholdMinutes) {
            return .fourHoursOrMore
        }

        let step = Int(minutes) / binWidthMinutes
        return .sinceDose(startMinutes: step * binWidthMinutes)
    }
}
