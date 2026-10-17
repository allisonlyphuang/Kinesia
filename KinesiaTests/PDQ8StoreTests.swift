import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class PDQ8StoreTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUpWithError() throws {
        container = try TestCoreDataStack.makeInMemoryContainer()
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func responses(_ values: [PDQ8Response]) -> [PDQ8Item: PDQ8Response] {
        Dictionary(uniqueKeysWithValues: zip(PDQ8Item.allCases, values))
    }

    private var mixedResponses: [PDQ8Item: PDQ8Response] {
        responses([.never, .occasionally, .sometimes, .often, .always, .never, .often, .sometimes])
    }

    // MARK: - Saving

    func testSaveCreatesOneRowWithTheScoreAndTheDay() throws {
        let log = try PDQ8Store.save(
            responses: mixedResponses,
            completedAt: referenceDate,
            in: context,
            calendar: utc
        )

        XCTAssertEqual(log.timestamp, referenceDate.timeIntervalSince1970)
        XCTAssertEqual(log.dayStart, utc.startOfDay(for: referenceDate).timeIntervalSince1970)
        XCTAssertEqual(log.rawSum, 15)
        XCTAssertEqual(log.scoreIndex, 15.0 / 32.0 * 100, accuracy: 1e-9)
        XCTAssertNotNil(log.id)
        XCTAssertEqual(try context.count(for: PDQ8Log.fetchRequest()), 1)
    }

    /// Per-item scores are stored, not just the total: a clinician has to be able to see which
    /// dimension moved.
    func testTheItemScoresRoundTripThroughTheStoredPayload() throws {
        let log = try PDQ8Store.save(responses: mixedResponses, completedAt: referenceDate, in: context, calendar: utc)
        let decoded = try log.decodedScore()

        XCTAssertEqual(decoded.itemScores, [0, 1, 2, 3, 4, 0, 3, 2])
        XCTAssertEqual(decoded.rawSum, 15)
        XCTAssertEqual(decoded.scoreIndex, log.scoreIndex, accuracy: 1e-9)
    }

    func testTheItemScoresSurviveAContextReset() throws {
        _ = try PDQ8Store.save(responses: mixedResponses, completedAt: referenceDate, in: context, calendar: utc)
        context.reset()

        let log = try XCTUnwrap(try PDQ8Store.fetchLatest(in: context))
        XCTAssertEqual(try log.decodedScore().itemScores, [0, 1, 2, 3, 4, 0, 3, 2])
    }

    func testAnIncompleteQuestionnaireWritesNothing() throws {
        var partial = mixedResponses
        partial[.cramps] = nil

        XCTAssertThrowsError(
            try PDQ8Store.save(responses: partial, completedAt: referenceDate, in: context, calendar: utc)
        )
        XCTAssertEqual(try context.count(for: PDQ8Log.fetchRequest()), 0)
    }

    func testANonFiniteCompletionDateIsRejectedAndWritesNothing() throws {
        XCTAssertThrowsError(
            try PDQ8Store.save(
                responses: mixedResponses,
                completedAt: Date(timeIntervalSince1970: .infinity),
                in: context,
                calendar: utc
            )
        ) { error in
            XCTAssertEqual(error as? PDQ8StoreError, .invalidWallClockTimestamp)
        }
        XCTAssertEqual(try context.count(for: PDQ8Log.fetchRequest()), 0)
    }

    func testAMissingPayloadIsReportedRatherThanGuessed() throws {
        let log = PDQ8Log(context: context)
        log.id = UUID()
        log.timestamp = referenceDate.timeIntervalSince1970
        log.itemScores = nil

        XCTAssertThrowsError(try log.decodedScore()) { error in
            XCTAssertEqual(error as? PDQ8StoreError, .missingItemScores)
        }
    }

    // MARK: - Reading back

    func testFetchLogsComesBackNewestFirst() throws {
        for offset in 0..<3 {
            _ = try PDQ8Store.save(
                responses: mixedResponses,
                completedAt: referenceDate.addingTimeInterval(Double(offset) * 86_400),
                in: context,
                calendar: utc
            )
        }

        let logs = try PDQ8Store.fetchLogs(in: context)
        XCTAssertEqual(logs.count, 3)
        XCTAssertEqual(logs.map(\.timestamp), logs.map(\.timestamp).sorted(by: >))
    }

    /// The trend chart plots oldest to newest, so the ranged fetch is deliberately the other way
    /// round from the unordered one.
    func testRangedFetchComesBackOldestFirstAndExcludesTheUpperBound() throws {
        for offset in 0..<3 {
            _ = try PDQ8Store.save(
                responses: mixedResponses,
                completedAt: referenceDate.addingTimeInterval(Double(offset) * 86_400),
                in: context,
                calendar: utc
            )
        }

        let logs = try PDQ8Store.fetchLogs(
            from: referenceDate,
            to: referenceDate.addingTimeInterval(2 * 86_400),
            in: context
        )
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.map(\.timestamp), logs.map(\.timestamp).sorted())
    }

    func testFetchLatestReturnsTheNewest() throws {
        _ = try PDQ8Store.save(responses: mixedResponses, completedAt: referenceDate, in: context, calendar: utc)
        let newest = try PDQ8Store.save(
            responses: responses(Array(repeating: .always, count: 8)),
            completedAt: referenceDate.addingTimeInterval(86_400),
            in: context,
            calendar: utc
        )

        XCTAssertEqual(try PDQ8Store.fetchLatest(in: context), newest)
    }

    func testHasCompletedQuestionnaireFlipsAfterTheFirstSave() throws {
        XCTAssertFalse(try PDQ8Store.hasCompletedQuestionnaire(in: context))
        _ = try PDQ8Store.save(responses: mixedResponses, completedAt: referenceDate, in: context, calendar: utc)
        XCTAssertTrue(try PDQ8Store.hasCompletedQuestionnaire(in: context))
    }
}
