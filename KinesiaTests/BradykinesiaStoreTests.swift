import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class BradykinesiaStoreTests: XCTestCase {
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

    func testSaveCreatesRelatedObjectsAndMapsValidMetrics() throws {
        let trial = validTrial()
        let metrics = BradykinesiaAnalyzer.analyze(trial)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let completedAt = Date(timeIntervalSince1970: 1_800_000_020)

        let saved = try BradykinesiaStore.save(
            trial: trial,
            metrics: metrics,
            startedAt: startedAt,
            completedAt: completedAt,
            in: context
        )
        let fetched = try XCTUnwrap(BradykinesiaStore.fetchLatestResult(in: context))
        let session = try XCTUnwrap(fetched.session)
        let rawCapture = try XCTUnwrap(session.rawCaptures?.allObjects.first as? RawCapture)
        let tapInterStats = try XCTUnwrap(metrics.tapInterStats)
        let leftStats = try XCTUnwrap(metrics.driftLeftStats)
        let rightStats = try XCTUnwrap(metrics.driftRightStats)

        XCTAssertEqual(fetched.id, saved.id)
        XCTAssertEqual(try context.count(for: TestSession.fetchRequest()), 1)
        XCTAssertEqual(try context.count(for: BradykinesiaResult.fetchRequest()), 1)
        XCTAssertEqual(try context.count(for: RawCapture.fetchRequest()), 1)
        XCTAssertEqual(fetched.numTaps, Int32(metrics.numTaps))
        XCTAssertTrue(fetched.isValid)
        XCTAssertNil(fetched.invalidReason)
        XCTAssertNotNil(fetched.id)
        XCTAssertNotNil(session.id)
        XCTAssertNotNil(rawCapture.id)
        XCTAssertEqual(session.startedAt, startedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(session.completedAt, completedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(fetched.timestamp, completedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(fetched.dayStart, Calendar.current.startOfDay(for: completedAt).timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(rawCapture.session?.id, session.id)
        assertStoredStats(
            tapInterStats,
            min: fetched.tapInterMin,
            max: fetched.tapInterMax,
            mean: fetched.tapInterMean,
            median: fetched.tapInterMedian,
            p25: fetched.tapInterP25,
            p75: fetched.tapInterP75,
            stdev: fetched.tapInterStdev
        )
        XCTAssertEqual(fetched.tapInterSkew, try XCTUnwrap(metrics.skewTapInter), accuracy: 0.000_001)
        assertStoredStats(
            leftStats,
            min: fetched.driftLeftMin,
            max: fetched.driftLeftMax,
            mean: fetched.driftLeftMean,
            median: fetched.driftLeftMedian,
            p25: fetched.driftLeftP25,
            p75: fetched.driftLeftP75,
            stdev: fetched.driftLeftStdev
        )
        XCTAssertEqual(fetched.driftLeftSkew, try XCTUnwrap(metrics.skewDriftLeft), accuracy: 0.000_001)
        assertStoredStats(
            rightStats,
            min: fetched.driftRightMin,
            max: fetched.driftRightMax,
            mean: fetched.driftRightMean,
            median: fetched.driftRightMedian,
            p25: fetched.driftRightP25,
            p75: fetched.driftRightP75,
            stdev: fetched.driftRightStdev
        )
        XCTAssertEqual(fetched.driftRightSkew, try XCTUnwrap(metrics.skewDriftRight), accuracy: 0.000_001)
        XCTAssertEqual(fetched.corXY, try XCTUnwrap(metrics.corXY), accuracy: 0.000_001)
    }

    func testRawCaptureRoundTripPreservesEveryTapAndTrialField() throws {
        let trial = validTrial()
        let completedAt = Date(timeIntervalSince1970: 1_800_100_020)
        _ = try BradykinesiaStore.save(
            trial: trial,
            metrics: BradykinesiaAnalyzer.analyze(trial),
            startedAt: Date(timeIntervalSince1970: 1_800_100_000),
            completedAt: completedAt,
            in: context
        )

        let request = RawCapture.fetchRequest()
        let rawCapture = try XCTUnwrap(context.fetch(request).first)
        let payload = try XCTUnwrap(rawCapture.payload)
        let decoded = try JSONDecoder().decode(TapTrial.self, from: payload)

        XCTAssertEqual(rawCapture.kind, BradykinesiaStore.rawCaptureKind)
        XCTAssertEqual(rawCapture.schemaVersion, BradykinesiaStore.rawCaptureSchemaVersion)
        XCTAssertEqual(rawCapture.timestamp, completedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(decoded.samples.map(\.t), trial.samples.map(\.t))
        XCTAssertEqual(decoded.samples.map(\.x), trial.samples.map(\.x))
        XCTAssertEqual(decoded.samples.map(\.y), trial.samples.map(\.y))
        assertTargets(decoded.samples.map(\.target))
        XCTAssertEqual(decoded.leftCenter.x, trial.leftCenter.x, accuracy: 0.000_001)
        XCTAssertEqual(decoded.leftCenter.y, trial.leftCenter.y, accuracy: 0.000_001)
        XCTAssertEqual(decoded.rightCenter.x, trial.rightCenter.x, accuracy: 0.000_001)
        XCTAssertEqual(decoded.rightCenter.y, trial.rightCenter.y, accuracy: 0.000_001)
        XCTAssertEqual(decoded.targetRadius, trial.targetRadius, accuracy: 0.000_001)
        XCTAssertEqual(decoded.startedAt, trial.startedAt, accuracy: 0.000_001)
        XCTAssertEqual(decoded.hand, trial.hand)
        XCTAssertEqual(decoded.screenScale, trial.screenScale, accuracy: 0.000_001)
    }

    func testUnavailableMetricsPersistWithExplicitInvalidityAndRawTrial() throws {
        let trial = TapTrial(
            samples: [TapSample(t: 12.5, x: 40, y: 80, target: .miss)],
            leftCenter: TapPoint(x: 20, y: 40),
            rightCenter: TapPoint(x: 100, y: 40),
            targetRadius: 24,
            startedAt: 12,
            hand: "left",
            screenScale: 3
        )
        let metrics = BradykinesiaAnalyzer.analyze(trial)
        let result = try BradykinesiaStore.save(
            trial: trial,
            metrics: metrics,
            startedAt: Date(timeIntervalSince1970: 1_800_200_000),
            completedAt: Date(timeIntervalSince1970: 1_800_200_020),
            in: context
        )
        let rawCapture = try XCTUnwrap(result.session?.rawCaptures?.allObjects.first as? RawCapture)
        let decoded = try JSONDecoder().decode(TapTrial.self, from: try XCTUnwrap(rawCapture.payload))

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(try XCTUnwrap(result.invalidReason).contains("tap interval statistics unavailable"))
        XCTAssertEqual(result.tapInterMean, 0, accuracy: 0.000_001)
        XCTAssertEqual(result.driftLeftMean, 0, accuracy: 0.000_001)
        XCTAssertEqual(result.driftRightMean, 0, accuracy: 0.000_001)
        XCTAssertEqual(result.corXY, 0, accuracy: 0.000_001)
        XCTAssertEqual(decoded.samples.count, 1)
        XCTAssertEqual(decoded.samples[0].t, 12.5, accuracy: 0.000_001)
        XCTAssertEqual(decoded.samples[0].x, 40, accuracy: 0.000_001)
        XCTAssertEqual(decoded.samples[0].y, 80, accuracy: 0.000_001)
        guard case .miss = decoded.samples[0].target else {
            return XCTFail("Raw target classification was not preserved")
        }
    }

    func testNonFiniteMetricIsPersistedAsAnInvalidPlaceholderRatherThanNaN() throws {
        let trial = validTrial()
        var metrics = BradykinesiaAnalyzer.analyze(trial)
        metrics.corXY = .nan

        let result = try BradykinesiaStore.save(
            trial: trial,
            metrics: metrics,
            startedAt: Date(timeIntervalSince1970: 1_800_250_000),
            completedAt: Date(timeIntervalSince1970: 1_800_250_020),
            in: context
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(try XCTUnwrap(result.invalidReason).contains("x/y correlation unavailable"))
        XCTAssertEqual(result.corXY, 0, accuracy: 0.000_001)
        XCTAssertTrue(result.corXY.isFinite)
    }

    func testFetchResultsOrdersByExplicitWallClockTimeAndSurvivesContextReset() throws {
        let trial = validTrial()
        let metrics = BradykinesiaAnalyzer.analyze(trial)
        let older = try BradykinesiaStore.save(
            trial: trial,
            metrics: metrics,
            startedAt: Date(timeIntervalSince1970: 1_800_300_000),
            completedAt: Date(timeIntervalSince1970: 1_800_300_020),
            in: context
        )
        let newer = try BradykinesiaStore.save(
            trial: trial,
            metrics: metrics,
            startedAt: Date(timeIntervalSince1970: 1_800_400_000),
            completedAt: Date(timeIntervalSince1970: 1_800_400_020),
            in: context
        )
        let olderID = older.id
        let newerID = newer.id

        XCTAssertEqual(try BradykinesiaStore.fetchResults(in: context).map(\.id), [newerID, olderID])

        context.reset()
        let refetched = try BradykinesiaStore.fetchResults(in: context)
        XCTAssertEqual(refetched.map(\.id), [newerID, olderID])
        XCTAssertEqual(try XCTUnwrap(refetched.first?.session?.rawCaptures?.count), 1)
        XCTAssertEqual(try XCTUnwrap(refetched.first?.numTaps), Int32(trial.samples.count))
    }

    private func validTrial() -> TapTrial {
        TapTrial(
            samples: [
                TapSample(t: 10.0, x: 0, y: 0, target: .left),
                TapSample(t: 10.1, x: 10, y: 0, target: .right),
                TapSample(t: 10.35, x: 0, y: 3, target: .miss),
                TapSample(t: 10.8, x: 10, y: 4, target: .right),
                TapSample(t: 11.4, x: 0, y: 7, target: .left),
                TapSample(t: 12.1, x: 10, y: 9, target: .miss)
            ],
            leftCenter: TapPoint(x: 20, y: 40),
            rightCenter: TapPoint(x: 100, y: 40),
            targetRadius: 24,
            startedAt: 10,
            hand: "right",
            screenScale: 3
        )
    }

    private func assertTargets(_ targets: [TapTarget], file: StaticString = #filePath, line: UInt = #line) {
        guard case [.left, .right, .miss, .right, .left, .miss] = targets else {
            XCTFail("Tap target classifications did not round-trip", file: file, line: line)
            return
        }
    }

    private func assertStoredStats(
        _ expected: SummaryStats,
        min: Double,
        max: Double,
        mean: Double,
        median: Double,
        p25: Double,
        p75: Double,
        stdev: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(min, expected.min, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(max, expected.max, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(mean, expected.mean, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(median, expected.median, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(p25, expected.p25, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(p75, expected.p75, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(stdev, expected.stdev, accuracy: 0.000_001, file: file, line: line)
    }
}
