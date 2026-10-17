import XCTest
@testable import Kinesia

/// Pure schedule arithmetic. No Core Data: these rules are validated before anything is written.
final class MedicationSchedulePlanTests: XCTestCase {

    /// A fixed, non-DST calendar so occurrence arithmetic is reproducible anywhere the suite runs.
    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func slot(_ hour: Int, _ minute: Int = 0) -> MedicationScheduleSlot {
        MedicationScheduleSlot(hour: hour, minute: minute)
    }

    // MARK: - Validation

    func testValidateAcceptsAnOrdinaryThreeDoseDay() throws {
        XCTAssertNoThrow(try MedicationSchedulePlan.validate([slot(8), slot(13), slot(18)]))
    }

    func testValidateRejectsAnEmptyPlan() {
        XCTAssertThrowsError(try MedicationSchedulePlan.validate([])) { error in
            XCTAssertEqual(error as? MedicationScheduleError, .noSlots)
        }
    }

    func testValidateRejectsAnHourOutsideTheDay() {
        XCTAssertThrowsError(try MedicationSchedulePlan.validate([slot(24, 0)])) { error in
            XCTAssertEqual(error as? MedicationScheduleError, .invalidTimeOfDay(hour: 24, minute: 0))
        }
    }

    func testValidateRejectsAMinuteOutsideTheHour() {
        XCTAssertThrowsError(try MedicationSchedulePlan.validate([slot(8, 60)])) { error in
            XCTAssertEqual(error as? MedicationScheduleError, .invalidTimeOfDay(hour: 8, minute: 60))
        }
    }

    func testValidateAcceptsTheBoundaryTimes() {
        XCTAssertNoThrow(try MedicationSchedulePlan.validate([slot(0, 0), slot(23, 59)]))
    }

    /// Two doses at the same clock time cannot be told apart in the adherence chart, and the
    /// "already logged today" check would match both.
    func testValidateRejectsTwoDosesAtTheSameTime() {
        XCTAssertThrowsError(try MedicationSchedulePlan.validate([slot(8), slot(13), slot(8)])) { error in
            XCTAssertEqual(error as? MedicationScheduleError, .duplicateSlot(hour: 8, minute: 0))
        }
    }

    func testValidateAcceptsTwoDosesOneMinuteApart() {
        XCTAssertNoThrow(try MedicationSchedulePlan.validate([slot(8, 0), slot(8, 1)]))
    }

    func testValidateRejectsANegativeDosage() {
        var negative = slot(8)
        negative.dosageMg = -1
        XCTAssertThrowsError(try MedicationSchedulePlan.validate([negative])) { error in
            XCTAssertEqual(error as? MedicationScheduleError, .invalidDosage(-1))
        }
    }

    func testValidateRejectsANonFiniteDosage() {
        var broken = slot(8)
        broken.dosageMg = .nan
        XCTAssertThrowsError(try MedicationSchedulePlan.validate([broken]))
    }

    /// A patient who does not know their milligrams still has a dose with a time, which is what
    /// every dose-linked chart actually needs.
    func testValidateAcceptsAZeroDosage() {
        XCTAssertNoThrow(try MedicationSchedulePlan.validate([slot(8)]))
    }

    // MARK: - Ordering

    func testOrderedSortsByTimeOfDay() {
        let ordered = MedicationSchedulePlan.ordered([slot(18), slot(8), slot(13)])
        XCTAssertEqual(ordered.map(\.hour), [8, 13, 18])
    }

    func testMinutesIntoDay() {
        XCTAssertEqual(slot(0, 0).minutesIntoDay, 0)
        XCTAssertEqual(slot(13, 30).minutesIntoDay, 810)
        XCTAssertEqual(slot(23, 59).minutesIntoDay, 1439)
    }

    // MARK: - Occurrences

