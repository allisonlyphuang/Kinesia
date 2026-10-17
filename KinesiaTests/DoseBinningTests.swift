import XCTest
@testable import Kinesia

final class DoseBinningTests: XCTestCase {

    private let window = ReportFixtures.window(days: 7)

    private func session(minutesSinceDose: Double?, tapRate: Double = 5, dayOffset: Int = 0, hour: Int = 9) -> SessionSnapshot {
        ReportFixtures.session(
            dayOffset: dayOffset,
            hour: hour,
            minutesSinceDose: minutesSinceDose,
            tapping: [
                ReportFixtures.tapping(dayOffset: dayOffset, hour: hour, numTaps: Int(tapRate * 20), durationSec: 20)
            ]
        )
    }

    private func bins(_ sessions: [SessionSnapshot], hand: CurrentHand = .right) -> [DoseBin] {
        DoseBinning.bins(sessions: sessions, window: window, metric: .tapRate, hand: hand)
    }

    private func bin(_ bins: [DoseBin], _ kind: DoseBinKind) throws -> DoseBin {
        try XCTUnwrap(bins.first { $0.kind == kind })
    }

    // MARK: - The bin layout

    func testThereAreTenBins() {
        XCTAssertEqual(DoseBinning.orderedKinds.count, 10)
        XCTAssertEqual(bins([]).count, 10)
    }

    func testTheBinsAreBeforeFirstDoseThenEightHalfHoursThenFourHoursOrMore() {
        XCTAssertEqual(
            DoseBinning.orderedKinds,
            [.beforeFirstDose]
                + (0..<8).map { DoseBinKind.sinceDose(startMinutes: $0 * 30) }
                + [.fourHoursOrMore]
        )
    }

    func testTheBinsAreInXAxisOrder() {
        XCTAssertEqual(DoseBinning.orderedKinds.map(\.order), Array(0..<10))
        XCTAssertEqual(bins([]).map(\.id), Array(0..<10))
    }

    func testTheHalfHourBinsCoverZeroToFourHours() {
        let covered = DoseBinning.orderedKinds.compactMap { kind -> Int? in
            guard case .sinceDose(let start) = kind else { return nil }
            return start
        }
        XCTAssertEqual(covered, [0, 30, 60, 90, 120, 150, 180, 210])
        XCTAssertEqual(DoseBinning.longBinThresholdMinutes, 240)
    }

    func testEveryBinHasALabel() {
        for kind in DoseBinning.orderedKinds {
            XCTAssertFalse(kind.label.isEmpty)
        }
    }

    func testTheLabelsReadAsClockTimes() {
        XCTAssertEqual(DoseBinKind.beforeFirstDose.label, "Before 1st dose")
        XCTAssertEqual(DoseBinKind.sinceDose(startMinutes: 0).label, "0:00–0:30")
        XCTAssertEqual(DoseBinKind.sinceDose(startMinutes: 90).label, "1:30–2:00")
        XCTAssertEqual(DoseBinKind.sinceDose(startMinutes: 210).label, "3:30–4:00")
        XCTAssertEqual(DoseBinKind.fourHoursOrMore.label, "4h+")
    }

    // MARK: - Placing a session

    // No medication context means no dose was taken that day before the session. This is the
    // OFF-state data the wearing-off question depends on, so it gets its own bin rather than
    // being dropped.
    func testNoDoseContextGoesInTheBeforeFirstDoseBin() {
        XCTAssertEqual(DoseBinning.kind(forMinutesSinceDose: nil), .beforeFirstDose)
    }

    func testTheFirstHalfHourBinStartsAtZero() {
        XCTAssertEqual(DoseBinning.kind(forMinutesSinceDose: 0), .sinceDose(startMinutes: 0))
    }

    func testTwentyNineMinutesIsStillTheFirstBin() {
        XCTAssertEqual(DoseBinning.kind(forMinutesSinceDose: 29.99), .sinceDose(startMinutes: 0))
    }

    func testThirtyMinutesStartsTheSecondBin() {
        XCTAssertEqual(DoseBinning.kind(forMinutesSinceDose: 30), .sinceDose(startMinutes: 30))
    }

    func testJustUnderFourHoursIsTheLastHalfHourBin() {
        XCTAssertEqual(DoseBinning.kind(forMinutesSinceDose: 239.99), .sinceDose(startMinutes: 210))
    }

