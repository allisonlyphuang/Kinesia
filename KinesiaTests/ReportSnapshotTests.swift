import CoreData
import XCTest
@testable import Kinesia

// The boundary between Core Data and the derivations. Two rules live here and nowhere else:
// placeholder zeros become nil, and minutesSinceDose comes from the relationship, not the number.
@MainActor
final class ReportSnapshotTests: XCTestCase {
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

    private var referenceDate: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    // MARK: - Row builders

    @discardableResult
    private func tappingRow(
        hand: String = "right",
        isValid: Bool = true,
        numTaps: Int32 = 100,
        durationSec: Double = 20,
        tapInterMedian: Double = 0.2,
        cvTapInter: Double = 11,
        tapInterSlope: Double = 0.001,
        in session: TestSession? = nil
    ) -> BradykinesiaResult {
        let row = BradykinesiaResult(context: context)
        row.id = UUID()
        row.hand = hand
        row.timestamp = referenceDate.timeIntervalSince1970
        row.dayStart = utc.startOfDay(for: referenceDate).timeIntervalSince1970
        row.numTaps = numTaps
        row.numCorrectTaps = 90
        row.durationSec = durationSec
        row.tapInterMedian = tapInterMedian
        row.cvTapInter = cvTapInter
        row.tapInterSlope = tapInterSlope
        row.isValid = isValid
        row.invalidReason = isValid ? nil : "tap interval statistics unavailable"
        row.metricsVersion = 1
        row.session = session
        return row
    }

    @discardableResult
    private func fireflyRow(isValid: Bool = true, in session: TestSession? = nil) -> AkinesiaResult {
        let row = AkinesiaResult(context: context)
        row.id = UUID()
        row.hand = "right"
        row.timestamp = referenceDate.timeIntervalSince1970
        row.reactionTimeMedian = 0.35
        row.reactionTimeP90 = 0.6
        row.movementTimeMedian = 0.24
        row.numRounds = 12
        row.numValidRounds = 10
        row.numLapses = 1
        row.numMissed = 1
        row.isValid = isValid
        row.invalidReason = isValid ? nil : "reaction time statistics unavailable"
        row.metricsVersion = 1
        row.session = session
        return row
    }

    @discardableResult
    private func tracingRow(isValid: Bool = true, in session: TestSession? = nil) -> DexterityResult {
        let row = DexterityResult(context: context)
        row.id = UUID()
        row.hand = "right"
        row.timestamp = referenceDate.timeIntervalSince1970
        row.rmsError = 3.4
        row.swipeSpeedMedian = 31.2
        row.fingerLifts = 1
        row.numSequences = 3
        row.doneSequences = 3
        row.isValid = isValid
        row.invalidReason = isValid ? nil : "required metrics are unavailable"
        row.metricsVersion = 1
        row.session = session
        return row
    }

    private func sessionRow(minutesSinceDose: Double = 0, withDose: Bool = false) -> TestSession {
        let session = TestSession(context: context)
        session.id = UUID()
        session.startedAt = referenceDate.timeIntervalSince1970
        session.completedAt = referenceDate.addingTimeInterval(300).timeIntervalSince1970
        session.dayStart = utc.startOfDay(for: referenceDate).timeIntervalSince1970
        session.minutesSinceDose = minutesSinceDose

        if withDose {
            let log = MedicationLog(context: context)
            log.id = UUID()
            log.timestamp = referenceDate.addingTimeInterval(-minutesSinceDose * 60).timeIntervalSince1970
            log.dayStart = session.dayStart
            log.wasSkipped = false
            session.medicationContext = log
        }
        return session
    }

    // MARK: - Placeholder zeros

    // The stores write 0 into required columns when a metric was unavailable and set
    // isValid = false. A chart that plots one draws a dip that never happened.
    func testAnInvalidTappingRowLosesItsStatistics() throws {
        let snapshot = try XCTUnwrap(TappingSnapshot(tappingRow(isValid: false)))

        XCTAssertFalse(snapshot.isValid)
        XCTAssertNil(snapshot.tapInterMedian)
        XCTAssertNil(snapshot.cvTapInter)
        XCTAssertNil(snapshot.tapInterSlope)
        XCTAssertEqual(snapshot.invalidReason, "tap interval statistics unavailable")
    }

