import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class ClinicianReportModelTests: XCTestCase {
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

    private var referenceDay: Date {
        utc.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func day(_ offset: Int) -> Date {
        utc.date(byAdding: .day, value: offset, to: referenceDay)!
    }

    private func instant(_ offset: Int, hour: Int) -> Date {
        utc.date(bySettingHour: hour, minute: 0, second: 0, of: day(offset))!
    }

    /// `now` is the last day of the default 7-day window.
    private func makeModel() -> ClinicianReportModel {
        ClinicianReportModel(context: context, calendar: utc, now: { self.instant(0, hour: 20) })
    }

    @discardableResult
    private func session(
        dayOffset: Int,
        hour: Int = 9,
        numTaps: Int32 = 100,
        hand: String = "right",
        withDose: Bool = false,
        firefly: Bool = false
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

        let tapping = BradykinesiaResult(context: context)
        tapping.id = UUID()
        tapping.hand = hand
        tapping.timestamp = startedAt.timeIntervalSince1970
        tapping.dayStart = row.dayStart
        tapping.numTaps = numTaps
        tapping.numCorrectTaps = numTaps - 10
        tapping.durationSec = 20
        tapping.cvTapInter = 11
        tapping.tapInterSlope = 0.001
        tapping.isValid = true
        tapping.metricsVersion = 1
        tapping.session = row

        if firefly {
            let result = AkinesiaResult(context: context)
            result.id = UUID()
            result.hand = hand
            result.timestamp = startedAt.timeIntervalSince1970
            result.reactionTimeMedian = 0.35
            result.numRounds = 12
            result.isValid = true
            result.metricsVersion = 1
            result.session = row
        }
        return row
    }

    // MARK: - Loading

    func testLoadingWithNoDataLeavesEmptyDerivationsAndNoError() {
        let model = makeModel()
        model.load()

        XCTAssertNil(model.loadError)
        XCTAssertNotNil(model.window)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(model.dailyAggregates.count, 7)
        XCTAssertEqual(model.doseBins.count, 10)
    }

    func testLoadingBuildsEveryDerivation() throws {
        for offset in -6...0 {
            session(dayOffset: offset, withDose: true)
        }
        try context.save()

        let model = makeModel()
        model.load()

        XCTAssertEqual(model.sessions.count, 7)
        XCTAssertEqual(model.dailyAggregates.count, 7)
        XCTAssertEqual(model.doseBins.count, 10)
        XCTAssertEqual(model.componentPoints.count, 7 * TapComponent.allCases.count)
        XCTAssertEqual(model.accuracyPoints.count, 7)
        XCTAssertNotNil(model.quality)
    }

    func testTheWindowDefaultsToSevenDays() {
        let model = makeModel()
        model.load()
        XCTAssertEqual(model.dayLength, .week)
        XCTAssertEqual(model.days.count, 7)
    }

    func testChangingTheWindowReloads() throws {
        session(dayOffset: -20)
        try context.save()

        let model = makeModel()
        model.load()
        XCTAssertEqual(model.sessions.count, 0)

        model.show(length: .month)
        XCTAssertEqual(model.days.count, 30)
        XCTAssertEqual(model.sessions.count, 1)
    }

    // MARK: - Metric and hand

    func testChangingTheMetricRebuildsTheDerivations() throws {
        session(dayOffset: 0, firefly: true)
        try context.save()

        let model = makeModel()
        model.load()
        XCTAssertEqual(try XCTUnwrap(model.dailyAggregates.last?.right), 5, accuracy: 1e-9)

        model.metric = .reactionTime
        XCTAssertEqual(try XCTUnwrap(model.dailyAggregates.last?.right), 350, accuracy: 1e-9)
    }

    func testChangingTheHandRebuildsTheDerivations() throws {
        session(dayOffset: 0, numTaps: 100, hand: "right")
        session(dayOffset: 0, hour: 11, numTaps: 60, hand: "left")
        try context.save()

        let model = makeModel()
        model.load()
        XCTAssertEqual(model.doseBins.compactMap(\.median).first, 5)

        model.hand = .left
        XCTAssertEqual(model.doseBins.compactMap(\.median).first, 3)
    }

    // MARK: - Baseline

    func testABaselineIsEstablishedFromTheWholeHistoryNotTheWindow() throws {
        for offset in -25...0 {
            session(dayOffset: offset)
        }
        try context.save()

        let model = makeModel()
        model.load()

        XCTAssertEqual(model.days.count, 7)
        XCTAssertNotNil(model.baseline, "a 7 day window cannot hold the 19 days a baseline needs")
    }

    func testAShortHistoryLeavesNoBaseline() throws {
        for offset in -3...0 {
            session(dayOffset: offset)
        }
        try context.save()

        let model = makeModel()
        model.load()
        XCTAssertNil(model.baseline)
        XCTAssertEqual(model.baselineState, .familiarization(dayNumber: 4, of: 5))
    }

    // MARK: - Daily timeline

    func testTimelinePointsAreScopedToTheSelectedDay() throws {
        session(dayOffset: 0, hour: 9)
        session(dayOffset: -1, hour: 9)
        try context.save()

        let model = makeModel()
        model.load()

        XCTAssertEqual(model.timelinePoints(for: day(0)).count, 1)
        XCTAssertEqual(model.timelinePoints(for: day(-1)).count, 1)
        XCTAssertEqual(model.timelinePoints(for: day(-3)).count, 0)
    }

    func testATimelinePointCarriesItsHourOfDay() throws {
        session(dayOffset: 0, hour: 14)
        try context.save()

        let model = makeModel()
        model.load()

        let point = try XCTUnwrap(model.timelinePoints(for: day(0)).first)
        XCTAssertEqual(point.hour, 14, accuracy: 1e-9)
        XCTAssertEqual(point.value, 5, accuracy: 1e-9)
        XCTAssertEqual(point.hand, .right)
    }

    func testBothHandsAppearAsSeparateTimelinePoints() throws {
        session(dayOffset: 0, hour: 9, hand: "right")
        session(dayOffset: 0, hour: 9, numTaps: 60, hand: "left")
        try context.save()

        let model = makeModel()
        model.load()

        XCTAssertEqual(Set(model.timelinePoints(for: day(0)).map(\.hand)), [.right, .left])
    }

    func testTheTimelineDefaultsToTheLastDayInTheWindow() {
        let model = makeModel()
        model.load()
        XCTAssertEqual(model.timelineDay, day(0))
    }

    func testSelectingADayChangesTheTimelineDay() {
        let model = makeModel()
        model.load()
        model.show(day: day(-3))
        XCTAssertEqual(model.timelineDay, day(-3))
    }

    // MARK: - Dose markers

    func testDoseMarkersCarryTheirSkippedState() throws {
        let schedules = try MedicationStore.replaceSchedule(
            with: [
                MedicationScheduleSlot(hour: 8, minute: 0),
                MedicationScheduleSlot(hour: 18, minute: 0)
            ],
            in: context
        )
        _ = try MedicationStore.logDose(schedule: schedules[0], takenAt: instant(0, hour: 8), in: context, calendar: utc)
        _ = try MedicationStore.logSkipped(schedule: schedules[1], onDayContaining: day(0), in: context, calendar: utc)

        let model = makeModel()
        model.load()

        let markers = model.doseMarkers(for: day(0))
        XCTAssertEqual(markers.count, 2)
        XCTAssertEqual(markers.filter(\.wasSkipped).count, 1)
        XCTAssertEqual(try XCTUnwrap(markers.first { !$0.wasSkipped }).hour, 8, accuracy: 1e-9)
    }

    func testDoseMarkersAreScopedToTheirDay() throws {
        let schedule = try MedicationStore.replaceSchedule(
            with: [MedicationScheduleSlot(hour: 8, minute: 0)],
            in: context
        )[0]
        _ = try MedicationStore.logDose(schedule: schedule, takenAt: instant(0, hour: 8), in: context, calendar: utc)

        let model = makeModel()
        model.load()

        XCTAssertEqual(model.doseMarkers(for: day(0)).count, 1)
        XCTAssertEqual(model.doseMarkers(for: day(-2)).count, 0)
    }

    // MARK: - Data quality

    func testDataQualityReflectsTheLoadedWindow() throws {
        for offset in [-6, -5, 0] {
            session(dayOffset: offset)
        }
        try context.save()

        let model = makeModel()
        model.load()

        let quality = try XCTUnwrap(model.quality)
        XCTAssertEqual(quality.daysInWindow, 7)
        XCTAssertEqual(quality.daysWithSessions, 3)
        XCTAssertTrue(quality.isSparse)
    }
}
