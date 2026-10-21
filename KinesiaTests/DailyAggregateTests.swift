import XCTest
@testable import Kinesia

final class DailyAggregateTests: XCTestCase {

    private let window = ReportFixtures.window(days: 7)

    // MARK: - Shape

    func testThereIsOneRowPerDayInTheWindow() {
        let rows = DailyAggregation.aggregate(
            sessions: [ReportFixtures.session(dayOffset: 2)],
            doses: [],
            window: window,
            metric: .tapRate
        )

        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows.map(\.dayStart), (0..<7).map(ReportFixtures.day))
    }

    func testRowsAreOldestFirst() {
        let rows = DailyAggregation.aggregate(
            sessions: ReportFixtures.history(count: 7) { _ in 5 },
            doses: [],
            window: window,
            metric: .tapRate
        )
        XCTAssertEqual(rows.map(\.dayStart), rows.map(\.dayStart).sorted())
    }

    // A day with no sessions still needs a row so a chart can show "no data".
    func testADayWithNoSessionsHasARowWithNilValues() {
        let rows = DailyAggregation.aggregate(
            sessions: [ReportFixtures.session(dayOffset: 0)],
            doses: [],
            window: window,
            metric: .tapRate
        )

        let empty = rows[3]
        XCTAssertNil(empty.right)
        XCTAssertNil(empty.left)
        XCTAssertEqual(empty.sessionCount, 0)
        XCTAssertFalse(empty.hasSessions)
    }

    // MARK: - Daily median

    func testOneSessionInADayGivesThatSessionsValue() throws {
        let rows = DailyAggregation.aggregate(
            sessions: [
                ReportFixtures.session(
                    dayOffset: 0,
                    tapping: [ReportFixtures.tapping(numTaps: 100, durationSec: 20)]
                )
            ],
            doses: [],
            window: window,
            metric: .tapRate
        )

        XCTAssertEqual(try XCTUnwrap(rows[0].right), 5, accuracy: 1e-9)
    }

    func testThreeSessionsInADayGiveTheMiddleValue() throws {
        let rates = [4.0, 6.0, 5.0]
        let sessions = rates.enumerated().map { index, rate in
            ReportFixtures.session(
                dayOffset: 0,
                hour: 9 + index,
                tapping: [ReportFixtures.tapping(dayOffset: 0, hour: 9 + index, numTaps: Int(rate * 20), durationSec: 20)]
            )
        }

        let rows = DailyAggregation.aggregate(sessions: sessions, doses: [], window: window, metric: .tapRate)
        XCTAssertEqual(try XCTUnwrap(rows[0].right), 5, accuracy: 1e-9)
    }

    func testAnEvenNumberOfSessionsAveragesTheTwoMiddleValues() throws {
        let sessions = [4.0, 6.0].enumerated().map { index, rate in
            ReportFixtures.session(
                dayOffset: 0,
                hour: 9 + index,
                tapping: [ReportFixtures.tapping(dayOffset: 0, hour: 9 + index, numTaps: Int(rate * 20), durationSec: 20)]
            )
        }

        let rows = DailyAggregation.aggregate(sessions: sessions, doses: [], window: window, metric: .tapRate)
        XCTAssertEqual(try XCTUnwrap(rows[0].right), 5, accuracy: 1e-9)
    }

    // MARK: - Hands

    func testHandsAreAggregatedSeparately() throws {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [
                ReportFixtures.tapping(hand: .right, numTaps: 100, durationSec: 20),
                ReportFixtures.tapping(hand: .left, numTaps: 60, durationSec: 20)
            ]
        )

        let rows = DailyAggregation.aggregate(sessions: [session], doses: [], window: window, metric: .tapRate)
        XCTAssertEqual(try XCTUnwrap(rows[0].right), 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(rows[0].left), 3, accuracy: 1e-9)
    }

    func testAHandWithNoResultIsNil() {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [ReportFixtures.tapping(hand: .right)]
        )

        let rows = DailyAggregation.aggregate(sessions: [session], doses: [], window: window, metric: .tapRate)
        XCTAssertNotNil(rows[0].right)
        XCTAssertNil(rows[0].left)
    }

    func testValueForHandMatchesTheStoredFields() throws {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [
                ReportFixtures.tapping(hand: .right, numTaps: 100, durationSec: 20),
                ReportFixtures.tapping(hand: .left, numTaps: 60, durationSec: 20)
            ]
        )
        let row = DailyAggregation.aggregate(sessions: [session], doses: [], window: window, metric: .tapRate)[0]

        XCTAssertEqual(row.value(for: .right), row.right)
        XCTAssertEqual(row.value(for: .left), row.left)
    }

    // MARK: - Other metrics

    func testReactionTimeConvertsSecondsToMilliseconds() throws {
        let session = ReportFixtures.session(
            dayOffset: 0,
            firefly: ReportFixtures.firefly(reactionTimeMedian: 0.35)
        )

        let rows = DailyAggregation.aggregate(sessions: [session], doses: [], window: window, metric: .reactionTime)
        XCTAssertEqual(try XCTUnwrap(rows[0].right), 350, accuracy: 1e-9)
    }

    func testTracingErrorUsesRmsError() throws {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tracing: ReportFixtures.tracing(rmsError: 4.2)
        )

        let rows = DailyAggregation.aggregate(sessions: [session], doses: [], window: window, metric: .tracingError)
        XCTAssertEqual(try XCTUnwrap(rows[0].right), 4.2, accuracy: 1e-9)
    }

    // MARK: - Invalid rows

    // numTaps and durationSec are validated by the store separately from the statistics, so
    // tap rate is a real measurement even when isValid is false.
    func testTapRateSurvivesAnInvalidRow() throws {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [
                ReportFixtures.tapping(
                    numTaps: 100,
                    durationSec: 20,
                    cvTapInter: nil,
                    tapInterSlope: nil,
                    isValid: false,
                    invalidReason: "tap interval statistics unavailable"
                )
            ]
        )

        let rows = DailyAggregation.aggregate(sessions: [session], doses: [], window: window, metric: .tapRate)
        XCTAssertEqual(try XCTUnwrap(rows[0].right), 5, accuracy: 1e-9)
    }

    func testAZeroDurationGivesNoValueRatherThanInfinity() {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [ReportFixtures.tapping(numTaps: 100, durationSec: 0)]
        )

        let rows = DailyAggregation.aggregate(sessions: [session], doses: [], window: window, metric: .tapRate)
        XCTAssertNil(rows[0].right)
    }

    // MARK: - Doses

    func testDoseCountCountsTakenDosesOnThatDay() {
        let doses = [
            ReportFixtures.dose(dayOffset: 1, scheduledHour: 8),
            ReportFixtures.dose(dayOffset: 1, scheduledHour: 13),
            ReportFixtures.dose(dayOffset: 2, scheduledHour: 8)
        ]

        let rows = DailyAggregation.aggregate(sessions: [], doses: doses, window: window, metric: .tapRate)
        XCTAssertEqual(rows[1].doseCount, 2)
        XCTAssertEqual(rows[2].doseCount, 1)
        XCTAssertEqual(rows[0].doseCount, 0)
    }

    func testASkippedDoseIsNotCounted() {
        let doses = [
            ReportFixtures.dose(dayOffset: 0, scheduledHour: 8),
            ReportFixtures.dose(dayOffset: 0, scheduledHour: 13, wasSkipped: true)
        ]

        let rows = DailyAggregation.aggregate(sessions: [], doses: doses, window: window, metric: .tapRate)
        XCTAssertEqual(rows[0].doseCount, 1)
    }

    // MARK: - Window edges

    func testSessionsOutsideTheWindowAreDropped() {
        let sessions = [
            ReportFixtures.session(dayOffset: -1),
            ReportFixtures.session(dayOffset: 0),
            ReportFixtures.session(dayOffset: 7)
        ]

        let rows = DailyAggregation.aggregate(sessions: sessions, doses: [], window: window, metric: .tapRate)
        XCTAssertEqual(rows.map(\.sessionCount).reduce(0, +), 1)
        XCTAssertEqual(rows[0].sessionCount, 1)
    }

    func testASessionLateOnTheLastDayIsInsideTheWindow() {
        let sessions = [ReportFixtures.session(dayOffset: 6, hour: 23)]
        let rows = DailyAggregation.aggregate(sessions: sessions, doses: [], window: window, metric: .tapRate)
        XCTAssertEqual(rows[6].sessionCount, 1)
    }

    // MARK: - The median helper

    func testMedianOfOneValue() {
        XCTAssertEqual(DailyAggregation.median([4]), 4)
    }

    func testMedianOfNoValues() {
        XCTAssertNil(DailyAggregation.median([]))
    }

    func testMedianIgnoresNonFiniteValues() {
        XCTAssertEqual(DailyAggregation.median([4, .nan, 6]), 5)
        XCTAssertNil(DailyAggregation.median([.nan, .infinity]))
    }
}