    func testAValidTappingRowKeepsItsStatistics() throws {
        let snapshot = try XCTUnwrap(TappingSnapshot(tappingRow()))

        XCTAssertEqual(try XCTUnwrap(snapshot.tapInterMedian), 0.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(snapshot.cvTapInter), 11, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(snapshot.tapInterSlope), 0.001, accuracy: 1e-9)
        XCTAssertNil(snapshot.invalidReason)
    }

    // BradykinesiaStore validates the counts and the duration separately from the statistics,
    // so tap rate is a real measurement even when isValid is false. Gating it would discard
    // sessions because an unrelated drift CV was missing.
    func testTapRateSurvivesAnInvalidRow() throws {
        let snapshot = try XCTUnwrap(TappingSnapshot(tappingRow(isValid: false, numTaps: 100, durationSec: 20)))

        XCTAssertEqual(snapshot.numTaps, 100)
        XCTAssertEqual(snapshot.durationSec, 20, accuracy: 1e-9)
        XCTAssertEqual(snapshot.numCorrectTaps, 90)
    }

    func testANonFiniteStoredValueBecomesNilEvenOnAValidRow() throws {
        let snapshot = try XCTUnwrap(TappingSnapshot(tappingRow(cvTapInter: .infinity)))
        XCTAssertNil(snapshot.cvTapInter)
        XCTAssertNotNil(snapshot.tapInterMedian)
    }

    func testAnInvalidFireflyRowLosesItsStatistics() throws {
        let snapshot = try XCTUnwrap(FireflySnapshot(fireflyRow(isValid: false)))

        XCTAssertNil(snapshot.reactionTimeMedian)
        XCTAssertNil(snapshot.reactionTimeP90)
        XCTAssertNil(snapshot.movementTimeMedian)
        XCTAssertEqual(snapshot.numRounds, 12) // counts are not gated
        XCTAssertEqual(snapshot.numMissed, 1)
    }

    func testAnInvalidTracingRowLosesItsStatistics() throws {
        let snapshot = try XCTUnwrap(TracingSnapshot(tracingRow(isValid: false)))

        XCTAssertNil(snapshot.rmsError)
        XCTAssertNil(snapshot.swipeSpeedMedian)
        XCTAssertEqual(snapshot.doneSequences, 3)
        XCTAssertEqual(snapshot.fingerLifts, 1)
    }

    // MARK: - Dose context

    // The only correct test is medicationContext != nil.
    func testNoMedicationContextGivesNoMinutesSinceDose() throws {
        let snapshot = try XCTUnwrap(SessionSnapshot(sessionRow(minutesSinceDose: 0, withDose: false)))
        XCTAssertNil(snapshot.minutesSinceDose)
    }

    // The trap: a session tested at the exact moment of a dose stores 0 and must not be
    // mistaken for one with no dose.
    func testADoseAtTheExactMomentOfTheSessionGivesZeroNotNil() throws {
        let snapshot = try XCTUnwrap(SessionSnapshot(sessionRow(minutesSinceDose: 0, withDose: true)))
        XCTAssertEqual(try XCTUnwrap(snapshot.minutesSinceDose), 0, accuracy: 1e-9)
    }

    func testAMedicationContextGivesTheStoredMinutes() throws {
        let snapshot = try XCTUnwrap(SessionSnapshot(sessionRow(minutesSinceDose: 72, withDose: true)))
        XCTAssertEqual(try XCTUnwrap(snapshot.minutesSinceDose), 72, accuracy: 1e-9)
    }

    func testTheBeforeFirstDoseSessionReachesItsOwnBin() throws {
        let snapshot = try XCTUnwrap(SessionSnapshot(sessionRow(withDose: false)))
        XCTAssertEqual(DoseBinning.kind(forMinutesSinceDose: snapshot.minutesSinceDose), .beforeFirstDose)
    }

    // MARK: - Session assembly

    func testASessionCarriesEveryTaskItHas() throws {
        let session = sessionRow(minutesSinceDose: 30, withDose: true)
        tappingRow(hand: "right", in: session)
        tappingRow(hand: "left", in: session)
        fireflyRow(in: session)
        tracingRow(in: session)

        let snapshot = try XCTUnwrap(SessionSnapshot(session))
        XCTAssertEqual(snapshot.tapping.count, 2)
        XCTAssertNotNil(snapshot.firefly)
        XCTAssertNotNil(snapshot.tracing)
        XCTAssertEqual(snapshot.id, session.id)
    }

