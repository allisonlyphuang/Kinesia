import XCTest
@testable import Kinesia

/// The analyzer is pure: it takes a decoded trial and returns a metric bundle, with no UI,
/// no clock and no database. Every test here builds rounds with exact timestamps and asserts
/// on the numbers that come out.
final class AkinesiaAnalyzerTests: XCTestCase {

    // MARK: - Fixtures

    /// A round the capture layer saw through to a catch. Timestamps are monotonic seconds, so
    /// a reaction time of 0.30 s and a movement time of 0.25 s here.
    private func completedRound(
        index: Int = 0,
        isPractice: Bool = false,
        cueOnsetAt: TimeInterval? = 10.0,
        liftOffAt: TimeInterval? = 10.3,
        catchAt: TimeInterval? = 10.55,
        returnedHomeAt: TimeInterval? = 10.9,
        scoredOutcome: ScoredOutcome = .valid
    ) -> RoundRecord {
        RoundRecord(
            index: index,
            isPractice: isPractice,
            homeSettledAt: 8.0,
            plannedForeperiod: 2.0,
            cueOnsetAt: cueOnsetAt,
            liftOffAt: liftOffAt,
            catchAt: catchAt,
            returnedHomeAt: returnedHomeAt,
            spawn: SpawnPoint(x: 150, y: 50),
            captureOutcome: .completed,
            scoredOutcome: scoredOutcome
        )
    }

    /// A round the capture layer rejected before any interval could be measured.
    private func abortedRound(
        index: Int = 0,
        isPractice: Bool = false,
        captureOutcome: CaptureOutcome
    ) -> RoundRecord {
        RoundRecord(
            index: index,
            isPractice: isPractice,
            homeSettledAt: 8.0,
            plannedForeperiod: 2.0,
            cueOnsetAt: captureOutcome == .missed ? 10.0 : nil,
            liftOffAt: captureOutcome == .missed ? nil : 9.5,
            catchAt: nil,
            returnedHomeAt: 12.0,
            spawn: captureOutcome == .missed ? SpawnPoint(x: 150, y: 50) : nil,
            captureOutcome: captureOutcome,
            scoredOutcome: .valid
        )
    }

    /// A round with a chosen reaction time, used for the threshold boundaries.
    private func round(reactionTime: TimeInterval, movementTime: TimeInterval = 0.25, index: Int = 0) -> RoundRecord {
        completedRound(
            index: index,
            cueOnsetAt: 10.0,
            liftOffAt: 10.0 + reactionTime,
            catchAt: 10.0 + reactionTime + movementTime
        )
    }

    /// A round whose reaction time is *exactly* the value asked for.
    ///
    /// The helper above builds `liftOffAt` by adding to a realistic cue timestamp, and binary
    /// floating point does not round-trip that: `(10.0 + 0.120) - 10.0` is `0.11999999999999922`,
    /// which really is below a 0.120 ceiling. Anchoring the cue at zero makes the subtraction
    /// exact, so a boundary test measures the comparison operator rather than float error.
    /// Real timestamps carry the same imprecision, but a genuine reaction time landing within
    /// 1e-16 of a threshold is not a distinction the test can or should defend.
    private func exactRound(reactionTime: TimeInterval, index: Int = 0) -> RoundRecord {
        completedRound(
            index: index,
            cueOnsetAt: 0,
            liftOffAt: reactionTime,
            catchAt: reactionTime + 0.25
        )
    }

    private func trial(_ rounds: [RoundRecord]) -> AkinesiaTrial {
        AkinesiaTrial(
            rounds: rounds,
            homeBaseCenter: SpawnPoint(x: 150, y: 150),
            homeBaseRadius: 40,
            fireflyRadius: 30,
            hand: .right,
            digit: "index",
            screenScale: 3,
            refreshRateHz: 120,
            cueModality: "visual",
            startedAt: 5.0,
            spawnRing: SpawnRing(
                center: TapPoint(x: 150, y: 150),
                radius: 100,
                tolerance: 8,
                arcStart: 0,
                arcEnd: 2 * .pi
            )
        )
    }

    /// Enough valid rounds to clear `minimumValidRounds`, with reaction times spread so the
    /// median and MAD are not degenerate.
    private func validRounds(count: Int = 9) -> [RoundRecord] {
        (0..<count).map { index in
            round(reactionTime: 0.30 + Double(index) * 0.01, index: index)
        }
    }

    // MARK: - Interval arithmetic