    func testOccurrenceLandsOnTheRequestedClockTime() throws {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let occurrence = try XCTUnwrap(
            MedicationSchedulePlan.occurrence(of: slot(8, 30), onDayContaining: day, calendar: utc)
        )
        let parts = utc.dateComponents([.hour, .minute], from: occurrence)
        XCTAssertEqual(parts.hour, 8)
        XCTAssertEqual(parts.minute, 30)
        XCTAssertEqual(utc.startOfDay(for: occurrence), utc.startOfDay(for: day))
    }

    /// The case the whole nearest-occurrence rule exists for: a 23:00 dose taken at 00:30 is
    /// 90 minutes late, not 22.5 hours early.
    func testNearestOccurrenceResolvesALateNightDoseToThePreviousDay() throws {
        let scheduled = try XCTUnwrap(
            MedicationSchedulePlan.occurrence(
                of: slot(23),
                onDayContaining: Date(timeIntervalSince1970: 1_800_000_000),
                calendar: utc
            )
        )
        let takenAt = scheduled.addingTimeInterval(90 * 60)   // 00:30 the next day

        let nearest = try XCTUnwrap(
            MedicationSchedulePlan.nearestOccurrence(of: slot(23), to: takenAt, calendar: utc)
        )
        XCTAssertEqual(nearest, scheduled)
        XCTAssertEqual(takenAt.timeIntervalSince(nearest) / 60, 90, accuracy: 1e-9)
    }

    /// The mirror case: an early dose resolves forward, not back a whole day.
    func testNearestOccurrenceResolvesAnEarlyMorningDoseToTheComingDay() throws {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let scheduled = try XCTUnwrap(
            MedicationSchedulePlan.occurrence(of: slot(1), onDayContaining: day, calendar: utc)
        )
        let takenAt = scheduled.addingTimeInterval(-30 * 60)  // 00:30, half an hour early

        let nearest = try XCTUnwrap(
            MedicationSchedulePlan.nearestOccurrence(of: slot(1), to: takenAt, calendar: utc)
        )
        XCTAssertEqual(nearest, scheduled)
        XCTAssertEqual(takenAt.timeIntervalSince(nearest) / 60, -30, accuracy: 1e-9)
    }

    func testNearestOccurrenceOfAnExactlyOnTimeDoseIsZeroAway() throws {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let scheduled = try XCTUnwrap(
            MedicationSchedulePlan.occurrence(of: slot(8), onDayContaining: day, calendar: utc)
        )
        let nearest = try XCTUnwrap(
            MedicationSchedulePlan.nearestOccurrence(of: slot(8), to: scheduled, calendar: utc)
        )
        XCTAssertEqual(nearest.timeIntervalSince(scheduled), 0, accuracy: 1e-9)
    }

    /// A dose 11 hours late still resolves to its own day. Anything further is genuinely
    /// ambiguous, and the nearest occurrence is the honest answer either way.
    func testNearestOccurrenceStaysOnTheSameDayWithinTwelveHours() throws {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let scheduled = try XCTUnwrap(
            MedicationSchedulePlan.occurrence(of: slot(8), onDayContaining: day, calendar: utc)
        )
        let nearest = try XCTUnwrap(
            MedicationSchedulePlan.nearestOccurrence(
                of: slot(8),
                to: scheduled.addingTimeInterval(11 * 3600),
                calendar: utc
            )
        )
        XCTAssertEqual(nearest, scheduled)
    }

    /// A clock time that does not exist on a spring-forward day must not be invented.
    /// America/New_York skips 02:00–03:00 on 9 March 2025.
    func testOccurrenceDoesNotInventATimeSkippedByDaylightSaving() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        var springForward = DateComponents()
        springForward.year = 2025
        springForward.month = 3
        springForward.day = 9
        springForward.hour = 12
        let day = try XCTUnwrap(newYork.date(from: springForward))

        let occurrence = MedicationSchedulePlan.occurrence(
            of: slot(2, 30),
            onDayContaining: day,
            calendar: newYork
        )

        // Either no occurrence, or one that is not the non-existent 02:30.
        if let occurrence {
            let parts = newYork.dateComponents([.hour, .minute], from: occurrence)
            XCTAssertFalse(parts.hour == 2 && parts.minute == 30)
        }
    }
}
