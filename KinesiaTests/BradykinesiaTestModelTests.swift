import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class BradykinesiaTestModelTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        let modelBundle = Bundle(for: BradykinesiaResult.self)
        let modelURL = try XCTUnwrap(modelBundle.url(forResource: "Kinesia", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        container = NSPersistentContainer(name: "Kinesia", managedObjectModel: model)

        let storeDescription = NSPersistentStoreDescription()
        storeDescription.type = NSInMemoryStoreType
        storeDescription.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [storeDescription]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }
    
    
    // UNILATERAL LIFECYCLE

    func testPhaseTransitionsAreDeterministicWithoutSleeping() {
            let model = makeModel(countdownSeconds: 2)

            XCTAssertEqual(model.phase, .ready)
            model.start()
            XCTAssertEqual(model.phase, .countdown(.right))
            XCTAssertEqual(model.secondsRemaining, 2)

            model.countdownTick()
            XCTAssertEqual(model.phase, .countdown(.right))
            XCTAssertEqual(model.secondsRemaining, 1)

            model.countdownTick()
            XCTAssertEqual(model.phase, .running(.right))
            XCTAssertEqual(model.secondsRemaining, 20)

            model.completeRunningWindow()
            XCTAssertEqual(model.phase, .finished)
        }

    func testRecordTapAcceptsOnlyRunningAndPreservesOrderAndMisses() {
            let model = makeModel(countdownSeconds: 1)
            let readyTap = TapSample(t: 1, x: 1, y: 1, target: .left)
            let runningSamples = [
                TapSample(t: 10, x: 0, y: 0, target: .left),
                TapSample(t: 10.2, x: 10, y: 0, target: .miss),
                TapSample(t: 10.5, x: 0, y: 3, target: .right)
            ]

            model.recordTap(readyTap)
            XCTAssertTrue(model.capturedSamples.isEmpty)

            model.start()
            model.recordTap(readyTap)
            XCTAssertTrue(model.capturedSamples.isEmpty)

            model.countdownTick()
            runningSamples.forEach(model.recordTap)
            XCTAssertEqual(model.capturedSamples.map(\.t), [10, 10.2, 10.5])
            XCTAssertEqual(model.capturedSamples.map(\.x), [0, 10, 0])
            XCTAssertEqual(model.capturedSamples.map(\.y), [0, 0, 3])
            XCTAssertEqual(model.capturedSamples.map(\.target), [.left, .miss, .right])

            model.completeRunningWindow()
            model.recordTap(TapSample(t: 11, x: 10, y: 4, target: .right))
            XCTAssertEqual(model.capturedSamples.count, 3)
        }

    func testLifecyclePersistsTrialAnalyzerResultAndRawCapture() throws {
            let startDate = Date(timeIntervalSince1970: 1_900_000_000)
            let completionDate = Date(timeIntervalSince1970: 1_900_000_020)
            var wallClockDates = [startDate, completionDate]
            let model = makeModel(
                countdownSeconds: 1,
                monotonicNow: advancingClock(from: 345.25),
                wallClockNow: { wallClockDates.removeFirst() }
            )
            let sourceSamples = validSamples()

            model.start()
            model.countdownTick()
            sourceSamples.forEach(model.recordTap)
            model.completeRunningWindow()

            let result = try XCTUnwrap(BradykinesiaStore.fetchLatestResult(in: context))
            let session = try XCTUnwrap(result.session)
            let rawCapture = try XCTUnwrap(session.rawCaptures?.allObjects.first as? RawCapture)
            let decoded = try JSONDecoder().decode(TapTrial.self, from: try XCTUnwrap(rawCapture.payload))
        
            XCTAssertEqual(model.phase, .finished)
            XCTAssertEqual(result.numTaps, Int32(sourceSamples.count))
            XCTAssertEqual(session.startedAt, startDate.timeIntervalSince1970, accuracy: 0.000_001)
            XCTAssertEqual(session.completedAt, completionDate.timeIntervalSince1970, accuracy: 0.000_001)
            XCTAssertEqual(decoded.samples.map(\.t), sourceSamples.map(\.t))
            XCTAssertEqual(decoded.samples.map(\.x), sourceSamples.map(\.x))
            XCTAssertEqual(decoded.samples.map(\.y), sourceSamples.map(\.y))
            XCTAssertEqual(decoded.samples.map(\.target), [.left, .right, .miss, .right, .left, .miss])
            XCTAssertEqual(decoded.leftCenter.x, 0, accuracy: 0.000_001)
            XCTAssertEqual(decoded.rightCenter.x, 10, accuracy: 0.000_001)
            XCTAssertEqual(decoded.targetRadius, 3, accuracy: 0.000_001)
            XCTAssertEqual(decoded.hand, .right)
            XCTAssertEqual(decoded.screenScale, 3, accuracy: 0.000_001)
            XCTAssertEqual(result.durationSec, 20, accuracy: 0.000_001)
        }

    func testActiveStartAndDuplicateCompletionCreateOnlyOnePersistedSession() throws {
            let model = makeModel(countdownSeconds: 1)

            model.start()
            model.start()
            XCTAssertEqual(model.phase, .countdown(.right))
            XCTAssertEqual(model.secondsRemaining, 1)

            model.countdownTick()
            model.start()
            validSamples().forEach(model.recordTap)
            model.completeRunningWindow()
            model.completeRunningWindow()

            XCTAssertEqual(model.phase, .finished)
            XCTAssertEqual(try context.count(for: TestSession.fetchRequest()), 1)
            XCTAssertEqual(try context.count(for: BradykinesiaResult.fetchRequest()), 1)
            XCTAssertEqual(try context.count(for: RawCapture.fetchRequest()), 1)
        }

    func testPersistenceFailureIsExposedWithoutAutomaticRetry() {
        enum ExpectedError: Error {
            case saveFailed
        }

        let model = makeModel(
            countdownSeconds: 0,
            persistenceAction: {_, _ in throw ExpectedError.saveFailed }
        )

        model.start()
        let sample = TapSample(t: 1, x: 0, y: 0, target: .miss)
        model.recordTap(sample)
        model.completeRunningWindow()
        model.completeRunningWindow()

        XCTAssertEqual(model.phase, .failed)
        XCTAssertNotNil(model.persistenceError)
        XCTAssertEqual(model.capturedSamples.count, 1)
        XCTAssertEqual(try? context.count(for: TestSession.fetchRequest()), 0)
    }

    func testConfigurationCanUpdateBeforeStartAndResetReturnsToReady() {
            let model = makeModel(countdownSeconds: 1)
            let configuredGeometry = BradykinesiaTestConfiguration(
                leftCenter: TapPoint(x: 24, y: 150),
                rightCenter: TapPoint(x: 276, y: 150),
                targetRadius: 48,
                handOrder: [.right],
                screenScale: 3,
                countdownSeconds: 1,
                captureDuration: 20
            )

            model.configure(configuredGeometry)
            XCTAssertEqual(model.configuration.leftCenter.x, 24, accuracy: 0.000_001)
            XCTAssertEqual(model.configuration.rightCenter.x, 276, accuracy: 0.000_001)
            XCTAssertEqual(model.configuration.targetRadius, 48, accuracy: 0.000_001)

            model.start()
            let attemptedActiveConfiguration = BradykinesiaTestConfiguration(
                leftCenter: TapPoint(x: 1, y: 1),
                rightCenter: TapPoint(x: 2, y: 2),
                targetRadius: 10,
                handOrder: [.left],
                screenScale: 2,
                countdownSeconds: 1,
                captureDuration: 20
            )
            model.configure(attemptedActiveConfiguration)
            XCTAssertEqual(model.configuration.leftCenter.x, 24, accuracy: 0.000_001)

            model.countdownTick()
            model.completeRunningWindow()
            XCTAssertEqual(model.phase, .finished)

            model.reset()
            XCTAssertEqual(model.phase, .ready)
            XCTAssertTrue(model.capturedSamples.isEmpty)
            XCTAssertTrue(model.completedAttempts.isEmpty)
        }
    
    
    
    // BILATERAL LIFECYCLE
    
    func testBilateralLifecycleRunsBothHandsAndPersistsExactlyOneSession() throws {
            let model = makeModel(countdownSeconds: 1, handOrder: [.right, .left])

            model.start()
            XCTAssertEqual(model.phase, .countdown(.right))
            model.countdownTick()
            XCTAssertEqual(model.phase, .running(.right))
            validSamples().forEach(model.recordTap)
            model.completeRunningWindow()

            // First hand done: parked in rest, nothing written to the database yet.
            XCTAssertEqual(model.phase, .rest(nextHand: .left))
            XCTAssertEqual(model.completedAttempts.map(\.hand), [.right])
            XCTAssertEqual(try context.count(for: TestSession.fetchRequest()), 0)

            model.beginCountdown(for: .left)
            XCTAssertEqual(model.phase, .countdown(.left))
            model.countdownTick()
            XCTAssertEqual(model.phase, .running(.left))
            validSamples().forEach(model.recordTap)
            model.completeRunningWindow()

            XCTAssertEqual(model.phase, .finished)
            XCTAssertEqual(model.completedAttempts.map(\.hand), [.right, .left])
            XCTAssertEqual(try context.count(for: TestSession.fetchRequest()), 1)
            XCTAssertEqual(try context.count(for: BradykinesiaResult.fetchRequest()), 2)
            XCTAssertEqual(try context.count(for: RawCapture.fetchRequest()), 2)
        }

        func testFirstHandAttemptSurvivesStartingTheSecondHand() {
            let model = makeModel(countdownSeconds: 0, handOrder: [.right, .left])

            model.start()
            validSamples().forEach(model.recordTap)
            model.completeRunningWindow()
            let firstAttemptTapCount = model.completedAttempts.first?.trial.samples.count

            model.beginCountdown(for: .left)

            // Per-hand state is cleared; the finished attempt is not.
            XCTAssertTrue(model.capturedSamples.isEmpty)
            XCTAssertEqual(model.completedAttempts.count, 1)
            XCTAssertEqual(model.completedAttempts.first?.trial.samples.count, firstAttemptTapCount)
        }

        func testTapsDuringRestAreIgnored() {
            let model = makeModel(countdownSeconds: 0, handOrder: [.right, .left])

            model.start()
            validSamples().forEach(model.recordTap)
            model.completeRunningWindow()
            XCTAssertEqual(model.phase, .rest(nextHand: .left))

            let capturedBeforeRestTap = model.capturedSamples.count
            model.recordTap(TapSample(t: 99, x: 0, y: 0, target: .right))

            XCTAssertEqual(model.capturedSamples.count, capturedBeforeRestTap)
            XCTAssertEqual(model.completedAttempts.count, 1)
        }

        func testUnilateralOrderFinishesWithoutEnteringRest() {
            let model = makeModel(countdownSeconds: 0, handOrder: [.right])

            model.start()
            validSamples().forEach(model.recordTap)
            model.completeRunningWindow()

            XCTAssertEqual(model.phase, .finished)
            XCTAssertEqual(model.completedAttempts.count, 1)
        }

        func testResetClearsCompletedAttemptsSoASecondTestDoesNotInheritThem() {
            let model = makeModel(countdownSeconds: 0, handOrder: [.right])

            model.start()
            validSamples().forEach(model.recordTap)
            model.completeRunningWindow()
            XCTAssertEqual(model.completedAttempts.count, 1)

            model.reset()
            XCTAssertTrue(model.completedAttempts.isEmpty)

            model.start()
            validSamples().forEach(model.recordTap)
            model.completeRunningWindow()

            XCTAssertEqual(model.completedAttempts.count, 1, "A new run must not append to the previous run's attempts")
        }
    
    
    // HELPERS

    private func makeModel(
        countdownSeconds: Int,
        handOrder: [CurrentHand] = [.right],
        monotonicNow: (() -> TimeInterval)? = nil,
        wallClockNow: (() -> Date)? = nil,
        persistenceAction: BradykinesiaTestModel.PersistenceAction? = nil
    ) -> BradykinesiaTestModel {
        BradykinesiaTestModel(
            configuration: BradykinesiaTestConfiguration(
                leftCenter: TapPoint(x: 0, y: 0),
                rightCenter: TapPoint(x: 10, y: 0),
                targetRadius: 3,
                handOrder: handOrder,
                screenScale: 3,
                countdownSeconds: countdownSeconds,
                captureDuration: 20
            ),
            context: context,
            monotonicNow: monotonicNow ?? advancingClock(from: 100),
            wallClockNow: wallClockNow ?? advancingWallClock(from: 1_800_000_000),
            automaticallyScheduleTimers: false,
            persistenceAction: persistenceAction
        )
    }

    private func validSamples() -> [TapSample] {
            [
                TapSample(t: 10.0, x: 0, y: 0, target: .left),
                TapSample(t: 10.1, x: 10, y: 0, target: .right),
                TapSample(t: 10.35, x: 0, y: 3, target: .miss),
                TapSample(t: 10.8, x: 10, y: 4, target: .right),
                TapSample(t: 11.4, x: 0, y: 7, target: .left),
                TapSample(t: 12.1, x: 10, y: 9, target: .miss)
            ]
    }
    
    /// A monotonic clock never returns the same value twice across a capture, and the store
    /// rejects a zero-length window, so the fake advances on every read.
    private func advancingClock(
        from start: TimeInterval,
        step: TimeInterval = 20
    ) -> () -> TimeInterval {
        var next = start
        return {
            defer { next += step }
            return next
        }
    }

    private func advancingWallClock(
        from start: TimeInterval,
        step: TimeInterval = 20
    ) -> () -> Date {
        let clock = advancingClock(from: start, step: step)
        return { Date(timeIntervalSince1970: clock()) }
    }
}