    func testReactionTimeIsCueOnsetToLiftOffAndMovementTimeIsLiftOffToCatch() throws {
        let scored = AkinesiaAnalyzer.score(completedRound())

        XCTAssertEqual(scored.outcome, .valid)
        XCTAssertEqual(try XCTUnwrap(scored.reactionTime), 0.30, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(scored.movementTime), 0.25, accuracy: 0.000_001)
    }

    func testRawIntervalsAreAvailableEvenWhenTheRoundIsRejected() throws {
        // A lapse still has a measurable interval; it is just not admitted into the statistics.
        let lapsed = round(reactionTime: 2.5)

        XCTAssertEqual(AkinesiaAnalyzer.score(lapsed).outcome, .lapse)
        XCTAssertNil(AkinesiaAnalyzer.score(lapsed).reactionTime)
        XCTAssertEqual(try XCTUnwrap(AkinesiaAnalyzer.rawReactionTime(of: lapsed)), 2.5, accuracy: 0.000_001)
    }

    // MARK: - Thresholds

    func testAnticipationBoundaryIsExclusiveSoARoundAtTheCeilingIsValid() {
        XCTAssertEqual(AkinesiaAnalyzer.score(exactRound(reactionTime: 0.119)).outcome, .anticipation)
        XCTAssertEqual(AkinesiaAnalyzer.score(exactRound(reactionTime: 0.120)).outcome, .valid)
        XCTAssertEqual(AkinesiaAnalyzer.score(exactRound(reactionTime: 0.121)).outcome, .valid)
    }

    func testLapseBoundaryIsExclusiveSoARoundAtTheFloorIsValid() {
        XCTAssertEqual(AkinesiaAnalyzer.score(exactRound(reactionTime: 1.999)).outcome, .valid)
        XCTAssertEqual(AkinesiaAnalyzer.score(exactRound(reactionTime: 2.000)).outcome, .valid)
        XCTAssertEqual(AkinesiaAnalyzer.score(exactRound(reactionTime: 2.001)).outcome, .lapse)
    }

    func testThresholdsAreInjectableSoTheSameRoundCanBeRescored() {
        let strict = AkinesiaThresholds(anticipationCeiling: 0.400, lapseFloor: 0.500, minimumValidRounds: 1)
        let quick = round(reactionTime: 0.30)

        XCTAssertEqual(AkinesiaAnalyzer.score(quick).outcome, .valid)
        XCTAssertEqual(AkinesiaAnalyzer.score(quick, thresholds: strict).outcome, .anticipation)
    }

    // MARK: - Capture outcomes

    func testCaptureOutcomesPassThroughWithoutIntervals() {
        for (capture, expected) in [
            (CaptureOutcome.falseStart, ScoredOutcome.falseStart),
            (CaptureOutcome.slip, ScoredOutcome.slip),
            (CaptureOutcome.missed, ScoredOutcome.missed)
        ] {
            let scored = AkinesiaAnalyzer.score(abortedRound(captureOutcome: capture))
            XCTAssertEqual(scored.outcome, expected)
            XCTAssertNil(scored.reactionTime, "\(capture) must not contribute a reaction time")
            XCTAssertNil(scored.movementTime, "\(capture) must not contribute a movement time")
        }
    }

    // MARK: - Malformed rounds

    func testCompletedRoundsWithUnusableTimestampsAreMalformedNotMissed() {
        // Each of these claims to be completed but cannot yield an interval.
        let cases: [(String, RoundRecord)] = [
            ("missing cue onset", completedRound(cueOnsetAt: nil)),
            ("missing lift-off", completedRound(liftOffAt: nil)),
            ("NaN cue onset", completedRound(cueOnsetAt: .nan)),
            ("infinite lift-off", completedRound(liftOffAt: .infinity)),
            ("lift-off before the cue", completedRound(cueOnsetAt: 10.0, liftOffAt: 9.8)),
            ("lift-off exactly at the cue", completedRound(cueOnsetAt: 10.0, liftOffAt: 10.0))
        ]

        for (label, record) in cases {
            XCTAssertEqual(AkinesiaAnalyzer.score(record).outcome, .malformed, label)
        }

        // The point of the separate case: a data fault never inflates the initiation-failure count.
        let metrics = AkinesiaAnalyzer.analyze(trial([completedRound(cueOnsetAt: nil)]))
        XCTAssertEqual(metrics.numMalformed, 1)
        XCTAssertEqual(metrics.numMissed, 0)
    }

