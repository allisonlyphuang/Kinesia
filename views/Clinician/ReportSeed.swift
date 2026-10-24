#if DEBUG
import CoreData
import Foundation

// Fills the store with a plausible history so the report can be looked at on a device.
// Debug builds only. Nothing here runs in a release build or in the test target.
enum ReportSeed {

    /// Clears every report-facing entity and writes `days` of history ending today.
    static func populate(days: Int = 45, in context: NSManagedObjectContext) throws {
        try clear(in: context)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let schedules = try MedicationStore.replaceSchedule(
            with: [
                MedicationScheduleSlot(dosageMg: 100, hour: 8, minute: 0),
                MedicationScheduleSlot(dosageMg: 100, hour: 13, minute: 0),
                MedicationScheduleSlot(dosageMg: 100, hour: 18, minute: 0)
            ],
            in: context
        )

        for offset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }

            // Two days in every nine have no check-in, so the gaps the charts have to show
            // are actually present.
            let isGap = abs(offset) % 9 == 3 || abs(offset) % 9 == 4
            try seedDoses(schedules: schedules, day: day, offset: offset, in: context, calendar: calendar)
            guard !isGap else { continue }

            try seedSessions(day: day, offset: offset, in: context, calendar: calendar)
        }

        try seedQuestionnaires(endingOn: today, in: context, calendar: calendar)
        try context.save()
    }

    // MARK: Sessions

    private static func seedSessions(
        day: Date,
        offset: Int,
        in context: NSManagedObjectContext,
        calendar: Calendar
    ) throws {
        // Three check-ins a day: before the first dose, after it, and late afternoon.
        for (index, hour) in [7, 10, 15].enumerated() {
            guard let startedAt = calendar.date(bySettingHour: hour, minute: 12, second: 0, of: day) else { continue }

            let session = TestSession(context: context)
            session.id = UUID()
            session.startedAt = startedAt.timeIntervalSince1970
            session.completedAt = startedAt.addingTimeInterval(420).timeIntervalSince1970
            session.dayStart = day.timeIntervalSince1970

            if hour > 8 {
                session.medicationContext = try MedicationStore.mostRecentDoseForSeed(
                    dayStart: day.timeIntervalSince1970,
                    instant: startedAt.timeIntervalSince1970,
                    in: context
                )
                if let dose = session.medicationContext {
                    session.minutesSinceDose = (startedAt.timeIntervalSince1970 - dose.timestamp) / 60
                }
            }

            // A slow decline over the window, plus a dip before each dose.
            let decline = Double(offset) * 0.012
            let beforeDose = hour == 7 ? -1.1 : 0
            let wobble = Double((abs(offset) * 7 + index) % 5) * 0.08

            for hand in CurrentHand.allCases {
                let handPenalty: Double = hand == .left ? -0.9 : 0
                let rate = 5.1 + decline + beforeDose + wobble + handPenalty
                let invalid = abs(offset) % 17 == 5 && hand == .left

                let tapping = BradykinesiaResult(context: context)
                tapping.id = UUID()
                tapping.hand = hand.rawValue
                tapping.timestamp = startedAt.addingTimeInterval(hand == .right ? 0 : 60).timeIntervalSince1970
                tapping.dayStart = session.dayStart
                tapping.durationSec = 20
                tapping.numTaps = Int32(max(1, (rate * 20).rounded()))
                tapping.numCorrectTaps = Int32(Double(tapping.numTaps) * 0.93)
                tapping.tapInterMedian = 1 / max(rate, 0.5)
                tapping.cvTapInter = invalid ? 0 : 9 + wobble * 12 - decline * 20
                tapping.tapInterSlope = invalid ? 0 : 0.0006 - decline * 0.02
                tapping.isValid = !invalid
                tapping.invalidReason = invalid ? "tap interval statistics unavailable" : nil
                tapping.metricsVersion = 1
                tapping.session = session
            }

            if index == 1 {
                let firefly = AkinesiaResult(context: context)
                firefly.id = UUID()
                firefly.hand = CurrentHand.right.rawValue
                firefly.timestamp = startedAt.timeIntervalSince1970
                firefly.dayStart = session.dayStart
                firefly.reactionTimeMedian = 0.34 - decline * 0.4
                firefly.reactionTimeP90 = 0.58 - decline * 0.5
                firefly.movementTimeMedian = 0.24
                firefly.numRounds = 12
                firefly.numValidRounds = 11
                firefly.numLapses = 1
                firefly.numMissed = 0
                firefly.isValid = true
                firefly.metricsVersion = 1
                firefly.session = session

                let tracing = DexterityResult(context: context)
                tracing.id = UUID()
                tracing.hand = CurrentHand.right.rawValue
                tracing.timestamp = startedAt.timeIntervalSince1970
                tracing.dayStart = session.dayStart
                tracing.rmsError = 3.2 - decline * 3
                tracing.swipeSpeedMedian = 31 + decline * 10
                tracing.fingerLifts = Int32(abs(offset) % 3)
                tracing.numSequences = 3
                tracing.doneSequences = 3
                tracing.isValid = true
                tracing.metricsVersion = 1
                tracing.session = session
            }
        }
    }

    // MARK: Doses

    private static func seedDoses(
        schedules: [MedicationSchedule],
        day: Date,
        offset: Int,
        in context: NSManagedObjectContext,
        calendar: Calendar
    ) throws {
        for (index, schedule) in schedules.enumerated() {
            guard let scheduled = MedicationStore.scheduledDate(for: schedule, onDayContaining: day, calendar: calendar) else {
                continue
            }

            // One dose in eleven is skipped; the rest run from 20 minutes early to an hour late.
            if (abs(offset) * 3 + index) % 11 == 0 {
                _ = try? MedicationStore.logSkipped(schedule: schedule, onDayContaining: day, in: context, calendar: calendar)
                continue
            }

            let delay = Double((abs(offset) * 13 + index * 7) % 80) - 20
            _ = try? MedicationStore.logDose(
                schedule: schedule,
                takenAt: scheduled.addingTimeInterval(delay * 60),
                in: context,
                calendar: calendar
            )
        }
    }

    // MARK: Questionnaires

    private static func seedQuestionnaires(
        endingOn today: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar
    ) throws {
        for monthsBack in stride(from: 7, through: 0, by: -1) {
            guard let when = calendar.date(byAdding: .month, value: -monthsBack, to: today) else { continue }
            let severity = 1 + (7 - monthsBack) / 3
            let responses = Dictionary(
                uniqueKeysWithValues: PDQ8Item.allCases.enumerated().map { index, item in
                    (item, PDQ8Response(rawValue: min(4, severity + index % 2)) ?? .never)
                }
            )
            _ = try? PDQ8Store.save(responses: responses, completedAt: when, in: context, calendar: calendar)
        }
    }

    // MARK: Clearing

    private static func clear(in context: NSManagedObjectContext) throws {
        let names = ["TestSession", "BradykinesiaResult", "AkinesiaResult", "DexterityResult",
                     "RawCapture", "MedicationLog", "MedicationSchedule", "PDQ8Log"]
        for name in names {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
            for object in try context.fetch(request) as? [NSManagedObject] ?? [] {
                context.delete(object)
            }
        }
        try context.save()
    }
}

extension MedicationStore {
    /// `mostRecentDose` lives on BradykinesiaStore; this is the same query under a name the
    /// seeder can call without implying tapping.
    static func mostRecentDoseForSeed(
        dayStart: TimeInterval,
        instant: TimeInterval,
        in context: NSManagedObjectContext
    ) throws -> MedicationLog? {
        try BradykinesiaStore.mostRecentDose(onOrAfter: dayStart, atOrBefore: instant, in: context)
    }
}
#endif
