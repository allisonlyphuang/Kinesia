import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class ReportQueryTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUpWithError() throws {
        container = try TestCoreDataStack.makeInMemoryContainer()
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private var referenceDay: Date {
        utc.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func day(_ offset: Int) -> Date {
        utc.date(byAdding: .day, value: offset, to: referenceDay)!
    }

    private func instant(_ offset: Int, hour: Int = 9) -> Date {
        utc.date(bySettingHour: hour, minute: 0, second: 0, of: day(offset))!
    }

    private var window: ReportWindow {
        ReportWindow(days: 7, endingOn: day(6), calendar: utc)!
    }

    @discardableResult
    private func session(
        dayOffset: Int,
        hour: Int = 9,
        tapping: Bool = true,
        firefly: Bool = false,
        tracing: Bool = false,
        withDose: Bool = false
    ) -> TestSession {
        let startedAt = instant(dayOffset, hour: hour)
        let row = TestSession(context: context)
        row.id = UUID()
        row.startedAt = startedAt.timeIntervalSince1970
        row.completedAt = startedAt.addingTimeInterval(300).timeIntervalSince1970
        row.dayStart = day(dayOffset).timeIntervalSince1970

        if withDose {
            let log = MedicationLog(context: context)
            log.id = UUID()
            log.timestamp = startedAt.addingTimeInterval(-3600).timeIntervalSince1970
            log.dayStart = row.dayStart
            log.wasSkipped = false
            row.medicationContext = log
            row.minutesSinceDose = 60
        }

        if tapping {
            let result = BradykinesiaResult(context: context)
            result.id = UUID()
            result.hand = "right"
            result.timestamp = startedAt.timeIntervalSince1970
            result.dayStart = row.dayStart
            result.numTaps = 100
            result.numCorrectTaps = 90
            result.durationSec = 20
            result.isValid = true
            result.metricsVersion = 1
            result.session = row
        }
        if firefly {
            let result = AkinesiaResult(context: context)
            result.id = UUID()
            result.hand = "right"
            result.timestamp = startedAt.timeIntervalSince1970
            result.reactionTimeMedian = 0.35
            result.numRounds = 12
            result.isValid = true
            result.metricsVersion = 1
            result.session = row
        }
        if tracing {
            let result = DexterityResult(context: context)
            result.id = UUID()
            result.hand = "right"
            result.timestamp = startedAt.timeIntervalSince1970
            result.rmsError = 3.4
            result.numSequences = 3
            result.doneSequences = 3
            result.isValid = true
            result.metricsVersion = 1
            result.session = row
        }
        return row
    }

    // MARK: - Range edges

    func testTheWindowStartIsIncludedAndTheEndIsExcluded() throws {
        session(dayOffset: -1)
        session(dayOffset: 0, hour: 0)
        session(dayOffset: 6, hour: 23)
        session(dayOffset: 7, hour: 0)
        try context.save()

        let sessions = try ReportQuery.sessions(from: window.start, to: window.end, in: context)
        XCTAssertEqual(sessions.count, 2)
    }

    func testSessionsComeBackOldestFirst() throws {
        session(dayOffset: 4)
        session(dayOffset: 1)
        session(dayOffset: 3)
        try context.save()

        let sessions = try ReportQuery.sessions(from: window.start, to: window.end, in: context)
        XCTAssertEqual(sessions.map(\.startedAt), sessions.map(\.startedAt).sorted())
    }

    func testAnEmptyWindowReturnsNoSessions() throws {
        session(dayOffset: 30)
        try context.save()

        XCTAssertTrue(try ReportQuery.sessions(from: window.start, to: window.end, in: context).isEmpty)
    }

    // MARK: - Partial sessions

    func testASessionWithOnlySomeTasksMapsThoseTasks() throws {
        session(dayOffset: 0, tapping: true, firefly: true, tracing: false)
        try context.save()

        let snapshot = try XCTUnwrap(
            try ReportQuery.sessions(from: window.start, to: window.end, in: context).first
        )
        XCTAssertEqual(snapshot.tapping.count, 1)
        XCTAssertNotNil(snapshot.firefly)
        XCTAssertNil(snapshot.tracing)
    }

    func testASessionWithAllThreeTasksMapsAllThree() throws {
        session(dayOffset: 0, tapping: true, firefly: true, tracing: true)
        try context.save()

        let snapshot = try XCTUnwrap(
            try ReportQuery.sessions(from: window.start, to: window.end, in: context).first
        )
        XCTAssertEqual(snapshot.tapping.count, 1)
        XCTAssertNotNil(snapshot.firefly)
        XCTAssertNotNil(snapshot.tracing)
    }

    func testASessionWithNoResultsStillComesBack() throws {
        session(dayOffset: 0, tapping: false)
        try context.save()

        let sessions = try ReportQuery.sessions(from: window.start, to: window.end, in: context)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions[0].tapping.isEmpty)
    }

    // MARK: - Dose context

    func testASessionWithoutADoseHasNoMinutesSinceDose() throws {
        session(dayOffset: 0, withDose: false)
        try context.save()

        let snapshot = try XCTUnwrap(
            try ReportQuery.sessions(from: window.start, to: window.end, in: context).first
        )
        XCTAssertNil(snapshot.minutesSinceDose)
    }

    func testASessionWithADoseCarriesTheMinutes() throws {
        session(dayOffset: 0, withDose: true)
        try context.save()

        let snapshot = try XCTUnwrap(
            try ReportQuery.sessions(from: window.start, to: window.end, in: context).first
        )
        XCTAssertEqual(try XCTUnwrap(snapshot.minutesSinceDose), 60, accuracy: 1e-9)
    }

    // MARK: - Doses

    func testDosesComeBackForTheWindowOnly() throws {
        let schedule = try MedicationStore.replaceSchedule(
            with: [MedicationScheduleSlot(hour: 8, minute: 0)],
            in: context
        )[0]
        for offset in [-1, 0, 3, 7] {
            _ = try? MedicationStore.logDose(
                schedule: schedule,
                takenAt: instant(offset, hour: 8),
                in: context,
                calendar: utc
            )
        }

        let doses = try ReportQuery.doses(in: window, in: context)
        XCTAssertEqual(doses.count, 2)
    }

    func testDosesComeBackOldestFirst() throws {
        let schedules = try MedicationStore.replaceSchedule(
            with: [
                MedicationScheduleSlot(hour: 8, minute: 0),
                MedicationScheduleSlot(hour: 18, minute: 0)
            ],
            in: context
        )
        _ = try MedicationStore.logDose(schedule: schedules[1], takenAt: instant(1, hour: 18), in: context, calendar: utc)
        _ = try MedicationStore.logDose(schedule: schedules[0], takenAt: instant(1, hour: 8), in: context, calendar: utc)

        let doses = try ReportQuery.doses(in: window, in: context)
        XCTAssertEqual(doses.map(\.takenAt), doses.map(\.takenAt).sorted())
    }

    func testASkippedDoseIsStillReturnedSoTheChartCanDrawIt() throws {
        let schedule = try MedicationStore.replaceSchedule(
            with: [MedicationScheduleSlot(hour: 8, minute: 0)],
            in: context
        )[0]
        _ = try MedicationStore.logSkipped(schedule: schedule, onDayContaining: day(2), in: context, calendar: utc)

        let doses = try ReportQuery.doses(in: window, in: context)
        XCTAssertEqual(doses.count, 1)
        XCTAssertTrue(doses[0].wasSkipped)
    }

    // MARK: - Questionnaires

    // The PDQ-8 chart asks about months, so a 7 day window would hold no answers.
    func testQuestionnairesAreNotLimitedToTheWindow() throws {
        let responses = Dictionary(
            uniqueKeysWithValues: zip(PDQ8Item.allCases, Array(repeating: PDQ8Response.sometimes, count: 8))
        )
        _ = try PDQ8Store.save(responses: responses, completedAt: day(-200), in: context, calendar: utc)
        _ = try PDQ8Store.save(responses: responses, completedAt: day(-100), in: context, calendar: utc)

        let answers = try ReportQuery.questionnaires(in: context)
        XCTAssertEqual(answers.count, 2)
        XCTAssertEqual(answers.map(\.completedAt), answers.map(\.completedAt).sorted())
        XCTAssertEqual(answers[0].rawSum, 16)
    }

    // MARK: - History

    // A baseline needs 19 days with data and the window is 7 days, so load reads the whole
    // history alongside the window.
    func testLoadReturnsTheWholeHistoryAsWellAsTheWindow() throws {
        for offset in -25..<7 {
            session(dayOffset: offset)
        }
        try context.save()

        let data = try ReportQuery.load(window: window, in: context)
        XCTAssertEqual(data.sessions.count, 7)
        XCTAssertEqual(data.history.count, 32)
        XCTAssertEqual(data.window, window)
    }

    func testTheHistoryFeedsABaselineTheWindowCouldNotEstablish() throws {
        for offset in -20..<7 {
            session(dayOffset: offset)
        }
        try context.save()

        let data = try ReportQuery.load(window: window, in: context)
        let values = BaselineRule.dailyValues(
            sessions: data.history,
            hand: .right,
            calendar: utc,
            value: PrimaryMetric.tapRate.value
        )
        XCTAssertNotNil(BaselineRule.state(from: values, hand: .right).baseline)
    }

    // MARK: - End to end

    func testLoadedDataDrivesTheDerivationsWithoutACoreDataContext() throws {
        session(dayOffset: 0, withDose: true)
        session(dayOffset: 2, withDose: true)
        try context.save()

        let data = try ReportQuery.load(window: window, in: context)
        context.reset()

        let rows = DailyAggregation.aggregate(
            sessions: data.sessions,
            doses: data.doses,
            window: data.window,
            metric: .tapRate
        )
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(try XCTUnwrap(rows[0].right), 5, accuracy: 1e-9)
        XCTAssertNil(rows[1].right)

        let bins = DoseBinning.bins(sessions: data.sessions, window: data.window, metric: .tapRate, hand: .right)
        XCTAssertEqual(bins.count, 10)
    }
}
