import CoreData
import XCTest
@testable import Kinesia

final class DexterityProtocolMetricsTests: XCTestCase {
    func testProtocolV1DefinesTheLockedRightIndexConfiguration() throws {
        XCTAssertEqual(DexterityProtocolV1.identifier, "kinesia-dexterity-v1")
        XCTAssertEqual(DexterityProtocolV1.route.identifier, "constellation-v1")
        XCTAssertEqual(DexterityProtocolV1.route.version, 1)
        XCTAssertEqual(DexterityProtocolV1.route.points, [
            .init(x: 15, y: 80), .init(x: 20, y: 20), .init(x: 50, y: 45), .init(x: 80, y: 20), .init(x: 85, y: 80)
        ])
        XCTAssertEqual(DexterityProtocolV1.targetRadius, 8)
        XCTAssertEqual(DexterityProtocolV1.practiceCompletionsRequired, 1)
        XCTAssertEqual(DexterityProtocolV1.scoredCompletionsRequired, 3)
        XCTAssertEqual(DexterityProtocolV1.hand, "right")
        XCTAssertEqual(DexterityProtocolV1.digit, "index")
    }

    func testCanonicalPathLengthDoesNotCrossSequenceBoundaries() throws {
        let first = sequence(samples: [point(t: 0, x: 0, y: 0), point(t: 1, x: 3, y: 4)])
        let second = sequence(samples: [point(t: 2, x: 100, y: 0), point(t: 3, x: 106, y: 8)])

        XCTAssertEqual(try XCTUnwrap(DexterityAnalyzer.canonicalPathLength(of: first, coordinateSpace: space)), 5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(DexterityAnalyzer.canonicalPathLength(of: second, coordinateSpace: space)), 10, accuracy: 0.000_001)
    }

    func testScoredMetricsUsePerSequenceRMSEMaximumAndMeanPathLength() throws {
        let sequences = [
            sequence(samples: [point(t: 0, x: 0, y: 1), point(t: 1, x: 5, y: 1), point(t: 2, x: 10, y: 1)]),
            sequence(samples: [point(t: 3, x: 0, y: 0), point(t: 4, x: 5, y: 4), point(t: 5, x: 10, y: 0)]),
            sequence(samples: [point(t: 6, x: 0, y: 2), point(t: 7, x: 5, y: 2), point(t: 8, x: 10, y: 2)])
        ]
        let metrics = DexterityAnalyzer.analyzeScored(trial(sequences: sequences))

        XCTAssertEqual(try XCTUnwrap(metrics.aggregate.rmsError), sqrt(31.0) / 3.0, accuracy: 0.000_001)
        let perSequenceRMSE = try XCTUnwrap(metrics.perSequenceRMSE)
        XCTAssertEqual(perSequenceRMSE.count, 3)
        XCTAssertEqual(perSequenceRMSE[0], 1, accuracy: 0.000_001)
        XCTAssertEqual(perSequenceRMSE[1], 4 / sqrt(3), accuracy: 0.000_001)
        XCTAssertEqual(perSequenceRMSE[2], 2, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.rmsErrorMax), 4 / sqrt(3), accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.swipeDist), (20 + 2 * sqrt(41)) / 3, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.aggregate.maxPointError), 4, accuracy: 0.000_001)
        XCTAssertNotEqual(metrics.rmsErrorMax, metrics.aggregate.maxPointError)
    }

    func testCompletedScoredIndexesPreserveRetriesAndExcludeIncompleteAttempts() throws {
        let failed = DexteritySequence(samples: [point(t: 0, x: 0, y: 0)], completed: false, endedByLift: true)
        let completed = sequence(samples: [point(t: 1, x: 0, y: 0), point(t: 2, x: 5, y: 0), point(t: 3, x: 10, y: 0)])
        let capture = DexteritySessionCapture(
            route: route,
            coordinateSpace: space,
            targetRadius: 1,
            practiceAttempts: [failed],
            scoredAttempts: [failed, completed, completed, completed],
            completedScoredAttemptIndexes: [1, 2, 3],
            startedAt: 0
        )

        XCTAssertEqual(try XCTUnwrap(capture.completedScoredSequences).count, 3)
        XCTAssertEqual(capture.scoredAttempts.count, 4)
        XCTAssertTrue(capture.scoredAttempts[0].endedByLift)
    }

    func testCoreDataModelUsesFingerLiftsRenamedFromThumbLifts() throws {
        let modelBundle = Bundle(for: DexterityResult.self)
        let modelURL = try XCTUnwrap(modelBundle.url(forResource: "Kinesia", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        let attributes = try XCTUnwrap(model.entitiesByName["DexterityResult"]?.attributesByName)

        XCTAssertNotNil(attributes["fingerLifts"])
        XCTAssertNil(attributes["thumbLifts"])
    }

    private let route = DexterityRoute(identifier: "line", version: 1, points: [.init(x: 0, y: 0), .init(x: 10, y: 0)])
    private let space = DexterityCoordinateSpace(captureWidth: 100, captureHeight: 100, scale: 1, offsetX: 0, offsetY: 0)

    private func trial(sequences: [DexteritySequence]) -> DexterityTrial {
        DexterityTrial(route: route, coordinateSpace: space, sequences: sequences, startedAt: 0)
    }

    private func sequence(samples: [DexterityTracePoint]) -> DexteritySequence {
        DexteritySequence(samples: samples, completed: true, endedByLift: false)
    }

    private func point(t: TimeInterval, x: Double, y: Double) -> DexterityTracePoint {
        DexterityTracePoint(t: t, x: x, y: y, segmentIndex: 0)
    }
}
