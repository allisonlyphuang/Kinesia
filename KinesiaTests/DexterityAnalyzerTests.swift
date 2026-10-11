import XCTest
@testable import Kinesia

@MainActor
final class DexterityAnalyzerTests: XCTestCase {
    func testPointToSegmentDistanceHandlesLineOffsetEndpointAndDegeneratePrimitive() throws {
        let start = DexterityRoutePoint(x: 0, y: 0)
        let end = DexterityRoutePoint(x: 10, y: 0)

        XCTAssertEqual(try XCTUnwrap(DexterityAnalyzer.distance(from: .init(x: 5, y: 0), toSegmentFrom: start, to: end)), 0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(DexterityAnalyzer.distance(from: .init(x: 5, y: 3), toSegmentFrom: start, to: end)), 3, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(DexterityAnalyzer.distance(from: .init(x: 13, y: 4), toSegmentFrom: start, to: end)), 5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(DexterityAnalyzer.distance(from: .init(x: 5, y: 6), toSegmentFrom: .init(x: 2, y: 2), to: .init(x: 2, y: 2))), 5, accuracy: 0.000_001)
    }

    func testCoordinateSpaceRoundTripsCanonicalPoints() throws {
        let space = DexterityCoordinateSpace(captureWidth: 200, captureHeight: 300, scale: 2, offsetX: 10, offsetY: 20)
        let canonical = DexterityRoutePoint(x: 4, y: 6)
        let local = try XCTUnwrap(space.localPoint(from: canonical))
        let recovered = try XCTUnwrap(space.canonicalPoint(localX: local.x, localY: local.y))

        XCTAssertEqual(local.x, 18, accuracy: 0.000_001)
        XCTAssertEqual(local.y, 32, accuracy: 0.000_001)
        XCTAssertEqual(recovered, canonical)
    }

