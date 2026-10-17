import XCTest
@testable import Kinesia

final class PrimaryMetricTests: XCTestCase {

    // MARK: - Shape

    func testThereAreThreeMetrics() {
        XCTAssertEqual(PrimaryMetric.allCases, [.tapRate, .reactionTime, .tracingError])
    }

    func testEveryMetricHasAUnitLabel() {
        for metric in PrimaryMetric.allCases {
            XCTAssertFalse(metric.unitLabel.isEmpty, "\(metric)")
        }
    }

    func testTheUnitLabelsNameTheUnit() {
        XCTAssertEqual(PrimaryMetric.tapRate.unitLabel, "taps/sec")
        XCTAssertEqual(PrimaryMetric.reactionTime.unitLabel, "ms")
        XCTAssertEqual(PrimaryMetric.tracingError.unitLabel, "route units")
    }

    // Orients the baseline band and the trend line. Display only, never a judgement label.
    func testOnlyTapRateImprovesByRising() {
        XCTAssertTrue(PrimaryMetric.tapRate.higherIsBetter)
        XCTAssertFalse(PrimaryMetric.reactionTime.higherIsBetter)
        XCTAssertFalse(PrimaryMetric.tracingError.higherIsBetter)
    }

    // MARK: - Tap rate

    func testTapRateIsTapsOverSeconds() throws {
        let session = ReportFixtures.session(
            tapping: [ReportFixtures.tapping(numTaps: 100, durationSec: 20)]
        )
        XCTAssertEqual(try XCTUnwrap(PrimaryMetric.tapRate.value(session, hand: .right)), 5, accuracy: 1e-9)
    }

    func testTapRateReadsTheRequestedHand() throws {
        let session = ReportFixtures.session(
            tapping: [
                ReportFixtures.tapping(hand: .right, numTaps: 100, durationSec: 20),
                ReportFixtures.tapping(hand: .left, numTaps: 60, durationSec: 20)
            ]
        )
        XCTAssertEqual(try XCTUnwrap(PrimaryMetric.tapRate.value(session, hand: .right)), 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(PrimaryMetric.tapRate.value(session, hand: .left)), 3, accuracy: 1e-9)
    }

    func testTapRateIsNilForAHandWithNoResult() {
        let session = ReportFixtures.session(tapping: [ReportFixtures.tapping(hand: .right)])
        XCTAssertNil(PrimaryMetric.tapRate.value(session, hand: .left))
    }

    func testAZeroDurationGivesNilRatherThanInfinity() {
        let session = ReportFixtures.session(
            tapping: [ReportFixtures.tapping(numTaps: 100, durationSec: 0)]
        )
        XCTAssertNil(PrimaryMetric.tapRate.value(session, hand: .right))
    }

    // The counts are validated by the store separately from the statistics, so tap rate is a
    // real measurement on a row the statistics made invalid.
    func testTapRateSurvivesAnInvalidRow() throws {
        let session = ReportFixtures.session(
            tapping: [
                ReportFixtures.tapping(
                    numTaps: 100,
                    durationSec: 20,
                    tapInterMedian: nil,
                    cvTapInter: nil,
                    tapInterSlope: nil,
                    isValid: false
                )
            ]
        )
        XCTAssertEqual(try XCTUnwrap(PrimaryMetric.tapRate.value(session, hand: .right)), 5, accuracy: 1e-9)
    }

    // MARK: - Reaction time

    // Stored in seconds; the chart axis is in milliseconds. This is the only place it converts.
    func testReactionTimeConvertsSecondsToMilliseconds() throws {
        let session = ReportFixtures.session(firefly: ReportFixtures.firefly(reactionTimeMedian: 0.348))
        XCTAssertEqual(
            try XCTUnwrap(PrimaryMetric.reactionTime.value(session, hand: .right)),
            348,
            accuracy: 1e-9
        )
    }

    func testReactionTimeIsNilWithoutAFireflyResult() {
        let session = ReportFixtures.session(firefly: nil)
        XCTAssertNil(PrimaryMetric.reactionTime.value(session, hand: .right))
    }

    func testReactionTimeIsNilForTheOtherHand() {
        let session = ReportFixtures.session(firefly: ReportFixtures.firefly(hand: .right))
        XCTAssertNil(PrimaryMetric.reactionTime.value(session, hand: .left))
    }

    // An invalid row reaches the snapshot with nil statistics, so the metric is unavailable
    // rather than zero.
    func testReactionTimeIsNilWhenTheRowWasInvalid() {
        let session = ReportFixtures.session(
            firefly: ReportFixtures.firefly(reactionTimeMedian: nil, isValid: false)
        )
        XCTAssertNil(PrimaryMetric.reactionTime.value(session, hand: .right))
    }

    // MARK: - Tracing error

    func testTracingErrorReadsRmsErrorInRouteUnits() throws {
        let session = ReportFixtures.session(tracing: ReportFixtures.tracing(rmsError: 3.4))
        XCTAssertEqual(
            try XCTUnwrap(PrimaryMetric.tracingError.value(session, hand: .right)),
            3.4,
            accuracy: 1e-9
        )
    }

    func testTracingErrorIsNilWithoutATracingResult() {
        XCTAssertNil(PrimaryMetric.tracingError.value(ReportFixtures.session(tracing: nil), hand: .right))
    }

    func testTracingErrorIsNilWhenTheRowWasInvalid() {
        let session = ReportFixtures.session(tracing: ReportFixtures.tracing(rmsError: nil, isValid: false))
        XCTAssertNil(PrimaryMetric.tracingError.value(session, hand: .right))
    }

    // MARK: - Identity

    func testEachMetricHasItsOwnRawValueAndId() {
        let ids = PrimaryMetric.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(PrimaryMetric.tapRate.id, PrimaryMetric.tapRate.rawValue)
    }
}
