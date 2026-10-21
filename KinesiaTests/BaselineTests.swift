import XCTest
@testable import Kinesia

final class BaselineTests: XCTestCase {

    private func values(_ raw: [Double], startingAt offset: Int = 0) -> [DailyValue] {
        raw.enumerated().map { index, value in
            DailyValue(day: ReportFixtures.day(offset + index), value: value)
        }
    }

    // MARK: - The two thresholds

    func testTheRuleIsFiveFamiliarizationDaysAndFourteenBaselineDays() {
        XCTAssertEqual(BaselineRule.familiarizationDays, 5)
        XCTAssertEqual(BaselineRule.baselineDays, 14)
        XCTAssertEqual(BaselineRule.requiredDays, 19)
    }

    // MARK: - Familiarization

    func testNoDataIsDayZeroOfFive() {
        XCTAssertEqual(
            BaselineRule.state(from: [], hand: .right),
            .familiarization(dayNumber: 0, of: 5)
        )
    }

    func testThreeDaysIsDayThreeOfFive() {
        XCTAssertEqual(
            BaselineRule.state(from: values([5, 5, 5]), hand: .right),
            .familiarization(dayNumber: 3, of: 5)
        )
    }

    func testFourDaysIsStillFamiliarization() {
        XCTAssertEqual(
            BaselineRule.state(from: values(Array(repeating: 5, count: 4)), hand: .right),
            .familiarization(dayNumber: 4, of: 5)
        )
    }

    // MARK: - Building

    func testTheFifthDayStartsBuildingTheBaseline() {
        XCTAssertEqual(
            BaselineRule.state(from: values(Array(repeating: 5, count: 5)), hand: .right),
            .building(dayNumber: 0, of: 14)
        )
    }

    func testBuildingCountsDaysAfterFamiliarization() {
        XCTAssertEqual(
            BaselineRule.state(from: values(Array(repeating: 5, count: 14)), hand: .right),
            .building(dayNumber: 9, of: 14)
        )
    }

    func testEighteenDaysIsOneDayShortOfABaseline() {
        XCTAssertEqual(
            BaselineRule.state(from: values(Array(repeating: 5, count: 18)), hand: .right),
            .building(dayNumber: 13, of: 14)
        )
    }

    // MARK: - Established

    func testNineteenDaysEstablishesTheBaseline() throws {
        let state = BaselineRule.state(from: values(Array(repeating: 5, count: 19)), hand: .right)
        let baseline = try XCTUnwrap(state.baseline)

        XCTAssertEqual(baseline.dayCount, 14)
        XCTAssertEqual(baseline.center, 5, accuracy: 1e-9)
        XCTAssertEqual(baseline.hand, .right)
    }

    // The first five days are excluded, so a patient who ramps up during familiarization does
    // not drag the baseline down.
    func testTheFirstFiveDaysAreExcluded() throws {
        var raw = Array(repeating: 10.0, count: 19)
        for index in 0..<5 { raw[index] = 1 }

        let baseline = try XCTUnwrap(BaselineRule.state(from: values(raw), hand: .right).baseline)
        XCTAssertEqual(baseline.center, 10, accuracy: 1e-9)
    }

    func testTheBandIsTheTwentyFifthToSeventyFifthPercentile() throws {
        // 5 familiarization days, then 14 values 1...14.
        let raw = Array(repeating: 99.0, count: 5) + (1...14).map(Double.init)
        let baseline = try XCTUnwrap(BaselineRule.state(from: values(raw), hand: .right).baseline)

        let stats = try XCTUnwrap(SummaryStats.compute((1...14).map(Double.init)))
        XCTAssertEqual(baseline.center, stats.median, accuracy: 1e-9)
        XCTAssertEqual(baseline.lower, stats.p25, accuracy: 1e-9)
        XCTAssertEqual(baseline.upper, stats.p75, accuracy: 1e-9)
        XCTAssertEqual(baseline.spread, stats.stdev, accuracy: 1e-9)
    }

    func testEstablishedOnIsTheLastBaselineDay() throws {
        let baseline = try XCTUnwrap(
            BaselineRule.state(from: values(Array(repeating: 5, count: 25)), hand: .right).baseline
        )
        // Day 0 to 4 are familiarization, day 5 to 18 are the baseline.
        XCTAssertEqual(baseline.establishedOn, ReportFixtures.day(18))
    }

    // The baseline is the first 14 days after familiarization and does not grow, so the band
    // stays where the patient started.
    func testMoreDataDoesNotMoveAnEstablishedBaseline() throws {
        let nineteen = Array(repeating: 5.0, count: 19)
        let thirty = nineteen + Array(repeating: 50.0, count: 11)

        let first = try XCTUnwrap(BaselineRule.state(from: values(nineteen), hand: .right).baseline)
        let later = try XCTUnwrap(BaselineRule.state(from: values(thirty), hand: .right).baseline)

        XCTAssertEqual(first, later)
    }