    func testExactlyFourHoursIsTheLongBin() {
        XCTAssertEqual(DoseBinning.kind(forMinutesSinceDose: 240), .fourHoursOrMore)
    }

    func testMoreThanFourHoursIsTheLongBin() {
        XCTAssertEqual(DoseBinning.kind(forMinutesSinceDose: 600), .fourHoursOrMore)
    }

    func testEveryHalfHourBoundaryLandsInItsOwnBin() {
        for step in 0..<8 {
            let start = Double(step * 30)
            XCTAssertEqual(
                DoseBinning.kind(forMinutesSinceDose: start),
                .sinceDose(startMinutes: step * 30),
                "\(start) minutes"
            )
        }
    }

    // The store only records a dose at or before the session start, so a negative value means
    // the row is wrong.
    func testANegativeValueCannotBePlaced() {
        XCTAssertNil(DoseBinning.kind(forMinutesSinceDose: -1))
    }

    func testANonFiniteValueCannotBePlaced() {
        XCTAssertNil(DoseBinning.kind(forMinutesSinceDose: .nan))
        XCTAssertNil(DoseBinning.kind(forMinutesSinceDose: .infinity))
    }

    func testAnUnplaceableSessionIsLeftOutOfEveryBin() {
        let result = bins([session(minutesSinceDose: -5)])
        XCTAssertEqual(result.map(\.sessionCount).reduce(0, +), 0)
    }

    // MARK: - Empty bins

    // A bin with no sessions still appears so the axis keeps its full width.
    func testBinsWithNoSessionsStillAppear() throws {
        let result = bins([session(minutesSinceDose: 45)])

        XCTAssertEqual(result.count, 10)
        let filled = try bin(result, .sinceDose(startMinutes: 30))
        XCTAssertEqual(filled.sessionCount, 1)

        let empty = try bin(result, .sinceDose(startMinutes: 120))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertNil(empty.median)
        XCTAssertNil(empty.stats)
        XCTAssertFalse(empty.hasWhisker)
    }

    // MARK: - Median and whisker

    // SummaryStats.compute returns nil below two values, so a one-session bin is drawn as a
    // bare point with no whisker.
    func testABinWithOneSessionHasAMedianButNoWhisker() throws {
        let result = bins([session(minutesSinceDose: 45, tapRate: 5)])
        let filled = try bin(result, .sinceDose(startMinutes: 30))

        XCTAssertEqual(try XCTUnwrap(filled.median), 5, accuracy: 1e-9)
        XCTAssertNil(filled.stats)
        XCTAssertFalse(filled.hasWhisker)
        XCTAssertNil(filled.p25)
        XCTAssertNil(filled.p75)
    }

    func testABinWithTwoSessionsHasAWhisker() throws {
        let sessions = [
            session(minutesSinceDose: 35, tapRate: 4, hour: 9),
            session(minutesSinceDose: 50, tapRate: 6, hour: 11)
        ]
        let filled = try bin(bins(sessions), .sinceDose(startMinutes: 30))

        XCTAssertEqual(filled.sessionCount, 2)
        XCTAssertEqual(try XCTUnwrap(filled.median), 5, accuracy: 1e-9)
        XCTAssertTrue(filled.hasWhisker)
        XCTAssertNotNil(filled.p25)
        XCTAssertNotNil(filled.p75)
    }

    func testTheWhiskerIsTheTwentyFifthToSeventyFifthPercentile() throws {
        let rates = [1.0, 2.0, 3.0, 4.0, 5.0]
        let sessions = rates.enumerated().map { index, rate in
            session(minutesSinceDose: 35, tapRate: rate, hour: 9 + index)
        }

        let filled = try bin(bins(sessions), .sinceDose(startMinutes: 30))
        let expected = try XCTUnwrap(SummaryStats.compute(rates))
        XCTAssertEqual(try XCTUnwrap(filled.p25), expected.p25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(filled.p75), expected.p75, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(filled.median), expected.median, accuracy: 1e-9)
    }

    // MARK: - Points

    func testEachPointCarriesItsSessionAndMinutesSinceDose() throws {
        let one = session(minutesSinceDose: 42, tapRate: 5)
        let filled = try bin(bins([one]), .sinceDose(startMinutes: 30))

        let point = try XCTUnwrap(filled.points.first)
        XCTAssertEqual(point.sessionId, one.id)
        XCTAssertEqual(try XCTUnwrap(point.minutesSinceDose), 42, accuracy: 1e-9)
        XCTAssertEqual(point.value, 5, accuracy: 1e-9)
    }

