import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class DexteritySessionModelTests: XCTestCase {
    func testPracticeAndFailedScoredAttemptsAreRetainedWhileOnlyCompletedScoredAttemptsSave() throws {
        let context = try makeContext()
        var saveCount = 0
        let model = DexteritySessionModel { capture, _, _, _, context in
            saveCount += 1
            XCTAssertEqual(capture.practiceAttempts.count, 2)
            XCTAssertEqual(capture.scoredAttempts.count, 4)
            XCTAssertEqual(capture.completedScoredAttemptIndexes, [1, 2, 3])
            return DexterityResult(context: context)
        }
        let configuration = try XCTUnwrap(DexterityProtocolV1.configuration(captureWidth: 320, captureHeight: 400, padding: 32))
        model.configure(configuration)
        model.start()

        model.receive(sequence: incompleteSequence(), monotonicStartedAt: 1, in: context)
        XCTAssertEqual(model.phase, .practice)
        model.receive(sequence: completedSequence(), monotonicStartedAt: 2, in: context)
        XCTAssertEqual(model.phase, .scored(round: 1))

        model.receive(sequence: cancelledSequence(), monotonicStartedAt: 3, in: context)
        XCTAssertEqual(model.phase, .scored(round: 1))
        model.receive(sequence: completedSequence(), monotonicStartedAt: 4, in: context)
        XCTAssertEqual(model.phase, .scored(round: 2))
        model.receive(sequence: completedSequence(), monotonicStartedAt: 5, in: context)
        XCTAssertEqual(model.phase, .scored(round: 3))
        model.receive(sequence: completedSequence(), monotonicStartedAt: 6, in: context)

        XCTAssertEqual(model.phase, .finished)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(model.practiceAttempts.count, 2)
        XCTAssertTrue(model.practiceAttempts[0].endedByLift)
        XCTAssertEqual(model.scoredAttempts.count, 4)
        XCTAssertTrue(model.scoredAttempts[0].endedByCancellation)
        XCTAssertEqual(model.completedScoredAttemptIndexes, [1, 2, 3])

        model.receive(sequence: completedSequence(), monotonicStartedAt: 7, in: context)
        XCTAssertEqual(saveCount, 1)
    }

    private func makeContext() throws -> NSManagedObjectContext {
        let bundle = Bundle(for: DexterityResult.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Kinesia", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
        let container = NSPersistentContainer(name: "Kinesia", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var error: Error?
        container.loadPersistentStores { _, loadError in error = loadError }
        if let error { throw error }
        return container.viewContext
    }

    private func completedSequence() -> DexteritySequence {
        let route = DexterityProtocolV1.route.points
        return DexteritySequence(samples: route.enumerated().map { index, point in
            DexterityTracePoint(t: Double(index), x: point.x, y: point.y, segmentIndex: min(index, route.count - 2))
        }, completed: true, endedByLift: false)
    }

    private func incompleteSequence() -> DexteritySequence {
        DexteritySequence(samples: [DexterityTracePoint(t: 0, x: 15, y: 80, segmentIndex: 0)], completed: false, endedByLift: true)
    }

    private func cancelledSequence() -> DexteritySequence {
        DexteritySequence(samples: [DexterityTracePoint(t: 0, x: 15, y: 80, segmentIndex: 0)], completed: false, endedByLift: false, endedByCancellation: true)
    }
}
