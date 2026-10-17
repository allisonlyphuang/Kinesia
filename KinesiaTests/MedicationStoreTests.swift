import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class MedicationStoreTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    /// A fixed UTC calendar: day boundaries and scheduled occurrences must be reproducible
    /// wherever the suite runs.
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

    private func time(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = utc.date(byAdding: .day, value: dayOffset, to: referenceDay)!
        return utc.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

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

    private func count<T: NSManagedObject>(_ type: T.Type, _ request: NSFetchRequest<T>) throws -> Int {
        try context.count(for: request)
    }

    // MARK: - Schedule

    func testReplaceScheduleCreatesOneActiveRowPerSlotInTimeOrder() throws {
        let created = try threeDoseSchedule()

        XCTAssertEqual(created.count, 3)
        XCTAssertEqual(created.map { Int($0.hour) }, [8, 13, 18])
        XCTAssertEqual(created.map { Int($0.sortIndex) }, [0, 1, 2])
        XCTAssertTrue(created.allSatisfy(\.isActive))
    }

    func testReplaceScheduleSortsSlotsGivenOutOfOrder() throws {
        let created = try MedicationStore.replaceSchedule(
            with: [
                MedicationScheduleSlot(hour: 18, minute: 0),
                MedicationScheduleSlot(hour: 8, minute: 30)
            ],
            in: context
        )
        XCTAssertEqual(created.map { Int($0.hour) }, [8, 18])
        XCTAssertEqual(created.map { Int($0.sortIndex) }, [0, 1])
    }

    func testReplaceSchedulePersistsLabelAndDosage() throws {
        let created = try MedicationStore.replaceSchedule(
            with: [MedicationScheduleSlot(label: "Morning", dosageMg: 100, hour: 8, minute: 0)],
            in: context
        )
        XCTAssertEqual(created.first?.label, "Morning")
        XCTAssertEqual(created.first?.dosageMg, 100)
    }

    /// Deactivating rather than deleting is the whole point: a patient who moves their 8:00 dose
    /// to 9:00 has not changed when last month's doses were due.
    func testReplaceScheduleDeactivatesTheOldRowsInsteadOfDeletingThem() throws {
        _ = try threeDoseSchedule()
        _ = try MedicationStore.replaceSchedule(
            with: [MedicationScheduleSlot(hour: 9, minute: 0)],
            in: context
        )

        let all = try MedicationStore.allSchedules(in: context)
        let active = try MedicationStore.activeSchedule(in: context)
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.map { Int($0.hour) }, [9])
    }

    func testReplaceScheduleKeepsAnOldLogsLinkToItsDeactivatedSlot() throws {
        let schedules = try threeDoseSchedule()
        let morning = schedules[0]
        let log = try MedicationStore.logDose(
            schedule: morning,
            takenAt: time(8, 5),
            in: context,
            calendar: utc
        )

        _ = try MedicationStore.replaceSchedule(
            with: [MedicationScheduleSlot(hour: 9, minute: 0)],
            in: context
        )

        XCTAssertEqual(log.schedule, morning)
        XCTAssertFalse(try XCTUnwrap(log.schedule).isActive)
        XCTAssertEqual(log.scheduledDate, time(8, 0))
    }

    func testReplaceScheduleRejectsAnInvalidPlanAndWritesNothing() throws {
        XCTAssertThrowsError(
            try MedicationStore.replaceSchedule(
                with: [MedicationScheduleSlot(hour: 8, minute: 0), MedicationScheduleSlot(hour: 8, minute: 0)],
                in: context
            )
        )
        XCTAssertEqual(try count(MedicationSchedule.self, MedicationSchedule.fetchRequest()), 0)
    }

    // MARK: - Logging a taken dose

    func testLogDoseRecordsTheTakenTimeAndTheScheduledTime() throws {
        let schedule = try threeDoseSchedule()[0]
        let log = try MedicationStore.logDose(
            schedule: schedule,
            takenAt: time(8, 20),
            in: context,
            calendar: utc
        )

        XCTAssertEqual(log.takenDate, time(8, 20))
        XCTAssertEqual(log.scheduledDate, time(8, 0))
        XCTAssertFalse(log.wasSkipped)
        XCTAssertEqual(log.source, MedicationStore.manualSource)
        XCTAssertEqual(log.schedule, schedule)
    }

    /// The adherence chart is exactly this number.
    func testDelayMinutesIsTakenMinusScheduled() throws {
        let schedules = try threeDoseSchedule()

        let late = try MedicationStore.logDose(schedule: schedules[0], takenAt: time(8, 25), in: context, calendar: utc)
        XCTAssertEqual(try XCTUnwrap(late.delayMinutes), 25, accuracy: 1e-9)

        let early = try MedicationStore.logDose(schedule: schedules[1], takenAt: time(12, 50), in: context, calendar: utc)
        XCTAssertEqual(try XCTUnwrap(early.delayMinutes), -10, accuracy: 1e-9)

        let onTime = try MedicationStore.logDose(schedule: schedules[2], takenAt: time(18, 0), in: context, calendar: utc)
        XCTAssertEqual(try XCTUnwrap(onTime.delayMinutes), 0, accuracy: 1e-9)
    }

    func testLogDoseFilesTheRowUnderTheScheduledDay() throws {
        let schedule = try threeDoseSchedule()[0]
        let log = try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 5), in: context, calendar: utc)
        XCTAssertEqual(log.dayStart, referenceDay.timeIntervalSince1970)
    }

    /// A 23:00 dose taken at 00:30 belongs in the column for the day it was due, 90 minutes late.
    func testALateNightDoseIsFiledUnderTheDayItWasDue() throws {
        let schedule = try MedicationStore.replaceSchedule(
            with: [MedicationScheduleSlot(hour: 23, minute: 0)],
            in: context
        )[0]

        let log = try MedicationStore.logDose(
            schedule: schedule,
            takenAt: time(0, 30, dayOffset: 1),
            in: context,
            calendar: utc
        )

        XCTAssertEqual(log.scheduledDate, time(23, 0))
        XCTAssertEqual(log.dayStart, referenceDay.timeIntervalSince1970)
        XCTAssertEqual(try XCTUnwrap(log.delayMinutes), 90, accuracy: 1e-9)
    }

    func testLogDoseRejectsAnInactiveSchedule() throws {
        let schedule = try threeDoseSchedule()[0]
        _ = try MedicationStore.replaceSchedule(with: [MedicationScheduleSlot(hour: 9, minute: 0)], in: context)

        XCTAssertThrowsError(
            try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 5), in: context, calendar: utc)
        ) { error in
            XCTAssertEqual(error as? MedicationStoreError, .scheduleInactive)
        }
    }

    func testLoggingTheSameDoseTwiceOnOneDayIsRejected() throws {
        let schedule = try threeDoseSchedule()[0]
        _ = try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 5), in: context, calendar: utc)

        XCTAssertThrowsError(
            try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 40), in: context, calendar: utc)
        ) { error in
            XCTAssertEqual(
                error as? MedicationStoreError,
                .doseAlreadyLogged(dayStart: referenceDay.timeIntervalSince1970)
            )
        }
        XCTAssertEqual(try count(MedicationLog.self, MedicationLog.fetchRequest()), 1)
    }

    func testTheSameDoseCanBeLoggedOnTwoDifferentDays() throws {
        let schedule = try threeDoseSchedule()[0]
        _ = try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 5), in: context, calendar: utc)
        _ = try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 5, dayOffset: 1), in: context, calendar: utc)

        XCTAssertEqual(try count(MedicationLog.self, MedicationLog.fetchRequest()), 2)
    }

    // MARK: - Skipping

    func testLogSkippedMarksTheRowAndUsesTheScheduledTimeAsTheTimestamp() throws {
        let schedule = try threeDoseSchedule()[1]
        let log = try MedicationStore.logSkipped(
            schedule: schedule,
            onDayContaining: time(15),
            in: context,
            calendar: utc
        )

        XCTAssertTrue(log.wasSkipped)
        XCTAssertEqual(log.takenDate, time(13, 0))
        XCTAssertEqual(log.scheduledDate, time(13, 0))
        XCTAssertEqual(log.dayStart, referenceDay.timeIntervalSince1970)
    }

    /// A skipped dose exists to say the dose did not happen. Treating it as medication context
    /// would make every session look dosed.
    func testASkippedDoseNeverBecomesASessionsMedicationContext() throws {
        let schedule = try threeDoseSchedule()[0]
        _ = try MedicationStore.logSkipped(schedule: schedule, onDayContaining: referenceDay, in: context, calendar: utc)

        let dose = try BradykinesiaStore.mostRecentDose(
            onOrAfter: referenceDay.timeIntervalSince1970,
            atOrBefore: time(10).timeIntervalSince1970,
            in: context
        )
        XCTAssertNil(dose)
    }

    func testATakenDoseIsFoundAsMedicationContext() throws {
        let schedule = try threeDoseSchedule()[0]
        let log = try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 5), in: context, calendar: utc)

        let dose = try BradykinesiaStore.mostRecentDose(
            onOrAfter: referenceDay.timeIntervalSince1970,
            atOrBefore: time(10).timeIntervalSince1970,
            in: context
        )
        XCTAssertEqual(dose, log)
    }

    func testCannotBothTakeAndSkipTheSameDose() throws {
        let schedule = try threeDoseSchedule()[0]
        _ = try MedicationStore.logSkipped(schedule: schedule, onDayContaining: referenceDay, in: context, calendar: utc)

        XCTAssertThrowsError(
            try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 30), in: context, calendar: utc)
        )
        XCTAssertEqual(try count(MedicationLog.self, MedicationLog.fetchRequest()), 1)
    }

    // MARK: - Unscheduled doses

    func testAnUnscheduledDoseHasNoScheduledTimeAndNoDelay() throws {
        let log = try MedicationStore.logUnscheduledDose(takenAt: time(15, 20), in: context, calendar: utc)

        XCTAssertNil(log.schedule)
        XCTAssertEqual(log.scheduledTime, 0)
        XCTAssertNil(log.scheduledDate)
        XCTAssertNil(log.delayMinutes)
        XCTAssertEqual(log.dayStart, referenceDay.timeIntervalSince1970)
    }

    func testSeveralUnscheduledDosesCanBeLoggedOnOneDay() throws {
        _ = try MedicationStore.logUnscheduledDose(takenAt: time(11), in: context, calendar: utc)
        _ = try MedicationStore.logUnscheduledDose(takenAt: time(16), in: context, calendar: utc)
        XCTAssertEqual(try count(MedicationLog.self, MedicationLog.fetchRequest()), 2)
    }

    func testAnUnscheduledDoseStillCountsAsMedicationContext() throws {
        let log = try MedicationStore.logUnscheduledDose(takenAt: time(11), in: context, calendar: utc)
        let dose = try BradykinesiaStore.mostRecentDose(
            onOrAfter: referenceDay.timeIntervalSince1970,
            atOrBefore: time(12).timeIntervalSince1970,
            in: context
        )
        XCTAssertEqual(dose, log)
    }

    // MARK: - Undo

    func testDeleteRemovesTheLogAndFreesTheSlotToBeLoggedAgain() throws {
        let schedule = try threeDoseSchedule()[0]
        let log = try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 5), in: context, calendar: utc)

        try MedicationStore.delete(log, in: context)
        XCTAssertEqual(try count(MedicationLog.self, MedicationLog.fetchRequest()), 0)

        XCTAssertNoThrow(
            try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 40), in: context, calendar: utc)
        )
    }

    // MARK: - Reading back

    func testLogsInARangeComeBackOldestFirstAndExcludeTheUpperBound() throws {
        let schedules = try threeDoseSchedule()
        _ = try MedicationStore.logDose(schedule: schedules[0], takenAt: time(8), in: context, calendar: utc)
        _ = try MedicationStore.logDose(schedule: schedules[1], takenAt: time(13), in: context, calendar: utc)
        _ = try MedicationStore.logDose(schedule: schedules[2], takenAt: time(18), in: context, calendar: utc)

        let logs = try MedicationStore.logs(from: time(8), to: time(18), in: context)
        XCTAssertEqual(logs.map(\.takenDate), [time(8), time(13)])
    }

    func testLogsForADayComeBackOldestFirst() throws {
        let schedules = try threeDoseSchedule()
        _ = try MedicationStore.logDose(schedule: schedules[2], takenAt: time(18), in: context, calendar: utc)
        _ = try MedicationStore.logDose(schedule: schedules[0], takenAt: time(8), in: context, calendar: utc)

        let logs = try MedicationStore.logs(onDayContaining: time(12), in: context, calendar: utc)
        XCTAssertEqual(logs.map(\.takenDate), [time(8), time(18)])
    }

    func testExistingLogFindsOnlyTheMatchingSlotAndDay() throws {
        let schedules = try threeDoseSchedule()
        _ = try MedicationStore.logDose(schedule: schedules[0], takenAt: time(8), in: context, calendar: utc)

        let dayStart = referenceDay.timeIntervalSince1970
        XCTAssertNotNil(try MedicationStore.existingLog(for: schedules[0], onDayStarting: dayStart, in: context))
        XCTAssertNil(try MedicationStore.existingLog(for: schedules[1], onDayStarting: dayStart, in: context))
        XCTAssertNil(
            try MedicationStore.existingLog(
                for: schedules[0],
                onDayStarting: utc.date(byAdding: .day, value: 1, to: referenceDay)!.timeIntervalSince1970,
                in: context
            )
        )
    }

    func testLogsSurviveAContextReset() throws {
        let schedule = try threeDoseSchedule()[0]
        _ = try MedicationStore.logDose(schedule: schedule, takenAt: time(8, 5), in: context, calendar: utc)

        context.reset()

        let logs = try MedicationStore.logs(onDayContaining: referenceDay, in: context, calendar: utc)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.scheduledDate, time(8, 0))
    }
}
