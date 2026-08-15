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

    func testPhaseTransitionsAreDeterministicWithoutSleeping() {
        let model = makeModel(countdownSeconds: 2)

        XCTAssertEqual(model.phase, .ready)
        model.start()
        XCTAssertEqual(model.phase, .countdown)
        XCTAssertEqual(model.secondsRemaining, 2)

        model.countdownTick()
        XCTAssertEqual(model.phase, .countdown)
        XCTAssertEqual(model.secondsRemaining, 1)

        model.countdownTick()
        XCTAssertEqual(model.phase, .running)
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
        assertTargets(model.capturedSamples.map(\.target), expected: [.left, .miss, .right])

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
            monotonicNow: { 345.25 },
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
        assertTargets(decoded.samples.map(\.target), expected: [.left, .right, .miss, .right, .left, .miss])
        XCTAssertEqual(decoded.leftCenter.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(decoded.rightCenter.x, 10, accuracy: 0.000_001)
        XCTAssertEqual(decoded.targetRadius, 3, accuracy: 0.000_001)
        XCTAssertEqual(decoded.startedAt, 345.25, accuracy: 0.000_001)
        XCTAssertEqual(decoded.hand, "right")
        XCTAssertEqual(decoded.screenScale, 3, accuracy: 0.000_001)
    }

    func testActiveStartAndDuplicateCompletionCreateOnlyOnePersistedSession() throws {
        let model = makeModel(countdownSeconds: 1)

        model.start()
        model.start()
        XCTAssertEqual(model.phase, .countdown)
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
            persistenceAction: { _, _, _, _, _ in throw ExpectedError.saveFailed }
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
            hand: "right",
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
            hand: "left",
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
        XCTAssertNil(model.metrics)
    }

    private func makeModel(
        countdownSeconds: Int,
        monotonicNow: @escaping () -> TimeInterval = { 100 },
        wallClockNow: @escaping () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) },
        persistenceAction: BradykinesiaTestModel.PersistenceAction? = nil
    ) -> BradykinesiaTestModel {
        BradykinesiaTestModel(
            configuration: BradykinesiaTestConfiguration(
                leftCenter: TapPoint(x: 0, y: 0),
                rightCenter: TapPoint(x: 10, y: 0),
                targetRadius: 3,
                hand: "right",
                screenScale: 3,
                countdownSeconds: countdownSeconds,
                captureDuration: 20
            ),
            context: context,
            monotonicNow: monotonicNow,
            wallClockNow: wallClockNow,
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

    private func assertTargets(
        _ actual: [TapTarget],
        expected: [TapTarget],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualTarget, expectedTarget) in zip(actual, expected) {
            switch (actualTarget, expectedTarget) {
            case (.left, .left), (.right, .right), (.miss, .miss):
                break
            default:
                XCTFail("Tap target classification changed", file: file, line: line)
            }
        }
    }
}
