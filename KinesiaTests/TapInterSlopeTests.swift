import XCTest
@testable import Kinesia

/// The decrement measure: OLS slope of tap interval against tap index.
final class TapInterSlopeTests: XCTestCase {

    // MARK: - Arithmetic

    func testAFlatSequenceHasZeroSlope() throws {
        let slope = try XCTUnwrap(BradykinesiaAnalyzer.tapInterSlope([0.2, 0.2, 0.2, 0.2, 0.2]))
        XCTAssertEqual(slope, 0, accuracy: 1e-12)
    }

    /// Intervals lengthening by a fixed step per tap is exactly that step.
    func testAPerfectlyLinearRiseRecoversTheStep() throws {
        let intervals = (0..<10).map { 0.2 + Double($0) * 0.01 }
        let slope = try XCTUnwrap(BradykinesiaAnalyzer.tapInterSlope(intervals))
        XCTAssertEqual(slope, 0.01, accuracy: 1e-12)
    }

    func testSpeedingUpGivesANegativeSlope() throws {
        let intervals = (0..<10).map { 0.4 - Double($0) * 0.02 }
        let slope = try XCTUnwrap(BradykinesiaAnalyzer.tapInterSlope(intervals))
        XCTAssertEqual(slope, -0.02, accuracy: 1e-12)
    }

    /// Hand-checked: x = 0,1,2, y = 1,2,4. Sxy = 3, Sxx = 2, slope = 1.5.
    func testAKnownThreePointFit() throws {
        let slope = try XCTUnwrap(BradykinesiaAnalyzer.tapInterSlope([1, 2, 4]))
        XCTAssertEqual(slope, 1.5, accuracy: 1e-12)
    }

    /// A symmetric spike in the middle leaves the trend flat: the slope is a trend measure, not
    /// a hesitation detector. Hesitations are visible in the within-session interval chart.
    func testASymmetricSpikeDoesNotTiltTheSlope() throws {
        let slope = try XCTUnwrap(BradykinesiaAnalyzer.tapInterSlope([0.2, 0.2, 0.9, 0.2, 0.2]))
        XCTAssertEqual(slope, 0, accuracy: 1e-12)
    }

    /// The regressor is tap index, not elapsed time, so a longer capture of the same behaviour
    /// reports the same decrement per tap.
    func testTheSlopeIsPerTapNotPerSecond() throws {
        let short = try XCTUnwrap(BradykinesiaAnalyzer.tapInterSlope((0..<5).map { 0.2 + Double($0) * 0.01 }))
        let long = try XCTUnwrap(BradykinesiaAnalyzer.tapInterSlope((0..<40).map { 0.2 + Double($0) * 0.01 }))
        XCTAssertEqual(short, long, accuracy: 1e-12)
    }

    // MARK: - Unavailability

    func testFewerThanThreeIntervalsIsUnavailable() {
        XCTAssertNil(BradykinesiaAnalyzer.tapInterSlope([]))
        XCTAssertNil(BradykinesiaAnalyzer.tapInterSlope([0.2]))
        XCTAssertNil(BradykinesiaAnalyzer.tapInterSlope([0.2, 0.3]))
    }

    func testExactlyThreeIntervalsIsAvailable() {
        XCTAssertNotNil(BradykinesiaAnalyzer.tapInterSlope([0.2, 0.3, 0.4]))
    }

    func testANonFiniteIntervalMakesTheSlopeUnavailable() {
        XCTAssertNil(BradykinesiaAnalyzer.tapInterSlope([0.2, .nan, 0.4]))
        XCTAssertNil(BradykinesiaAnalyzer.tapInterSlope([0.2, .infinity, 0.4]))
    }

    // MARK: - Through the analyzer

    private func trial(intervals: [Double]) -> TapTrial {
        var t = 100.0
        var samples: [TapSample] = [TapSample(t: t, x: 100, y: 100, target: .right)]
        for (index, interval) in intervals.enumerated() {
            t += interval
            samples.append(
                TapSample(t: t, x: index.isMultiple(of: 2) ? 200 : 100, y: 100, target: index.isMultiple(of: 2) ? .left : .right)
            )
        }
        return TapTrial(
            samples: samples,
            leftCenter: TapPoint(x: 100, y: 100),
            rightCenter: TapPoint(x: 200, y: 100),
            targetRadius: 40,
            startedAt: 100,
            hand: .right,
            screenScale: 3
        )
    }

    func testAnalyzeCarriesTheSlopeOnTheMetricBundle() throws {
        let metrics = BradykinesiaAnalyzer.analyze(trial(intervals: (0..<10).map { 0.2 + Double($0) * 0.01 }))
        let slope = try XCTUnwrap(metrics.tapInterSlope)
        XCTAssertEqual(slope, 0.01, accuracy: 1e-9)
    }

    func testAnalyzeLeavesTheSlopeUnavailableForTooFewTaps() {
        let metrics = BradykinesiaAnalyzer.analyze(trial(intervals: [0.2, 0.3]))
        XCTAssertNil(metrics.tapInterSlope)
    }

    func testTheSlopeMatchesTheIntervalsTheAnalyzerItselfDerived() throws {
        let metrics = BradykinesiaAnalyzer.analyze(trial(intervals: [0.2, 0.25, 0.3, 0.35]))
        let intervals = try XCTUnwrap(metrics.tapIntervals)
        let expected = try XCTUnwrap(BradykinesiaAnalyzer.tapInterSlope(intervals))
        XCTAssertEqual(try XCTUnwrap(metrics.tapInterSlope), expected, accuracy: 1e-12)
    }

    func testMetricsVersionIsStamped() {
        XCTAssertEqual(BradykinesiaMetrics.metricsVersion, 1)
        XCTAssertEqual(DexterityMetrics.metricsVersion, 1)
    }
}
