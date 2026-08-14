import XCTest
@testable import Kinesia

@MainActor
final class BradykinesiaAnalyzerTests: XCTestCase {
    func testTapIntervalsForRegularTapping() throws {
        let intervals = try XCTUnwrap(BradykinesiaAnalyzer.tapIntervals(from: samples([0, 0.5, 1, 1.5, 2])))
        XCTAssertEqual(intervals.count, 4)
        intervals.forEach { XCTAssertEqual($0, 0.5, accuracy: 0.000_001) }
    }

    func testTapIntervalsForIrregularTapping() throws {
        let intervals = try XCTUnwrap(BradykinesiaAnalyzer.tapIntervals(from: samples([0, 0.25, 0.75, 1.5])))
        XCTAssertEqual(intervals, [0.25, 0.5, 0.75])
    }

    func testTapIntervalsForZeroTapsAreEmpty() throws {
        XCTAssertEqual(try XCTUnwrap(BradykinesiaAnalyzer.tapIntervals(from: [])), [])
    }

    func testTapIntervalsForOneTapAreEmpty() throws {
        XCTAssertEqual(try XCTUnwrap(BradykinesiaAnalyzer.tapIntervals(from: samples([0]))), [])
    }

    func testTapIntervalsForTwoTapsContainOneInterval() throws {
        XCTAssertEqual(try XCTUnwrap(BradykinesiaAnalyzer.tapIntervals(from: samples([0, 0.5]))), [0.5])
    }

    func testTapIntervalsRejectRepeatedTimestampWithoutDroppingIt() {
        XCTAssertNil(BradykinesiaAnalyzer.tapIntervals(from: samples([0, 0.5, 0.5, 1])))
    }

    func testTapIntervalsRejectBackwardsTimestampWithoutSorting() {
        XCTAssertNil(BradykinesiaAnalyzer.tapIntervals(from: samples([0, 1, 0.75])))
    }

    func testTapIntervalsRejectNonFiniteTimestamp() {
        XCTAssertNil(BradykinesiaAnalyzer.tapIntervals(from: samples([0, .nan, 1])))
    }

    func testAnalyzeRegularTrial() throws {
        let metrics = BradykinesiaAnalyzer.analyze(trial(timestamps: [0, 0.5, 1, 1.5, 2]))
        let stats = try XCTUnwrap(metrics.tapInterStats)

        XCTAssertEqual(metrics.numTaps, 5)
        XCTAssertEqual(metrics.tapIntervals, [0.5, 0.5, 0.5, 0.5])
        XCTAssertEqual(stats.min, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.max, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.mean, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.median, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.stdev, 0, accuracy: 0.000_001)
        let coefficientOfVariation = try XCTUnwrap(metrics.cvTapInter)
        XCTAssertEqual(coefficientOfVariation, 0, accuracy: 0.000_001)
        XCTAssertNil(metrics.skewTapInter)
        XCTAssertNil(metrics.numCorrectTaps)
    }

    func testAnalyzeIrregularTrial() throws {
        let metrics = BradykinesiaAnalyzer.analyze(trial(timestamps: [0, 0.25, 0.75, 1.5]))
        let stats = try XCTUnwrap(metrics.tapInterStats)

        XCTAssertEqual(metrics.tapIntervals, [0.25, 0.5, 0.75])
        XCTAssertEqual(stats.mean, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.median, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.stdev, 0.25, accuracy: 0.000_001)
        let coefficientOfVariation = try XCTUnwrap(metrics.cvTapInter)
        let skewness = try XCTUnwrap(metrics.skewTapInter)
        XCTAssertEqual(coefficientOfVariation, sqrt(2.0 / 3.0) / 2 * 100, accuracy: 0.000_001)
        XCTAssertEqual(skewness, 0, accuracy: 0.000_001)
    }

    func testAnalyzeInsufficientTapCounts() {
        let zeroTapMetrics = BradykinesiaAnalyzer.analyze(trial(timestamps: []))
        XCTAssertEqual(zeroTapMetrics.numTaps, 0)
        XCTAssertEqual(zeroTapMetrics.tapIntervals, [])
        XCTAssertNil(zeroTapMetrics.tapInterStats)
        XCTAssertNil(zeroTapMetrics.cvTapInter)
        XCTAssertNil(zeroTapMetrics.skewTapInter)

        let oneTapMetrics = BradykinesiaAnalyzer.analyze(trial(timestamps: [0]))
        XCTAssertEqual(oneTapMetrics.numTaps, 1)
        XCTAssertEqual(oneTapMetrics.tapIntervals, [])
        XCTAssertNil(oneTapMetrics.tapInterStats)
        XCTAssertNil(oneTapMetrics.cvTapInter)
        XCTAssertNil(oneTapMetrics.skewTapInter)

        let twoTapMetrics = BradykinesiaAnalyzer.analyze(trial(timestamps: [0, 0.5]))
        XCTAssertEqual(twoTapMetrics.numTaps, 2)
        XCTAssertEqual(twoTapMetrics.tapIntervals, [0.5])
        XCTAssertNil(twoTapMetrics.tapInterStats)
        XCTAssertNil(twoTapMetrics.cvTapInter)
        XCTAssertNil(twoTapMetrics.skewTapInter)
    }

    func testAnalyzeInvalidTimestampsPreservesTapCountAndMakesTemporalMetricsUnavailable() {
        let sourceSamples = samples([0, 0.5, 0.5, 1])
        let metrics = BradykinesiaAnalyzer.analyze(trial(samples: sourceSamples))

        XCTAssertEqual(metrics.numTaps, sourceSamples.count)
        XCTAssertNil(metrics.tapIntervals)
        XCTAssertNil(metrics.tapInterStats)
        XCTAssertNil(metrics.cvTapInter)
        XCTAssertNil(metrics.skewTapInter)
    }

    private func samples(_ timestamps: [TimeInterval]) -> [TapSample] {
        timestamps.enumerated().map { index, timestamp in
            TapSample(t: timestamp, x: Double(index), y: 0, target: .left)
        }
    }

    private func trial(timestamps: [TimeInterval]) -> TapTrial {
        trial(samples: samples(timestamps))
    }

    private func trial(samples: [TapSample]) -> TapTrial {
        TapTrial(
            samples: samples,
            leftCenter: TapPoint(x: 10, y: 20),
            rightCenter: TapPoint(x: 30, y: 20),
            targetRadius: 15,
            startedAt: 0,
            hand: "right",
            screenScale: 3
        )
    }
}
