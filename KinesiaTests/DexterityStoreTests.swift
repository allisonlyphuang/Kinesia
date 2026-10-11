import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class DexterityStoreTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        let bundle = Bundle(for: DexterityResult.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Kinesia", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
        container = NSPersistentContainer(name: "Kinesia", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var error: Error?
        container.loadPersistentStores { _, loadError in error = loadError }
        if let error { throw error }
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    func testSaveMapsScoredMetricsAndRetainsAllRawAttempts() throws {
        let failedPractice = DexteritySequence(samples: [sample(t: 0, point: DexterityProtocolV1.route.points[0], segment: 0)], completed: false, endedByLift: true)
        let failedScored = DexteritySequence(samples: [sample(t: 0, point: DexterityProtocolV1.route.points[0], segment: 0)], completed: false, endedByLift: true)
        let cancelledScored = DexteritySequence(samples: [sample(t: 0, point: DexterityProtocolV1.route.points[0], segment: 0)], completed: false, endedByLift: false, endedByCancellation: true)
        let completed = completedSequence(start: 10)
        let capture = DexteritySessionCapture(
            route: DexterityProtocolV1.route,
            coordinateSpace: coordinateSpace,
            targetRadius: DexterityProtocolV1.targetRadius,
            practiceAttempts: [failedPractice, completed],
            scoredAttempts: [failedScored, cancelledScored, completed, completed, completed],
            completedScoredAttemptIndexes: [2, 3, 4],
            startedAt: 10
        )
        let metrics = DexterityAnalyzer.analyzeScored(trial(from: capture))
        let started = Date(timeIntervalSince1970: 1_900_000_000)
        let completedAt = Date(timeIntervalSince1970: 1_900_000_010)

        let saved = try DexterityStore.save(capture: capture, metrics: metrics, startedAt: started, completedAt: completedAt, in: context)
        let session = try XCTUnwrap(saved.session)
        let raw = try XCTUnwrap(session.rawCaptures?.allObjects.first as? RawCapture)
        let decoded = try JSONDecoder().decode(DexteritySessionCapture.self, from: try XCTUnwrap(raw.payload))

        XCTAssertEqual(try context.count(for: TestSession.fetchRequest()), 1)
        XCTAssertEqual(try context.count(for: DexterityResult.fetchRequest()), 1)
        XCTAssertEqual(try context.count(for: RawCapture.fetchRequest()), 1)
        XCTAssertTrue(saved.isValid)
        XCTAssertNil(saved.invalidReason)
        XCTAssertEqual(saved.hand, "right")
        XCTAssertEqual(saved.numSequences, 3)
        XCTAssertEqual(saved.doneSequences, 3)
        XCTAssertEqual(saved.fingerLifts, 1)
        XCTAssertEqual(saved.rmsError, 0, accuracy: 0.000_001)
        XCTAssertEqual(saved.rmsErrorMax, 0, accuracy: 0.000_001)
        XCTAssertEqual(saved.swipeDist, try XCTUnwrap(metrics.swipeDist), accuracy: 0.000_001)
        XCTAssertEqual(raw.kind, DexterityStore.rawCaptureKind)
        XCTAssertEqual(raw.schemaVersion, DexterityStore.rawCaptureSchemaVersion)
        XCTAssertEqual(decoded.practiceAttempts.count, 2)
        XCTAssertEqual(decoded.scoredAttempts.count, 5)
        XCTAssertEqual(decoded.scoredAttempts[0].endedByLift, true)
        XCTAssertEqual(decoded.scoredAttempts[1].endedByCancellation, true)
        XCTAssertEqual(decoded.completedScoredAttemptIndexes, [2, 3, 4])
    }

    func testIncompleteScoredCaptureDoesNotInsertObjects() throws {
        let completed = completedSequence(start: 10)
        let capture = DexteritySessionCapture(
            route: DexterityProtocolV1.route,
            coordinateSpace: coordinateSpace,
            targetRadius: DexterityProtocolV1.targetRadius,
            practiceAttempts: [completed],
            scoredAttempts: [completed, completed],
            completedScoredAttemptIndexes: [0, 1],
            startedAt: 10
        )
        let trial = DexterityTrial(route: capture.route, coordinateSpace: capture.coordinateSpace, sequences: [completed, completed], startedAt: 10)

        XCTAssertThrowsError(try DexterityStore.save(capture: capture, metrics: DexterityAnalyzer.analyzeScored(trial), startedAt: Date(), completedAt: Date(), in: context))
        XCTAssertEqual(try context.count(for: TestSession.fetchRequest()), 0)
        XCTAssertEqual(try context.count(for: DexterityResult.fetchRequest()), 0)
        XCTAssertEqual(try context.count(for: RawCapture.fetchRequest()), 0)
    }

    func testFetchResultsUsesNewestWallClockTimestamp() throws {
        let capture = validCapture()
        let metrics = DexterityAnalyzer.analyzeScored(trial(from: capture))
        _ = try DexterityStore.save(capture: capture, metrics: metrics, startedAt: Date(timeIntervalSince1970: 10), completedAt: Date(timeIntervalSince1970: 20), in: context)
        let newest = try DexterityStore.save(capture: capture, metrics: metrics, startedAt: Date(timeIntervalSince1970: 30), completedAt: Date(timeIntervalSince1970: 40), in: context)

        XCTAssertEqual(try DexterityStore.fetchLatestResult(in: context)?.id, newest.id)
        XCTAssertEqual(try DexterityStore.fetchResults(in: context).first?.id, newest.id)
    }

    private let coordinateSpace = DexterityCoordinateSpace(captureWidth: 120, captureHeight: 120, scale: 1, offsetX: 0, offsetY: 0)

    private func validCapture() -> DexteritySessionCapture {
        let completed = completedSequence(start: 10)
        return DexteritySessionCapture(route: DexterityProtocolV1.route, coordinateSpace: coordinateSpace, targetRadius: DexterityProtocolV1.targetRadius, practiceAttempts: [completed], scoredAttempts: [completed, completed, completed], completedScoredAttemptIndexes: [0, 1, 2], startedAt: 10)
    }

    private func trial(from capture: DexteritySessionCapture) -> DexterityTrial {
        DexterityTrial(route: capture.route, coordinateSpace: capture.coordinateSpace, sequences: capture.completedScoredSequences ?? [], startedAt: capture.startedAt)
    }

    private func completedSequence(start: TimeInterval) -> DexteritySequence {
        let points = DexterityProtocolV1.route.points
        let samples = points.enumerated().map { index, point in
            sample(t: start + Double(index), point: point, segment: min(index, points.count - 2))
        }
        return DexteritySequence(samples: samples, completed: true, endedByLift: false)
    }

    private func sample(t: TimeInterval, point: DexterityRoutePoint, segment: Int) -> DexterityTracePoint {
        DexterityTracePoint(t: t, x: point.x, y: point.y, segmentIndex: segment)
    }
}
