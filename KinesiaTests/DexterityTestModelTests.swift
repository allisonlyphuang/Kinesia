import XCTest
@testable import Kinesia

@MainActor
final class DexterityTestModelTests: XCTestCase {
    func testStartInsideFirstTargetBeginsTracingWithSegmentZero() throws {
        let model = makeModel()

        model.handle(.began(sample(t: 0, x: 0, y: 0)))

        XCTAssertEqual(model.phase, .tracing)
        XCTAssertTrue(model.isTraceActive)
        XCTAssertEqual(model.activeSegmentIndex, 0)
        XCTAssertEqual(model.nextTargetIndex, 1)
        XCTAssertEqual(try XCTUnwrap(model.currentTracePoints.first).segmentIndex, 0)
    }

    func testStartOutsideFirstTargetDoesNotBeginSequence() {
        let model = makeModel()

        model.handle(.began(sample(t: 0, x: 3, y: 0)))

        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.isTraceActive)
        XCTAssertTrue(model.currentTracePoints.isEmpty)
        XCTAssertNil(model.latestSequence)
    }

    func testTargetBoundaryAdvancesAfterTheArrivingSampleIsAssigned() throws {
        let model = tracingModel()

        model.handle(.moved([sample(t: 1, x: 5, y: 0), sample(t: 2, x: 10, y: 0), sample(t: 3, x: 10, y: 4)]))

        XCTAssertEqual(model.currentTracePoints.map(\.segmentIndex), [0, 0, 0, 1])
        XCTAssertEqual(model.activeSegmentIndex, 1)
        XCTAssertEqual(model.nextTargetIndex, 2)
        XCTAssertEqual(try XCTUnwrap(model.currentTracePoints.last).x, 10, accuracy: 0.000_001)
    }

    func testCannotSkipExpectedTarget() {
        let model = tracingModel()

        model.handle(.moved([sample(t: 1, x: 10, y: 10)]))

        XCTAssertEqual(model.activeSegmentIndex, 0)
        XCTAssertEqual(model.nextTargetIndex, 1)
        XCTAssertEqual(model.currentTracePoints.last?.segmentIndex, 0)
    }

    func testBacktrackingDoesNotDecrementProgress() {
        let model = tracingModel()
        model.handle(.moved([sample(t: 1, x: 10, y: 0)]))
        model.handle(.moved([sample(t: 2, x: 3, y: 0)]))

        XCTAssertEqual(model.activeSegmentIndex, 1)
        XCTAssertEqual(model.nextTargetIndex, 2)
        XCTAssertEqual(model.currentTracePoints.last?.segmentIndex, 1)
    }

    func testFinalTargetCompletesAndDoesNotAcceptLaterMovement() throws {
        let model = tracingModel()
        model.handle(.moved([sample(t: 1, x: 10, y: 0), sample(t: 2, x: 10, y: 10)]))
        let completedCount = model.currentTracePoints.count

        XCTAssertEqual(model.phase, .completed)
        XCTAssertEqual(try XCTUnwrap(model.latestSequence).completed, true)
        XCTAssertEqual(try XCTUnwrap(model.latestSequence).samples.last?.segmentIndex, 1)

        model.handle(.moved([sample(t: 3, x: 9, y: 9)]))
        XCTAssertEqual(model.currentTracePoints.count, completedCount)
    }

    func testEarlyEndProducesIncompleteLiftSequence() throws {
        let model = tracingModel()

        model.handle(.ended(sample(t: 1, x: 5, y: 0)))

        let sequence = try XCTUnwrap(model.latestSequence)
        XCTAssertEqual(model.phase, .ended)
        XCTAssertFalse(sequence.completed)
        XCTAssertTrue(sequence.endedByLift)
        XCTAssertFalse(sequence.endedByCancellation)
        XCTAssertEqual(sequence.samples.count, 2)
    }

    func testEndedSequenceDoesNotAutomaticallyStartARetry() throws {
        let model = tracingModel()
        model.handle(.ended(sample(t: 1, x: 5, y: 0)))
        let endedSequence = try XCTUnwrap(model.latestSequence)

        model.handle(.began(sample(t: 2, x: 0, y: 0)))

        XCTAssertEqual(model.phase, .ended)
        XCTAssertEqual(model.latestSequence, endedSequence)
    }

    func testEndAfterCompletionPreservesCompletedSequence() throws {
        let model = completedModel()
        let before = try XCTUnwrap(model.latestSequence)

        model.handle(.ended(sample(t: 3, x: 10, y: 10)))

        XCTAssertEqual(model.phase, .completed)
        XCTAssertEqual(model.latestSequence, before)
    }

    func testCancelledTraceIsNotCompletedAndRetainsCancellationMetadata() throws {
        let model = tracingModel()

        model.handle(.cancelled(sample(t: 1, x: 5, y: 0)))

        let sequence = try XCTUnwrap(model.latestSequence)
        XCTAssertEqual(model.phase, .ended)
        XCTAssertFalse(sequence.completed)
        XCTAssertFalse(sequence.endedByLift)
        XCTAssertTrue(sequence.endedByCancellation)
    }

    func testDuplicateEndedSampleIsNotAppendedTwiceButDistinctSampleIsRetained() throws {
        let duplicateModel = tracingModel()
        let finalMoved = sample(t: 1, x: 5, y: 0)
        duplicateModel.handle(.moved([finalMoved]))
        duplicateModel.handle(.ended(finalMoved))
        XCTAssertEqual(try XCTUnwrap(duplicateModel.latestSequence).samples.count, 2)

        let distinctModel = tracingModel()
        distinctModel.handle(.moved([finalMoved]))
        distinctModel.handle(.ended(sample(t: 2, x: 6, y: 0)))
        XCTAssertEqual(try XCTUnwrap(distinctModel.latestSequence).samples.count, 3)
    }

    func testInvalidConfigurationIsExplicit() {
        let invalidRadius = DexterityTestModel(configuration: DexterityTestConfiguration(route: route(), coordinateSpace: coordinateSpace(), targetRadius: 0))
        let invalidRoute = DexterityTestModel(configuration: DexterityTestConfiguration(
            route: DexterityRoute(identifier: "invalid", version: 1, points: [.init(x: 0, y: 0)]),
            coordinateSpace: coordinateSpace(),
            targetRadius: 1
        ))
        let invalidSpace = DexterityTestModel(configuration: DexterityTestConfiguration(
            route: route(),
            coordinateSpace: DexterityCoordinateSpace(captureWidth: 100, captureHeight: 100, scale: 0, offsetX: 0, offsetY: 0),
            targetRadius: 1
        ))

        XCTAssertEqual(invalidRadius.phase, .configurationInvalid("target radius is invalid"))
        XCTAssertEqual(invalidRoute.phase, .configurationInvalid("route is invalid"))
        XCTAssertEqual(invalidSpace.phase, .configurationInvalid("coordinate space is invalid"))
    }

    func testCompletedSequenceFlowsDirectlyIntoTrialAndAnalyzer() throws {
        let model = tracingModel()
        model.handle(.moved([
            sample(t: 1, x: 5, y: 0),
            sample(t: 2, x: 10, y: 0),
            sample(t: 3, x: 10, y: 5),
            sample(t: 4, x: 10, y: 10)
        ]))

        let sequence = try XCTUnwrap(model.latestSequence)
        let trial = DexterityTrial(
            route: route(),
            coordinateSpace: coordinateSpace(),
            sequences: [sequence],
            startedAt: 0
        )
        let metrics = DexterityAnalyzer.analyze(trial)

        XCTAssertEqual(metrics.doneSequences, 1)
        XCTAssertEqual(try XCTUnwrap(metrics.rmsError), 0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.swipeSpeedStats).mean, 5, accuracy: 0.000_001)
    }

    func testResetReturnsAnEndedSequenceModelToReady() {
        let model = tracingModel()
        model.handle(.ended(sample(t: 1, x: 5, y: 0)))

        model.reset()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.latestSequence)
        XCTAssertTrue(model.currentTracePoints.isEmpty)
        XCTAssertEqual(model.activeSegmentIndex, 0)
        XCTAssertEqual(model.nextTargetIndex, 1)
    }

    private func makeModel() -> DexterityTestModel {
        DexterityTestModel(configuration: DexterityTestConfiguration(route: route(), coordinateSpace: coordinateSpace(), targetRadius: 1))
    }

    private func tracingModel() -> DexterityTestModel {
        let model = makeModel()
        model.handle(.began(sample(t: 0, x: 0, y: 0)))
        return model
    }

    private func completedModel() -> DexterityTestModel {
        let model = tracingModel()
        model.handle(.moved([sample(t: 1, x: 10, y: 0), sample(t: 2, x: 10, y: 10)]))
        return model
    }

    private func route() -> DexterityRoute {
        DexterityRoute(
            identifier: "test-route",
            version: 1,
            points: [.init(x: 0, y: 0), .init(x: 10, y: 0), .init(x: 10, y: 10)]
        )
    }

    private func coordinateSpace() -> DexterityCoordinateSpace {
        DexterityCoordinateSpace(captureWidth: 100, captureHeight: 100, scale: 1, offsetX: 0, offsetY: 0)
    }

    private func sample(t: TimeInterval, x: Double, y: Double) -> DexterityTouchSample {
        DexterityTouchSample(t: t, x: x, y: y)
    }
}