    func testAValidRoundWithoutACatchTimestampStillReportsItsReactionTime() throws {
        // Movement time is a by-product; losing it must not cost the akinesia measurement.
        let scored = AkinesiaAnalyzer.score(completedRound(catchAt: nil))

        XCTAssertEqual(scored.outcome, .valid)
        XCTAssertEqual(try XCTUnwrap(scored.reactionTime), 0.30, accuracy: 0.000_001)
        XCTAssertNil(scored.movementTime)
    }

    // MARK: - Practice rounds

    func testPracticeRoundsAreCountedButNeverScored() {
        let rounds = [
            completedRound(index: 0, isPractice: true, liftOffAt: 10.05),   // would be an anticipation
            completedRound(index: 1, isPractice: true, liftOffAt: 13.0),    // would be a lapse
            abortedRound(index: 2, isPractice: true, captureOutcome: .falseStart)
        ] + validRounds(count: 9)

        let metrics = AkinesiaAnalyzer.analyze(trial(rounds))

        XCTAssertEqual(metrics.numPracticeRounds, 3)
        XCTAssertEqual(metrics.numRounds, 9, "practice rounds are not scored rounds")
        XCTAssertEqual(metrics.numValidRounds, 9)
        XCTAssertEqual(metrics.numAnticipations, 0)
        XCTAssertEqual(metrics.numLapses, 0)
        XCTAssertEqual(metrics.numFalseStarts, 0)
        XCTAssertEqual(metrics.reactionTimes?.count, 9)
    }

    // MARK: - Session-level counts

    func testEveryScoredRoundLandsInExactlyOneCount() {
        let rounds: [RoundRecord] = [
            round(reactionTime: 0.30, index: 0),
            round(reactionTime: 0.35, index: 1),
            round(reactionTime: 0.05, index: 2),                        // anticipation
            round(reactionTime: 3.0, index: 3),                         // lapse
            abortedRound(index: 4, captureOutcome: .falseStart),
            abortedRound(index: 5, captureOutcome: .slip),
            abortedRound(index: 6, captureOutcome: .missed),
            completedRound(index: 7, cueOnsetAt: nil),                  // malformed
            completedRound(index: 8, isPractice: true)                  // not scored at all
        ]

        let metrics = AkinesiaAnalyzer.analyze(trial(rounds))
        let sum = metrics.numValidRounds + metrics.numAnticipations + metrics.numLapses
            + metrics.numFalseStarts + metrics.numSlips + metrics.numMissed + metrics.numMalformed

        XCTAssertEqual(metrics.numRounds, 8)
        XCTAssertEqual(metrics.numPracticeRounds, 1)
        XCTAssertEqual(sum, metrics.numRounds, "counts must partition the scored rounds")
        XCTAssertEqual(metrics.numValidRounds, 2)
        XCTAssertEqual(metrics.numAnticipations, 1)
        XCTAssertEqual(metrics.numLapses, 1)
        XCTAssertEqual(metrics.numFalseStarts, 1)
        XCTAssertEqual(metrics.numSlips, 1)
        XCTAssertEqual(metrics.numMissed, 1)
        XCTAssertEqual(metrics.numMalformed, 1)
    }

    func testOnlyValidRoundsContributeIntervalsAndOrderIsPreserved() throws {
        let rounds: [RoundRecord] = [
            round(reactionTime: 0.40, index: 0),
            round(reactionTime: 0.05, index: 1),   // anticipation, contributes nothing
            round(reactionTime: 0.20, index: 2),
            round(reactionTime: 5.00, index: 3),   // lapse, contributes nothing
            round(reactionTime: 0.30, index: 4)
        ]

        let reactionTimes = try XCTUnwrap(AkinesiaAnalyzer.analyze(trial(rounds)).reactionTimes)

        XCTAssertEqual(reactionTimes.count, 3)
        XCTAssertEqual(reactionTimes[0], 0.40, accuracy: 0.000_001)
        XCTAssertEqual(reactionTimes[1], 0.20, accuracy: 0.000_001)
        XCTAssertEqual(reactionTimes[2], 0.30, accuracy: 0.000_001)
    }

    func testTheAnalyzerRecomputesOutcomesAndIgnoresAnyStoredVerdict() {
        // A stored verdict is only the verdict under one set of thresholds. Trusting it would
        // make the thresholds impossible to revise.
        let mislabelled = completedRound(liftOffAt: 10.05, scoredOutcome: .valid) // really 0.05 s
        XCTAssertEqual(AkinesiaAnalyzer.score(mislabelled).outcome, .anticipation)

        let alsoMislabelled = completedRound(scoredOutcome: .lapse)               // really 0.30 s
        XCTAssertEqual(AkinesiaAnalyzer.score(alsoMislabelled).outcome, .valid)
    }