    func testASessionWithOnlyTappingHasNoOtherTasks() throws {
        let session = sessionRow()
        tappingRow(in: session)

        let snapshot = try XCTUnwrap(SessionSnapshot(session))
        XCTAssertEqual(snapshot.tapping.count, 1)
        XCTAssertNil(snapshot.firefly)
        XCTAssertNil(snapshot.tracing)
    }

    // The relationship is a set, so order has to be recovered from the timestamps.
    func testBothHandsComeBackInTheOrderTheyWereRecorded() throws {
        let session = sessionRow()
        let right = tappingRow(hand: "right", in: session)
        let left = tappingRow(hand: "left", in: session)
        right.timestamp = referenceDate.timeIntervalSince1970
        left.timestamp = referenceDate.addingTimeInterval(60).timeIntervalSince1970

        let snapshot = try XCTUnwrap(SessionSnapshot(session))
        XCTAssertEqual(snapshot.tapping.map(\.hand), [.right, .left])
    }

    func testASessionWithNoResultsStillMakesASnapshot() throws {
        let snapshot = try XCTUnwrap(SessionSnapshot(sessionRow()))
        XCTAssertTrue(snapshot.tapping.isEmpty)
        XCTAssertNil(snapshot.firefly)
        XCTAssertNil(snapshot.tracing)
    }

    // MARK: - Unmappable rows

    func testARowWithAnUnrecognisedHandIsRefused() {
        XCTAssertNil(TappingSnapshot(tappingRow(hand: "sideways")))
    }

    func testARowWithAnUnrecognisedHandIsDroppedFromItsSession() throws {
        let session = sessionRow()
        tappingRow(hand: "right", in: session)
        tappingRow(hand: "sideways", in: session)

        let snapshot = try XCTUnwrap(SessionSnapshot(session))
        XCTAssertEqual(snapshot.tapping.count, 1)
        XCTAssertEqual(snapshot.tapping.first?.hand, .right)
    }

    // MARK: - Dose snapshots

    func testAnUnscheduledDoseHasNoDelay() throws {
        let log = MedicationLog(context: context)
        log.id = UUID()
        log.timestamp = referenceDate.timeIntervalSince1970
        log.dayStart = utc.startOfDay(for: referenceDate).timeIntervalSince1970
        log.scheduledTime = 0

        let snapshot = try XCTUnwrap(DoseSnapshot(log))
        XCTAssertNil(snapshot.scheduledAt)
        XCTAssertNil(snapshot.delayMinutes)
        XCTAssertFalse(snapshot.isScheduled)
    }

    func testAScheduledDoseCarriesItsSlot() throws {
        let schedule = try MedicationStore.replaceSchedule(
            with: [MedicationScheduleSlot(label: "Morning", hour: 8, minute: 30)],
            in: context
        )[0]
        let scheduledAt = try XCTUnwrap(
            MedicationStore.scheduledDate(for: schedule, onDayContaining: referenceDate, calendar: utc)
        )
        let log = try MedicationStore.logDose(
            schedule: schedule,
            takenAt: scheduledAt.addingTimeInterval(15 * 60),
            in: context,
            calendar: utc
        )

        let snapshot = try XCTUnwrap(DoseSnapshot(log))
        XCTAssertEqual(snapshot.slotMinutesIntoDay, 8 * 60 + 30)
        XCTAssertEqual(snapshot.slotLabel, "Morning")
        XCTAssertEqual(try XCTUnwrap(snapshot.delayMinutes), 15, accuracy: 1e-9)
    }

    // MARK: - The boundary holds

    // Snapshots are passed to pure functions and, later, rendered off the main actor by
    // ImageRenderer. Nothing in them may be a managed object.
    func testSnapshotsSurviveTheirContextBeingReset() throws {
        let session = sessionRow(minutesSinceDose: 45, withDose: true)
        tappingRow(in: session)
        fireflyRow(in: session)
        try context.save()

        let snapshot = try XCTUnwrap(SessionSnapshot(session))
        context.reset()

        XCTAssertEqual(snapshot.tapping.count, 1)
        XCTAssertEqual(try XCTUnwrap(snapshot.minutesSinceDose), 45, accuracy: 1e-9)
        XCTAssertNotNil(snapshot.firefly)
    }
}
