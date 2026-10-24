import XCTest
@testable import Kinesia

@MainActor
final class HomeSummaryTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func session(
        day: Int,
        firefly: Bool = false,
        tracing: Bool = false,
        tapping: Bool = false
    ) -> SessionSnapshot {
        SessionSnapshot(
            id: UUID(),
            startedAt: date(day),
            dayStart: calendar.startOfDay(for: date(day)),
            minutesSinceDose: nil,
            tapping: tapping
                ? [TappingSnapshot(
                    hand: .right, timestamp: date(day), numTaps: 40, durationSec: 20,
                    tapInterMedian: nil, cvTapInter: nil, tapInterSlope: nil,
                    numCorrectTaps: 40, isValid: true, invalidReason: nil, metricsVersion: 1)]
                : [],
            firefly: firefly
                ? FireflySnapshot(
                    hand: .right, timestamp: date(day), reactionTimeMedian: nil,
                    reactionTimeP90: nil, movementTimeMedian: nil, numRounds: 12,
                    numValidRounds: 12, numLapses: 0, numMissed: 0, isValid: true,
                    invalidReason: nil, metricsVersion: 1)
                : nil,
            tracing: tracing
                ? TracingSnapshot(
                    hand: .right, timestamp: date(day), rmsError: nil, swipeSpeedMedian: nil,
                    fingerLifts: 0, numSequences: 3, doneSequences: 3, isValid: true,
                    invalidReason: nil, metricsVersion: 1)
                : nil
        )
    }

    // MARK: Streak

    func testStreakCountsConsecutiveDaysEndingToday() {
        let days = Set([20, 21, 22, 23].map { calendar.startOfDay(for: date($0)) })
        XCTAssertEqual(
            HomeSummaryBuilder.streak(days: days, today: calendar.startOfDay(for: date(23)), calendar: calendar),
            4
        )
    }

    // The patient has not checked in yet this morning. Their streak is intact until
    // the day ends, so it counts back from yesterday.
    func testStreakSurvivesTodayNotBeingLoggedYet() {
        let days = Set([20, 21, 22].map { calendar.startOfDay(for: date($0)) })
        XCTAssertEqual(
            HomeSummaryBuilder.streak(days: days, today: calendar.startOfDay(for: date(23)), calendar: calendar),
            3
        )
    }

    func testStreakBreaksOnAMissedDay() {
        let days = Set([19, 20, 22, 23].map { calendar.startOfDay(for: date($0)) })
        XCTAssertEqual(
            HomeSummaryBuilder.streak(days: days, today: calendar.startOfDay(for: date(23)), calendar: calendar),
            2
        )
    }

    func testStreakIsZeroWhenTheLastTwoDaysAreMissed() {
        let days = Set([20, 21].map { calendar.startOfDay(for: date($0)) })
        XCTAssertEqual(
            HomeSummaryBuilder.streak(days: days, today: calendar.startOfDay(for: date(23)), calendar: calendar),
            0
        )
    }

    func testStreakIsZeroWithNoHistory() {
        XCTAssertEqual(
            HomeSummaryBuilder.streak(days: [], today: calendar.startOfDay(for: date(23)), calendar: calendar),
            0
        )
    }

    // MARK: Day number

    func testDayNumberCountsFromTheFirstRecordedSession() {
        let summary = HomeSummaryBuilder.make(
            sessions: [session(day: 1), session(day: 23)],
            slots: [],
            now: date(23),
            calendar: calendar
        )
        XCTAssertEqual(summary.dayNumber, 23)
    }

    func testDayNumberIsNilWithNoHistory() {
        let summary = HomeSummaryBuilder.make(sessions: [], slots: [], now: date(23), calendar: calendar)
        XCTAssertNil(summary.dayNumber)
        XCTAssertFalse(summary.hasHistory)
        XCTAssertEqual(summary.streak, 0)
    }

    // MARK: Done today

    func testCheckedInTodayNeedsAllThreeTests() {
        let partial = HomeSummaryBuilder.make(
            sessions: [session(day: 23, firefly: true, tracing: true)],
            slots: [],
            now: date(23),
            calendar: calendar
        )
        XCTAssertEqual(partial.doneToday, [.fireflies, .constellation])
        XCTAssertFalse(partial.checkedInToday)

        let complete = HomeSummaryBuilder.make(
            sessions: [session(day: 23, firefly: true, tracing: true, tapping: true)],
            slots: [],
            now: date(23),
            calendar: calendar
        )
        XCTAssertEqual(complete.doneToday, [.fireflies, .constellation, .ripples])
        XCTAssertTrue(complete.checkedInToday)
    }

    func testYesterdaysTestsDoNotCountAsDoneToday() {
        let summary = HomeSummaryBuilder.make(
            sessions: [session(day: 22, firefly: true, tracing: true, tapping: true)],
            slots: [],
            now: date(23),
            calendar: calendar
        )
        XCTAssertTrue(summary.doneToday.isEmpty)
        XCTAssertFalse(summary.checkedInToday)
    }

    // MARK: Next dose

    func testNextDoseIsTheNextSlotLaterToday() {
        let slots = [
            MedicationScheduleSlot(hour: 8, minute: 0),
            MedicationScheduleSlot(hour: 13, minute: 0),
            MedicationScheduleSlot(hour: 18, minute: 0)
        ]
        let next = HomeSummaryBuilder.nextDose(slots: slots, now: date(23, hour: 14), calendar: calendar)
        XCTAssertEqual(next, date(23, hour: 18))
    }

    func testNextDoseRollsOverToTomorrowAfterTheLastSlot() {
        let slots = [MedicationScheduleSlot(hour: 8, minute: 0), MedicationScheduleSlot(hour: 18, minute: 0)]
        let next = HomeSummaryBuilder.nextDose(slots: slots, now: date(23, hour: 21), calendar: calendar)
        XCTAssertEqual(next, date(24, hour: 8))
    }

    func testNextDoseIsNilWithoutASchedule() {
        XCTAssertNil(HomeSummaryBuilder.nextDose(slots: [], now: date(23), calendar: calendar))
    }
}
