import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class MedicationDayModelTests: XCTestCase {
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

    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(bySettingHour: hour, minute: minute, second: 0, of: referenceDay)!
    }

    @discardableResult
    private func threeDoseSchedule() throws -> [MedicationSchedule] {
        try MedicationStore.replaceSchedule(
            with: [
                MedicationScheduleSlot(hour: 8, minute: 0),
                MedicationScheduleSlot(hour: 13, minute: 0),
                MedicationScheduleSlot(hour: 18, minute: 0)
            ],
            in: context
        )
    }

    /// `now` is fixed so "taken at" is exact rather than whenever the suite happened to run.
    private func makeModel(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> MedicationDayModel {
        MedicationDayModel(
            context: context,
            day: referenceDay,
            calendar: utc,
            now: { now }
        )
    }

    // MARK: - Loading

    func testWithNoScheduleThereAreNoRows() {
        let model = makeModel()
        model.load()

        XCTAssertFalse(model.hasSchedule)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.nextDose)
        XCTAssertNil(model.loadError)
    }

    func testOneRowPerScheduledDoseInTimeOrderAllPending() throws {
        try threeDoseSchedule()
        let model = makeModel()
        model.load()

        XCTAssertEqual(model.rows.count, 3)
        XCTAssertEqual(model.rows.map(\.scheduledDate), [time(8), time(13), time(18)])
        XCTAssertTrue(model.rows.allSatisfy { $0.state == .pending })
        XCTAssertTrue(model.rows.allSatisfy { !$0.isRecorded })
    }

    // MARK: - Recording

    func testMarkingADoseTakenRecordsTheActualTime() throws {
        try threeDoseSchedule()
        let model = makeModel(now: time(8, 20))
        model.load()

        model.markTaken(model.rows[0])

        XCTAssertEqual(model.rows[0].state, .taken(at: time(8, 20)))
        XCTAssertTrue(model.rows[0].isRecorded)
        XCTAssertEqual(model.rows[1].state, .pending)
        XCTAssertNil(model.actionError)
        XCTAssertEqual(try XCTUnwrap(model.rows[0].log?.delayMinutes), 20, accuracy: 1e-9)
    }

    func testMarkingADoseSkippedIsADifferentStateFromNotRecorded() throws {
        try threeDoseSchedule()
        let model = makeModel()
        model.load()

        model.markSkipped(model.rows[1])

        XCTAssertEqual(model.rows[1].state, .skipped)
        XCTAssertTrue(model.rows[1].isRecorded)
        XCTAssertEqual(model.rows[0].state, .pending)
        XCTAssertFalse(model.rows[0].isRecorded)
    }

    func testUndoReturnsARowToPendingAndRemovesTheLog() throws {
        try threeDoseSchedule()
        let model = makeModel(now: time(8, 5))
        model.load()

        model.markTaken(model.rows[0])
        model.clear(model.rows[0])

        XCTAssertEqual(model.rows[0].state, .pending)
        XCTAssertEqual(try context.count(for: MedicationLog.fetchRequest()), 0)
    }

    func testARowCanBeRecordedAgainAfterUndo() throws {
        try threeDoseSchedule()
        let model = makeModel(now: time(8, 5))
        model.load()

        model.markTaken(model.rows[0])
        model.clear(model.rows[0])
        model.markSkipped(model.rows[0])

        XCTAssertEqual(model.rows[0].state, .skipped)
        XCTAssertNil(model.actionError)
    }

    /// The store refuses the second write; the model surfaces it and the row stays as it was.
    func testRecordingTheSameDoseTwiceSurfacesAnErrorWithoutChangingTheRow() throws {
        try threeDoseSchedule()
        let model = makeModel(now: time(8, 5))
        model.load()

        model.markTaken(model.rows[0])
        model.markSkipped(model.rows[0])

        XCTAssertNotNil(model.actionError)
        XCTAssertEqual(model.rows[0].state, .taken(at: time(8, 5)))
        XCTAssertEqual(try context.count(for: MedicationLog.fetchRequest()), 1)
    }

    func testAnErrorIsClearedByTheNextSuccessfulAction() throws {
        try threeDoseSchedule()
        let model = makeModel(now: time(8, 5))
        model.load()

        model.markTaken(model.rows[0])
        model.markSkipped(model.rows[0])
        XCTAssertNotNil(model.actionError)

        model.markSkipped(model.rows[1])
        XCTAssertNil(model.actionError)
    }

    // MARK: - Next dose

    func testNextDoseIsTheFirstUnrecordedRow() throws {
        try threeDoseSchedule()
        let model = makeModel(now: time(8, 5))
        model.load()

        XCTAssertEqual(model.nextDose?.scheduledDate, time(8))

        model.markTaken(model.rows[0])
        XCTAssertEqual(model.nextDose?.scheduledDate, time(13))

        model.markSkipped(model.rows[1])
        XCTAssertEqual(model.nextDose?.scheduledDate, time(18))
    }

    func testNextDoseIsNilOnceEveryDoseIsRecorded() throws {
        try threeDoseSchedule()
        let model = makeModel(now: time(8, 5))
        model.load()

        for row in model.rows { model.markSkipped(row) }

        XCTAssertNil(model.nextDose)
        XCTAssertTrue(model.rows.allSatisfy(\.isRecorded))
    }

    // MARK: - Unscheduled doses

    func testAnUnscheduledDoseAppearsSeparatelyFromTheScheduledRows() throws {
        try threeDoseSchedule()
        let model = makeModel(now: time(15, 30))
        model.load()

        model.logUnscheduledDose()

        XCTAssertEqual(model.unscheduledDoses.count, 1)
        XCTAssertEqual(model.unscheduledDoses.first?.takenDate, time(15, 30))
        XCTAssertTrue(model.rows.allSatisfy { $0.state == .pending })
    }

    // MARK: - Day switching

    func testShowingAnotherDayLoadsThatDaysRecords() throws {
        try threeDoseSchedule()
        let model = makeModel(now: time(8, 5))
        model.load()
        model.markTaken(model.rows[0])

        let nextDay = utc.date(byAdding: .day, value: 1, to: referenceDay)!
        model.show(day: nextDay)

        XCTAssertTrue(model.rows.allSatisfy { $0.state == .pending })

        model.show(day: referenceDay)
        XCTAssertEqual(model.rows[0].state, .taken(at: time(8, 5)))
    }

    // MARK: - Copy

    // messages must not blame the patient or use internal vocabulary.
    // "failed" is allowed: it describes the save, not the patient.
    func testErrorMessagesAreNonEmptyAndDoNotBlameThePatient() {
        let errors: [Error] = [
            MedicationStoreError.doseAlreadyLogged(dayStart: 0),
            MedicationStoreError.scheduleInactive,
            MedicationStoreError.unresolvableScheduledTime,
            MedicationStoreError.invalidWallClockTimestamp
        ]
        let banned = ["error", "invalid", "you forgot", "wrong"]

        for error in errors {
            let message = MedicationLogView.message(for: error)
            XCTAssertFalse(message.isEmpty)
            for word in banned {
                XCTAssertFalse(
                    message.lowercased().contains(word),
                    "\"\(message)\" contains \"\(word)\""
                )
            }
        }
    }
}