    func testExactLineHasZeroRMSE() throws {
        let metrics = DexterityAnalyzer.analyze(trial(samples: [
            sample(t: 0, x: 0, y: 0), sample(t: 1, x: 5, y: 0), sample(t: 2, x: 10, y: 0)
        ]))

        XCTAssertEqual(try XCTUnwrap(metrics.rmsError), 0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.maxPointError), 0, accuracy: 0.000_001)
    }

    func testParallelOffsetHasKnownRMSEAndMaximumError() throws {
        let metrics = DexterityAnalyzer.analyze(trial(samples: [
            sample(t: 0, x: 0, y: 3), sample(t: 1, x: 5, y: 3), sample(t: 2, x: 10, y: 3)
        ]))

        XCTAssertEqual(try XCTUnwrap(metrics.rmsError), 3, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.maxPointError), 3, accuracy: 0.000_001)
    }

    func testDegenerateRouteIsRejectedEvenThoughTheDistancePrimitiveIsDefined() throws {
        let route = DexterityRoute(identifier: "degenerate", version: 1, points: [.init(x: 2, y: 2), .init(x: 2, y: 2)])
        let metrics = DexterityAnalyzer.analyze(trial(route: route, samples: [sample(t: 0, x: 2, y: 2)]))

        XCTAssertFalse(DexterityAnalyzer.isCalculationValid(route: route))
        XCTAssertNil(metrics.rmsError)
        XCTAssertTrue(try XCTUnwrap(metrics.calculationInvalidReason).contains("route is invalid"))
    }

    func testSelfIntersectingRouteUsesCapturedOrderedSegmentInsteadOfGlobalNearestSegment() throws {
        let route = DexterityRoute(
            identifier: "crossing",
            version: 1,
            points: [.init(x: 0, y: 0), .init(x: 10, y: 10), .init(x: 0, y: 10), .init(x: 10, y: 0)]
        )
        let metrics = DexterityAnalyzer.analyze(trial(route: route, samples: [sample(t: 0, x: 7, y: 6, segmentIndex: 2)]))

        XCTAssertEqual(try XCTUnwrap(metrics.rmsError), 3 / sqrt(2), accuracy: 0.000_001)
        XCTAssertGreaterThan(try XCTUnwrap(metrics.rmsError), 1)
    }

    func testConstantSpeedUsesSampleSDAndZeroCV() throws {
        let metrics = DexterityAnalyzer.analyze(trial(samples: [
            sample(t: 0, x: 0, y: 0), sample(t: 1, x: 3, y: 4), sample(t: 2, x: 6, y: 8)
        ]))
        let stats = try XCTUnwrap(metrics.swipeSpeedStats)

        XCTAssertEqual(stats.mean, 5, accuracy: 0.000_001)
        XCTAssertEqual(stats.stdev, 0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.cvSwipeSpeed), 0, accuracy: 0.000_001)
    }

    func testVariableSpeedUsesSampleSDCV() throws {
        let metrics = DexterityAnalyzer.analyze(trial(samples: [
            sample(t: 0, x: 0, y: 0), sample(t: 1, x: 2, y: 0), sample(t: 2, x: 8, y: 0)
        ]))
        let stats = try XCTUnwrap(metrics.swipeSpeedStats)

        XCTAssertEqual(stats.mean, 4, accuracy: 0.000_001)
        XCTAssertEqual(stats.stdev, sqrt(8), accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.cvSwipeSpeed), sqrt(8) / 4 * 100, accuracy: 0.000_001)
    }

    func testDuplicateAndDescendingTimestampsInvalidateSpeedWithoutDroppingSamples() throws {
        let duplicate = DexterityAnalyzer.analyze(trial(samples: [sample(t: 0, x: 0, y: 0), sample(t: 1, x: 1, y: 0), sample(t: 1, x: 2, y: 0)]))
        let descending = DexterityAnalyzer.analyze(trial(samples: [sample(t: 0, x: 0, y: 0), sample(t: 2, x: 1, y: 0), sample(t: 1, x: 2, y: 0)]))

        XCTAssertEqual(try XCTUnwrap(duplicate.rmsError), 0, accuracy: 0.000_001)
        XCTAssertNil(duplicate.pathInvalidReason)
        XCTAssertNil(duplicate.swipeSpeedStats)
        XCTAssertEqual(duplicate.speedInvalidReason, "speed samples are invalid")
        XCTAssertEqual(try XCTUnwrap(descending.rmsError), 0, accuracy: 0.000_001)
        XCTAssertNil(descending.pathInvalidReason)
        XCTAssertNil(descending.swipeSpeedStats)
        XCTAssertEqual(descending.speedInvalidReason, "speed samples are invalid")
    }

    func testIdenticalCoordinatesProduceTrueZeroSpeedAndUnavailableCV() throws {
        let metrics = DexterityAnalyzer.analyze(trial(samples: [
            sample(t: 0, x: 2, y: 2), sample(t: 1, x: 2, y: 2), sample(t: 2, x: 2, y: 2)
        ]))
        let stats = try XCTUnwrap(metrics.swipeSpeedStats)

        XCTAssertEqual(stats.mean, 0, accuracy: 0.000_001)
        XCTAssertEqual(stats.stdev, 0, accuracy: 0.000_001)
        XCTAssertNil(metrics.cvSwipeSpeed)
    }

    func testOneAndTwoTracePointsLeaveSpeedSummaryUnavailableWithoutBeingMalformed() throws {
        let one = DexterityAnalyzer.analyze(trial(samples: [sample(t: 0, x: 0, y: 0)]))
        let two = DexterityAnalyzer.analyze(trial(samples: [sample(t: 0, x: 0, y: 0), sample(t: 1, x: 5, y: 0)]))

        XCTAssertNil(one.swipeSpeedStats)
        XCTAssertNil(two.swipeSpeedStats)
        XCTAssertNil(one.calculationInvalidReason)
        XCTAssertNil(two.calculationInvalidReason)
        XCTAssertEqual(try XCTUnwrap(DexterityAnalyzer.speedSamples(from: trial(samples: [sample(t: 0, x: 0, y: 0), sample(t: 1, x: 5, y: 0)]))), [5])
    }

    func testNonFiniteCoordinatesInvalidatePathAndSpeed() {
        let nan = DexterityAnalyzer.analyze(trial(samples: [sample(t: 0, x: .nan, y: 0)]))
        let infinity = DexterityAnalyzer.analyze(trial(samples: [sample(t: 0, x: .infinity, y: 0)]))

        XCTAssertNil(nan.rmsError)
        XCTAssertNil(nan.swipeSpeedStats)
        XCTAssertEqual(nan.pathInvalidReason, "path samples are invalid")
        XCTAssertEqual(nan.speedInvalidReason, "speed samples are invalid")
        XCTAssertNil(infinity.rmsError)
        XCTAssertNil(infinity.swipeSpeedStats)
        XCTAssertEqual(infinity.pathInvalidReason, "path samples are invalid")
        XCTAssertEqual(infinity.speedInvalidReason, "speed samples are invalid")
    }

    func testInvalidSegmentIndexInvalidatesPathWithoutDiscardingSpeed() throws {
        let metrics = DexterityAnalyzer.analyze(trial(samples: [
            sample(t: 0, x: 0, y: 0, segmentIndex: 1), sample(t: 1, x: 5, y: 0, segmentIndex: 1), sample(t: 2, x: 10, y: 0, segmentIndex: 1)
        ]))

        XCTAssertNil(metrics.rmsError)
        XCTAssertNotNil(metrics.swipeSpeedStats)
        XCTAssertEqual(metrics.pathInvalidReason, "path samples are invalid")
        XCTAssertNil(metrics.speedInvalidReason)
    }

    func testIncompleteSequenceCanStillProducePathMetrics() throws {
        let metrics = DexterityAnalyzer.analyze(trial(samples: [
            sample(t: 0, x: 0, y: 0), sample(t: 1, x: 5, y: 0)
        ], completed: false))

        XCTAssertEqual(metrics.doneSequences, 0)
        XCTAssertEqual(try XCTUnwrap(metrics.rmsError), 0, accuracy: 0.000_001)
    }

    func testSequenceAndLiftCountsRemainRawMetadata() {
        let first = DexteritySequence(samples: [], completed: true, endedByLift: false)
        let second = DexteritySequence(samples: [], completed: false, endedByLift: true)
        let third = DexteritySequence(samples: [], completed: true, endedByLift: true)
        let metrics = DexterityAnalyzer.analyze(trial(sequences: [first, second, third]))

        XCTAssertEqual(metrics.numSequences, 3)
        XCTAssertEqual(metrics.doneSequences, 2)
        XCTAssertEqual(metrics.liftCount, 2)
    }

    func testEquivalentRenderedScalesProduceEqualCanonicalSpeedMetrics() throws {
        let canonicalTrial = trial(samples: [
            sample(t: 0, x: 0, y: 0), sample(t: 1, x: 5, y: 0), sample(t: 2, x: 10, y: 0)
        ])
        let scaledSpace = DexterityCoordinateSpace(captureWidth: 200, captureHeight: 200, scale: 2, offsetX: 30, offsetY: 40)
        let scaledTrial = trial(
            samples: [
                sample(t: 0, x: 30, y: 40), sample(t: 1, x: 40, y: 40), sample(t: 2, x: 50, y: 40)
            ],
            coordinateSpace: scaledSpace
        )

        let canonicalMetrics = DexterityAnalyzer.analyze(canonicalTrial)
        let scaledMetrics = DexterityAnalyzer.analyze(scaledTrial)
        let canonicalStats = try XCTUnwrap(canonicalMetrics.swipeSpeedStats)
        let scaledStats = try XCTUnwrap(scaledMetrics.swipeSpeedStats)

        XCTAssertEqual(try XCTUnwrap(DexterityAnalyzer.speedSamples(from: scaledTrial)), [5, 5])
        XCTAssertEqual(try XCTUnwrap(canonicalMetrics.rmsError), try XCTUnwrap(scaledMetrics.rmsError), accuracy: 0.000_001)
        XCTAssertEqual(canonicalStats.mean, scaledStats.mean, accuracy: 0.000_001)
        XCTAssertEqual(canonicalStats.stdev, scaledStats.stdev, accuracy: 0.000_001)
        XCTAssertEqual(canonicalMetrics.cvSwipeSpeed, scaledMetrics.cvSwipeSpeed)
    }

    func testDegenerateRoutePreservesCanonicalSpeedMetrics() throws {
        let route = DexterityRoute(identifier: "degenerate", version: 1, points: [.init(x: 0, y: 0), .init(x: 0, y: 0)])
        let metrics = DexterityAnalyzer.analyze(trial(route: route, samples: [
            sample(t: 0, x: 0, y: 0), sample(t: 1, x: 3, y: 4), sample(t: 2, x: 6, y: 8)
        ]))

        XCTAssertNil(metrics.rmsError)
        XCTAssertEqual(metrics.pathInvalidReason, "route is invalid")
        XCTAssertEqual(try XCTUnwrap(metrics.swipeSpeedStats).mean, 5, accuracy: 0.000_001)
        XCTAssertNil(metrics.speedInvalidReason)
    }

    func testInvalidCoordinateSpaceBlocksPathAndSpeedIndependently() {
        let invalidSpace = DexterityCoordinateSpace(captureWidth: 100, captureHeight: 100, scale: 0, offsetX: 0, offsetY: 0)
        let metrics = DexterityAnalyzer.analyze(trial(samples: [
            sample(t: 0, x: 0, y: 0), sample(t: 1, x: 5, y: 0), sample(t: 2, x: 10, y: 0)
        ], coordinateSpace: invalidSpace))

        XCTAssertNil(metrics.rmsError)
        XCTAssertNil(metrics.swipeSpeedStats)
        XCTAssertEqual(metrics.pathInvalidReason, "coordinate space is invalid")
        XCTAssertEqual(metrics.speedInvalidReason, "coordinate space is invalid")
    }

    private func route() -> DexterityRoute {
        DexterityRoute(identifier: "line", version: 1, points: [.init(x: 0, y: 0), .init(x: 10, y: 0)])
    }

    private func coordinateSpace() -> DexterityCoordinateSpace {
        DexterityCoordinateSpace(captureWidth: 100, captureHeight: 100, scale: 1, offsetX: 0, offsetY: 0)
    }

    private func sample(t: TimeInterval, x: Double, y: Double, segmentIndex: Int = 0) -> DexterityTracePoint {
        DexterityTracePoint(t: t, x: x, y: y, segmentIndex: segmentIndex)
    }

    private func trial(
        route: DexterityRoute? = nil,
        samples: [DexterityTracePoint] = [],
        completed: Bool = true,
        sequences: [DexteritySequence]? = nil,
        coordinateSpace: DexterityCoordinateSpace? = nil
    ) -> DexterityTrial {
        DexterityTrial(
            route: route ?? self.route(),
            coordinateSpace: coordinateSpace ?? self.coordinateSpace(),
            sequences: sequences ?? [DexteritySequence(samples: samples, completed: completed, endedByLift: false)],
            startedAt: 0
        )
    }
}