    func testABeforeFirstDosePointHasNoMinutesSinceDose() throws {
        let filled = try bin(bins([session(minutesSinceDose: nil)]), .beforeFirstDose)
        XCTAssertNil(try XCTUnwrap(filled.points.first).minutesSinceDose)
    }

    func testPointsInABinAreOldestFirst() throws {
        let sessions = [14, 9, 11].map { hour in
            session(minutesSinceDose: 35, hour: hour)
        }
        let filled = try bin(bins(sessions), .sinceDose(startMinutes: 30))

        XCTAssertEqual(filled.points.map(\.startedAt), filled.points.map(\.startedAt).sorted())
    }

    // MARK: - Hands and metrics

    func testOnlyTheRequestedHandIsBinned() throws {
        let both = ReportFixtures.session(
            dayOffset: 0,
            minutesSinceDose: 45,
            tapping: [
                ReportFixtures.tapping(hand: .right, numTaps: 100, durationSec: 20),
                ReportFixtures.tapping(hand: .left, numTaps: 60, durationSec: 20)
            ]
        )

        let right = try bin(bins([both], hand: .right), .sinceDose(startMinutes: 30))
        let left = try bin(bins([both], hand: .left), .sinceDose(startMinutes: 30))

        XCTAssertEqual(try XCTUnwrap(right.median), 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(left.median), 3, accuracy: 1e-9)
    }

    func testASessionWithNoResultForThatHandIsLeftOut() {
        let rightOnly = ReportFixtures.session(
            dayOffset: 0,
            minutesSinceDose: 45,
            tapping: [ReportFixtures.tapping(hand: .right)]
        )

        XCTAssertEqual(bins([rightOnly], hand: .left).map(\.sessionCount).reduce(0, +), 0)
    }

    func testAnotherPrimaryMetricCanBeBinned() throws {
        let one = ReportFixtures.session(
            dayOffset: 0,
            minutesSinceDose: 45,
            firefly: ReportFixtures.firefly(reactionTimeMedian: 0.35)
        )

        let result = DoseBinning.bins(sessions: [one], window: window, metric: .reactionTime, hand: .right)
        let filled = try bin(result, .sinceDose(startMinutes: 30))
        XCTAssertEqual(try XCTUnwrap(filled.median), 350, accuracy: 1e-9)
    }

    // MARK: - The window

    func testSessionsOutsideTheWindowAreDropped() {
        let sessions = [
            session(minutesSinceDose: 45, dayOffset: -1),
            session(minutesSinceDose: 45, dayOffset: 0),
            session(minutesSinceDose: 45, dayOffset: 7)
        ]

        XCTAssertEqual(bins(sessions).map(\.sessionCount).reduce(0, +), 1)
    }

    // Bins pool every day in the window, unlike DailyAggregate which keeps days apart.
    func testSessionsFromDifferentDaysShareABin() throws {
        let sessions = (0..<5).map { session(minutesSinceDose: 45, dayOffset: $0) }
        let filled = try bin(bins(sessions), .sinceDose(startMinutes: 30))
        XCTAssertEqual(filled.sessionCount, 5)
    }

    func testNoSessionsGivesTenEmptyBins() {
        let result = bins([])
        XCTAssertEqual(result.count, 10)
        XCTAssertTrue(result.allSatisfy(\.isEmpty))
    }

    // MARK: - The reading the chart supports

    // A rise from "before 1st dose" into the 30 to 90 minute bins suggests a dose response.
    func testAWearingOffPatternIsVisibleAcrossTheBins() throws {
        let sessions = [
            session(minutesSinceDose: nil, tapRate: 3, dayOffset: 0, hour: 7),
            session(minutesSinceDose: 45, tapRate: 6, dayOffset: 0, hour: 9),
            session(minutesSinceDose: 250, tapRate: 3.5, dayOffset: 0, hour: 13)
        ]
        let result = bins(sessions)

        let before = try XCTUnwrap(try bin(result, .beforeFirstDose).median)
        let after = try XCTUnwrap(try bin(result, .sinceDose(startMinutes: 30)).median)
        let late = try XCTUnwrap(try bin(result, .fourHoursOrMore).median)

        XCTAssertGreaterThan(after, before)
        XCTAssertLessThan(late, after)
    }
}