    func testContainsChecksTheBand() throws {
        let raw = Array(repeating: 99.0, count: 5) + (1...14).map(Double.init)
        let baseline = try XCTUnwrap(BaselineRule.state(from: values(raw), hand: .right).baseline)

        XCTAssertTrue(baseline.contains(baseline.center))
        XCTAssertTrue(baseline.contains(baseline.lower))
        XCTAssertTrue(baseline.contains(baseline.upper))
        XCTAssertFalse(baseline.contains(baseline.lower - 1))
        XCTAssertFalse(baseline.contains(baseline.upper + 1))
    }

    // MARK: - Input handling

    func testDaysAreCountedAsDaysWithDataNotCalendarDays() throws {
        // 19 days of data spread across 40 calendar days.
        let scattered = (0..<19).map { index in
            DailyValue(day: ReportFixtures.day(index * 2), value: 5)
        }

        XCTAssertNotNil(BaselineRule.state(from: scattered, hand: .right).baseline)
    }

    func testOutOfOrderInputIsSorted() throws {
        let raw = Array(repeating: 99.0, count: 5) + (1...14).map(Double.init)
        let ordered = values(raw)

        let shuffled = BaselineRule.state(from: ordered.reversed(), hand: .right)
        let sorted = BaselineRule.state(from: ordered, hand: .right)

        XCTAssertEqual(shuffled, sorted)
    }

    func testNonFiniteValuesAreDroppedAndDoNotCountAsDays() {
        let raw = Array(repeating: 5.0, count: 18) + [.nan]
        XCTAssertEqual(
            BaselineRule.state(from: values(raw), hand: .right),
            .building(dayNumber: 13, of: 14)
        )
    }

    func testTheHandIsCarriedThrough() throws {
        let baseline = try XCTUnwrap(
            BaselineRule.state(from: values(Array(repeating: 5, count: 19)), hand: .left).baseline
        )
        XCTAssertEqual(baseline.hand, .left)
    }

    // MARK: - Building daily values from sessions

    func testDailyValuesTakesTheDailyMedianPerDay() throws {
        let sessions = [
            ReportFixtures.session(dayOffset: 0, hour: 9, tapping: [ReportFixtures.tapping(dayOffset: 0, hour: 9, numTaps: 80)]),
            ReportFixtures.session(dayOffset: 0, hour: 12, tapping: [ReportFixtures.tapping(dayOffset: 0, hour: 12, numTaps: 120)]),
            ReportFixtures.session(dayOffset: 1, hour: 9, tapping: [ReportFixtures.tapping(dayOffset: 1, hour: 9, numTaps: 100)])
        ]

        let daily = BaselineRule.dailyValues(
            sessions: sessions,
            hand: .right,
            calendar: ReportFixtures.utc,
            value: PrimaryMetric.tapRate.value
        )

        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily[0].day, ReportFixtures.day(0))
        XCTAssertEqual(daily[0].value, 5, accuracy: 1e-9) // median of 4 and 6
        XCTAssertEqual(daily[1].value, 5, accuracy: 1e-9)
    }

    func testDailyValuesSkipsDaysWithNoValueForThatHand() {
        let sessions = [
            ReportFixtures.session(dayOffset: 0, tapping: [ReportFixtures.tapping(hand: .right)]),
            ReportFixtures.session(dayOffset: 1, tapping: [ReportFixtures.tapping(hand: .right)])
        ]

        let daily = BaselineRule.dailyValues(
            sessions: sessions,
            hand: .left,
            calendar: ReportFixtures.utc,
            value: PrimaryMetric.tapRate.value
        )
        XCTAssertTrue(daily.isEmpty)
    }

    func testDailyValuesComeBackOldestFirst() {
        let sessions = (0..<5).reversed().map { ReportFixtures.session(dayOffset: $0) }
        let daily = BaselineRule.dailyValues(
            sessions: sessions,
            hand: .right,
            calendar: ReportFixtures.utc,
            value: PrimaryMetric.tapRate.value
        )
        XCTAssertEqual(daily.map(\.day), daily.map(\.day).sorted())
    }

    // The baseline needs 19 days and the default window is 7, so it reads the whole history.
    func testAFullHistoryEstablishesABaselineTheWindowCouldNotHold() throws {
        let history = ReportFixtures.history(count: 19) { _ in 5 }
        let daily = BaselineRule.dailyValues(
            sessions: history,
            hand: .right,
            calendar: ReportFixtures.utc,
            value: PrimaryMetric.tapRate.value
        )

        XCTAssertEqual(daily.count, 19)
        XCTAssertNotNil(BaselineRule.state(from: daily, hand: .right).baseline)
    }
}
