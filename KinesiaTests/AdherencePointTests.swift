import XCTest
@testable import Kinesia

final class AdherencePointTests: XCTestCase {

    private let window = ReportFixtures.window(days: 7)

    // MARK: - Delay

    func testADoseTakenOnTimeHasZeroDelay() throws {
        let points = Adherence.points(doses: [ReportFixtures.dose(delayMinutes: 0)], window: window)
        XCTAssertEqual(try XCTUnwrap(points[0].delayMinutes), 0, accuracy: 1e-9)
    }

    func testALateDoseIsPositive() throws {
        let points = Adherence.points(doses: [ReportFixtures.dose(delayMinutes: 25)], window: window)
        XCTAssertEqual(try XCTUnwrap(points[0].delayMinutes), 25, accuracy: 1e-9)
    }

    func testAnEarlyDoseIsNegative() throws {
        let points = Adherence.points(doses: [ReportFixtures.dose(delayMinutes: -10)], window: window)
        XCTAssertEqual(try XCTUnwrap(points[0].delayMinutes), -10, accuracy: 1e-9)
    }

    // A dose due at 23:00 and taken at 00:30 is 90 minutes late. MedicationStore files it under
    // the day it was due, so the point lands in that day's column.
    func testALateNightDoseIsLateNotNearlyADayEarly() throws {
        let dose = ReportFixtures.dose(dayOffset: 2, scheduledHour: 23, delayMinutes: 90)
        let points = Adherence.points(doses: [dose], window: window)

        XCTAssertEqual(try XCTUnwrap(points[0].delayMinutes), 90, accuracy: 1e-9)
        XCTAssertEqual(points[0].dayStart, ReportFixtures.day(2))
    }

    // MARK: - Skipped doses

    // A skipped dose was never taken, so it has no delay. Drawing it at zero would read as
    // on schedule.
    func testASkippedDoseHasNoDelayButStillAppears() {
        let points = Adherence.points(
            doses: [ReportFixtures.dose(wasSkipped: true)],
            window: window
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertTrue(points[0].wasSkipped)
        XCTAssertNil(points[0].delayMinutes)
    }

    // MARK: - Unscheduled doses

    // An unscheduled dose has no scheduled time to be late against. It still shows on the daily
    // timeline and still counts as medication context for a session.
    func testAnUnscheduledDoseIsLeftOut() {
        let doses = [
            ReportFixtures.dose(scheduledHour: 8),
            ReportFixtures.dose(scheduled: false)
        ]

        let points = Adherence.points(doses: doses, window: window)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].slotMinutesIntoDay, 480)
    }

    // MARK: - Slots

    func testTheSlotIsMinutesSinceMidnight() {
        let points = Adherence.points(
            doses: [ReportFixtures.dose(scheduledHour: 13, scheduledMinute: 30)],
            window: window
        )
        XCTAssertEqual(points[0].slotMinutesIntoDay, 13 * 60 + 30)
        XCTAssertEqual(points[0].slotTimeLabel, "13:30")
    }

    func testTheSlotLabelPadsSingleDigitHours() {
        let points = Adherence.points(
            doses: [ReportFixtures.dose(scheduledHour: 8, scheduledMinute: 5)],
            window: window
        )
        XCTAssertEqual(points[0].slotTimeLabel, "08:05")
    }

    func testTheSameSlotOnDifferentDaysSharesOneIdentity() {
        let doses = (0..<3).map { ReportFixtures.dose(dayOffset: $0, scheduledHour: 8) }
        let points = Adherence.points(doses: doses, window: window)

        XCTAssertEqual(Set(points.map(\.slotMinutesIntoDay)).count, 1)
    }

    func testSlotsComeBackInTimeOfDayOrder() {
        let doses = [
            ReportFixtures.dose(scheduledHour: 18),
            ReportFixtures.dose(scheduledHour: 8),
            ReportFixtures.dose(scheduledHour: 13)
        ]

        let slots = Adherence.slots(in: Adherence.points(doses: doses, window: window))
        XCTAssertEqual(slots, [8 * 60, 13 * 60, 18 * 60])
    }

    func testThePatientsOwnLabelIsCarriedThrough() {
        let points = Adherence.points(
            doses: [ReportFixtures.dose(slotLabel: "Morning")],
            window: window
        )
        XCTAssertEqual(points[0].slotLabel, "Morning")
    }

    // MARK: - Ordering and the window

    func testPointsAreSortedByDayThenBySlot() {
        let doses = [
            ReportFixtures.dose(dayOffset: 1, scheduledHour: 18),
            ReportFixtures.dose(dayOffset: 0, scheduledHour: 13),
            ReportFixtures.dose(dayOffset: 1, scheduledHour: 8),
            ReportFixtures.dose(dayOffset: 0, scheduledHour: 8)
        ]

        let points = Adherence.points(doses: doses, window: window)
        XCTAssertEqual(
            points.map { ($0.dayStart, $0.slotMinutesIntoDay) }.map { "\($0.0.timeIntervalSince1970)-\($0.1)" },
            [
                "\(ReportFixtures.day(0).timeIntervalSince1970)-480",
                "\(ReportFixtures.day(0).timeIntervalSince1970)-780",
                "\(ReportFixtures.day(1).timeIntervalSince1970)-480",
                "\(ReportFixtures.day(1).timeIntervalSince1970)-1080"
            ]
        )
    }

    func testDosesOutsideTheWindowAreDropped() {
        let doses = [
            ReportFixtures.dose(dayOffset: -1),
            ReportFixtures.dose(dayOffset: 0),
            ReportFixtures.dose(dayOffset: 7)
        ]

        XCTAssertEqual(Adherence.points(doses: doses, window: window).count, 1)
    }

    func testADoseOnTheLastDayOfTheWindowIsIncluded() {
        let points = Adherence.points(doses: [ReportFixtures.dose(dayOffset: 6)], window: window)
        XCTAssertEqual(points.count, 1)
    }

    func testNoDosesGivesNoPoints() {
        XCTAssertTrue(Adherence.points(doses: [], window: window).isEmpty)
    }

    // MARK: - Counting off schedule

    func testCountOffScheduleUsesTheAbsoluteDelay() {
        let doses = [
            ReportFixtures.dose(dayOffset: 0, scheduledHour: 8, delayMinutes: 45),
            ReportFixtures.dose(dayOffset: 0, scheduledHour: 13, delayMinutes: -45),
            ReportFixtures.dose(dayOffset: 0, scheduledHour: 18, delayMinutes: 5)
        ]

        let points = Adherence.points(doses: doses, window: window)
        XCTAssertEqual(Adherence.countOffSchedule(points, byMoreThan: 30), 2)
    }

    func testASkippedDoseIsNotCountedAsOffSchedule() {
        let points = Adherence.points(
            doses: [ReportFixtures.dose(wasSkipped: true)],
            window: window
        )
        XCTAssertEqual(Adherence.countOffSchedule(points, byMoreThan: 0), 0)
    }

    func testADoseExactlyAtTheThresholdIsNotCounted() {
        let points = Adherence.points(
            doses: [ReportFixtures.dose(delayMinutes: 30)],
            window: window
        )
        XCTAssertEqual(Adherence.countOffSchedule(points, byMoreThan: 30), 0)
    }
}
