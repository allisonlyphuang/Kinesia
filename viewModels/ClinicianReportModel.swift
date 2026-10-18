import Combine
import CoreData
import Foundation

@MainActor
final class ClinicianReportModel: ObservableObject {

    @Published private(set) var data: ReportData?
    @Published private(set) var quality: DataQuality?
    @Published private(set) var loadError: Error?

    @Published var metric: PrimaryMetric = .tapRate { didSet { rebuild() } }
    @Published var hand: CurrentHand = .right { didSet { rebuild() } }
    @Published private(set) var dayLength: ReportWindowLength = .week
    @Published private(set) var selectedDay: Date?

    // derived values
    @Published private(set) var dailyAggregates: [DailyAggregate] = []
    @Published private(set) var doseBins: [DoseBin] = []
    @Published private(set) var adherence: [AdherencePoint] = []
    @Published private(set) var componentPoints: [TapComponentPoint] = []
    @Published private(set) var accuracyPoints: [TapAccuracyPoint] = []
    @Published private(set) var baselineState: BaselineState = .familiarization(dayNumber: 0, of: BaselineRule.familiarizationDays)

    private let context: NSManagedObjectContext
    private let calendar: Calendar
    private let now: () -> Date

    init(
        context: NSManagedObjectContext,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    var window: ReportWindow? { data?.window }
    var sessions: [SessionSnapshot] { data?.sessions ?? [] }
    var questionnaires: [PDQ8Snapshot] { data?.questionnaires ?? [] }
    var baseline: Baseline? { baselineState.baseline }

    /// days in the window for the day selector on the daily timeline
    var days: [Date] { data?.window.days ?? [] }

    var timelineDay: Date? { selectedDay ?? days.last }

    func load() {
        guard let window = ReportWindow.trailing(dayLength, endingOn: now(), calendar: calendar) else {
            loadError = ReportModelError.invalidWindow
            return
        }
        do {
            data = try ReportQuery.load(window: window, in: context)
            loadError = nil
            rebuild()
        } catch {
            loadError = error
            data = nil
        }
    }

    func show(length: ReportWindowLength) {
        dayLength = length
        selectedDay = nil
        load()
    }

    func show(day: Date) {
        selectedDay = calendar.startOfDay(for: day)
    }

    // MARK: Derivations

    private func rebuild() {
        guard let data else { return }

        dailyAggregates = DailyAggregation.aggregate(
            sessions: data.sessions,
            doses: data.doses,
            window: data.window,
            metric: metric
        )
        doseBins = DoseBinning.bins(
            sessions: data.sessions,
            window: data.window,
            metric: metric,
            hand: hand
        )
        adherence = Adherence.points(doses: data.doses, window: data.window)

        baselineState = BaselineRule.state(
            from: BaselineRule.dailyValues(
                sessions: data.history,
                hand: hand,
                calendar: calendar,
                value: metric.value
            ),
            hand: hand
        )

        let componentBaselines = TapComponents.baselineStates(
            history: data.history,
            hand: hand,
            calendar: calendar
        )
        componentPoints = TapComponents.points(
            sessions: data.sessions,
            window: data.window,
            hand: hand,
            baselines: componentBaselines
        )
        accuracyPoints = TapComponents.accuracy(
            sessions: data.sessions,
            window: data.window,
            hand: hand
        )

        quality = DataQualityReport.compute(
            sessions: data.sessions,
            doses: data.doses,
            window: data.window,
            baselineState: baselineState
        )
    }

    // MARK: Timeline for one day

    func timelinePoints(for day: Date) -> [DailyTimelineChart.Point] {
        sessions
            .filter { calendar.isDate($0.dayStart, inSameDayAs: day) }
            .flatMap { session -> [DailyTimelineChart.Point] in
                CurrentHand.allCases.compactMap { hand in
                    guard let value = metric.value(session, hand: hand) else { return nil }
                    return DailyTimelineChart.Point(
                        id: UUID(),
                        hour: hours(into: session.startedAt),
                        value: value,
                        hand: hand
                    )
                }
            }
    }

    func doseMarkers(for day: Date) -> [DailyTimelineChart.DoseMarker] {
        (data?.doses ?? [])
            .filter { calendar.isDate($0.dayStart, inSameDayAs: day) }
            .compactMap { dose in
                let instant = dose.scheduledAt ?? dose.takenAt
                return DailyTimelineChart.DoseMarker(
                    id: dose.id,
                    hour: hours(into: dose.wasSkipped ? instant : dose.takenAt),
                    wasSkipped: dose.wasSkipped,
                    label: instant.formatted(ReportFormat.timeOnly)
                )
            }
    }

    private func hours(into instant: Date) -> Double {
        let start = calendar.startOfDay(for: instant)
        return instant.timeIntervalSince(start) / 3600
    }
}

nonisolated enum ReportModelError: Error, Equatable {
    case invalidWindow
}