    // MARK: - Statistics gate

    func testBelowTheMinimumValidRoundsStatisticsAreUnavailableButCountsSurvive() throws {
        let metrics = AkinesiaAnalyzer.analyze(trial(validRounds(count: 7)))

        XCTAssertEqual(metrics.numValidRounds, 7)
        XCTAssertEqual(try XCTUnwrap(metrics.reactionTimes).count, 7, "raw intervals are still reported")
        XCTAssertNil(metrics.reactionTimeStats)
        XCTAssertNil(metrics.movementTimeStats)
    }

    func testAtTheMinimumValidRoundsStatisticsAreProduced() throws {
        let metrics = AkinesiaAnalyzer.analyze(trial(validRounds(count: 8)))
        let stats = try XCTUnwrap(metrics.reactionTimeStats)

        XCTAssertEqual(metrics.numValidRounds, 8)
        // Reaction times run 0.30, 0.31, ... 0.37; the median falls between 0.33 and 0.34.
        XCTAssertEqual(stats.median, 0.335, accuracy: 0.000_001)
        XCTAssertEqual(stats.min, 0.30, accuracy: 0.000_001)
        XCTAssertEqual(stats.max, 0.37, accuracy: 0.000_001)
    }

    func testMovementTimeIsKeptOutOfTheReactionTimeStatistics() throws {
        // Movement times here are ten times the reaction times, so pooling the two series would
        // move the reaction-time median far off 0.34.
        let rounds = (0..<9).map { index in
            round(reactionTime: 0.30 + Double(index) * 0.01, movementTime: 3.0, index: index)
        }

        let metrics = AkinesiaAnalyzer.analyze(trial(rounds))
        let reactionStats = try XCTUnwrap(metrics.reactionTimeStats)
        let movementStats = try XCTUnwrap(metrics.movementTimeStats)

        XCTAssertEqual(reactionStats.median, 0.34, accuracy: 0.000_001)
        XCTAssertEqual(movementStats.median, 3.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.reactionTimes).count, 9)
        XCTAssertEqual(try XCTUnwrap(metrics.movementTimes).count, 9)
    }

    func testMovementTimesCanBeShorterThanReactionTimesWithoutBlockingStatistics() throws {
        // Eight clean rounds plus one that lost its catch timestamp: nine reaction times, eight
        // movement times, and both series still clear the minimum.
        var rounds = validRounds(count: 8)
        rounds.append(completedRound(index: 8, catchAt: nil))

        let metrics = AkinesiaAnalyzer.analyze(trial(rounds))

        XCTAssertEqual(metrics.numValidRounds, 9)
        XCTAssertEqual(try XCTUnwrap(metrics.reactionTimes).count, 9)
        XCTAssertEqual(try XCTUnwrap(metrics.movementTimes).count, 8)
        XCTAssertNotNil(metrics.reactionTimeStats)
        XCTAssertNotNil(metrics.movementTimeStats)
    }

    // MARK: - Degenerate sessions

    func testAnEmptyTrialProducesZeroCountsAndNoStatistics() throws {
        let metrics = AkinesiaAnalyzer.analyze(trial([]))

        XCTAssertEqual(metrics.numRounds, 0)
        XCTAssertEqual(metrics.numPracticeRounds, 0)
        XCTAssertEqual(metrics.numValidRounds, 0)
        XCTAssertEqual(try XCTUnwrap(metrics.reactionTimes), [])
        XCTAssertEqual(try XCTUnwrap(metrics.movementTimes), [])
        XCTAssertNil(metrics.reactionTimeStats)
        XCTAssertNil(metrics.movementTimeStats)
    }

    func testASessionOfNothingButFailuresReportsThemWithoutStatistics() throws {
        let rounds = [
            abortedRound(index: 0, captureOutcome: .falseStart),
            abortedRound(index: 1, captureOutcome: .slip),
            abortedRound(index: 2, captureOutcome: .missed)
        ]

        let metrics = AkinesiaAnalyzer.analyze(trial(rounds))

        XCTAssertEqual(metrics.numRounds, 3)
        XCTAssertEqual(metrics.numValidRounds, 0)
        XCTAssertEqual(try XCTUnwrap(metrics.reactionTimes), [])
        XCTAssertNil(metrics.reactionTimeStats)
    }
}
