import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class AkinesiaStoreTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        // One shared model for the whole target; see TestCoreDataStack.
        container = try TestCoreDataStack.makeInMemoryContainer()
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private var referenceDayStart: TimeInterval {
        Calendar.current
            .startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
            .timeIntervalSince1970
    }

    /// One caught round. Monotonic times, spaced so they never overlap between rounds.
    private func completedRound(
        index: Int,
        isPractice: Bool = false,
        reactionTime: Double,
        movementTime: Double = 0.25
    ) -> RoundRecord {
        let cue = 100.0 + Double(index) * 5
        let lift = cue + reactionTime
        let caught = lift + movementTime
        return RoundRecord(
            index: index,
            isPractice: isPractice,
            homeSettledAt: cue - 2,
            plannedForeperiod: 2,
            cueOnsetAt: cue,
            liftOffAt: lift,
            catchAt: caught,
            returnedHomeAt: caught + 0.5,
            spawn: SpawnPoint(x: 150, y: 50),
            captureOutcome: .completed,
            scoredOutcome: .valid
        )
    }

    private func abortedRound(index: Int, outcome: CaptureOutcome) -> RoundRecord {
        RoundRecord(
            index: index,
            isPractice: false,
            homeSettledAt: 100 + Double(index) * 5,
            plannedForeperiod: 2,
            cueOnsetAt: outcome == .missed ? 102 + Double(index) * 5 : nil,
            liftOffAt: outcome == .missed ? nil : 101 + Double(index) * 5,
            catchAt: nil,
            returnedHomeAt: nil,
            spawn: outcome == .missed ? SpawnPoint(x: 150, y: 50) : nil,
            captureOutcome: outcome,
            scoredOutcome: .valid
        )
    }

    private func trial(_ rounds: [RoundRecord]) -> AkinesiaTrial {
        AkinesiaTrial(
            rounds: rounds,
            homeBaseCenter: SpawnPoint(x: 150, y: 150),
            homeBaseRadius: 40,
            fireflyRadius: 30,
            hand: .right,
            screenScale: 3,
            refreshRateHz: 120,
            startedAt: 95,
            spawnRing: SpawnRing(
                center: TapPoint(x: 150, y: 150),
                radius: 100,
                tolerance: 8,
                arcStart: 0,
                arcEnd: 2 * .pi
            )
        )
    }

    /// Nine clean rounds with spread reaction times, so the session clears `minimumValidRounds`
    /// and every statistic is a distinct number rather than a coincidence.
    private func validTrial() -> AkinesiaTrial {
        trial((0..<9).map { completedRound(index: $0, reactionTime: 0.30 + Double($0) * 0.02) })
    }

    private func makeAttempt(
        trial: AkinesiaTrial,
        metrics: AkinesiaMetrics? = nil,
        startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        completedAt: Date = Date(timeIntervalSince1970: 1_800_000_060),
        monotonicCompletedAt: TimeInterval = 160
    ) -> AkinesiaAttempt {
        AkinesiaAttempt(
            trial: trial,
            metrics: metrics ?? AkinesiaAnalyzer.analyze(trial),
            startedAt: startedAt,
            completedAt: completedAt,
            monotonicCompletedAt: monotonicCompletedAt,
            device: AkinesiaDeviceIdentity(model: "iPhone", systemVersion: "26.5")
        )
    }

    /// The row existing in the context is the point; the return value is a convenience for the
    /// one test that needs to identify it afterwards. Matches `BradykinesiaStoreTests`.
    @discardableResult
    private func makeMedicationLog(at timestamp: TimeInterval, wasSkipped: Bool = false) -> MedicationLog {
        let log = MedicationLog(context: context)
        log.id = UUID()
        log.timestamp = timestamp
        log.dayStart = Calendar.current
            .startOfDay(for: Date(timeIntervalSince1970: timestamp))
            .timeIntervalSince1970
        log.wasSkipped = wasSkipped
        return log
    }

    // MARK: - The happy path

    func testSaveCreatesExactlyOneSessionOneResultAndOneRawCapture() throws {
        let saved = try AkinesiaStore.save(attempt: makeAttempt(trial: validTrial()), in: context)

        XCTAssertEqual(try context.count(for: TestSession.fetchRequest()), 1)
        XCTAssertEqual(try context.count(for: AkinesiaResult.fetchRequest()), 1)
        XCTAssertEqual(try context.count(for: RawCapture.fetchRequest()), 1)

        let result = try XCTUnwrap(saved.akinesia)
        XCTAssertEqual(result.session?.id, saved.id)
        XCTAssertEqual(result.hand, "right")
        XCTAssertEqual(result.metricsVersion, Int16(AkinesiaMetrics.metricsVersion))
    }

    func testTheRawCaptureIsLabelledAkinesiaAndCarriesThePayload() throws {
        let saved = try AkinesiaStore.save(attempt: makeAttempt(trial: validTrial()), in: context)
        let capture = try XCTUnwrap(saved.rawCaptures?.allObjects.first as? RawCapture)

        XCTAssertEqual(capture.kind, AkinesiaStore.rawCaptureKind)
        XCTAssertEqual(capture.schemaVersion, AkinesiaStore.rawCaptureSchemaVersion)
        XCTAssertNotNil(capture.payload)
    }

    func testTheRawPayloadRoundTripsToAnIdenticalTrial() throws {
        // Recomputability depends on this: when a threshold changes, old sessions are re-scored
        // from this payload. If it does not decode, they are frozen under the old rules forever.
        let original = validTrial()
        let saved = try AkinesiaStore.save(attempt: makeAttempt(trial: original), in: context)
        let capture = try XCTUnwrap(saved.rawCaptures?.allObjects.first as? RawCapture)
        let payload = try XCTUnwrap(capture.payload)

        let decoded = try JSONDecoder().decode(AkinesiaTrial.self, from: payload)

        XCTAssertEqual(decoded.rounds.count, original.rounds.count)
        XCTAssertEqual(decoded.hand, original.hand)
        XCTAssertEqual(decoded.refreshRateHz, original.refreshRateHz)
        XCTAssertEqual(decoded.spawnRing.radius, original.spawnRing.radius)
        XCTAssertEqual(decoded.rounds.first?.cueOnsetAt, original.rounds.first?.cueOnsetAt)
        XCTAssertEqual(decoded.rounds.first?.liftOffAt, original.rounds.first?.liftOffAt)
        XCTAssertEqual(decoded.rounds.last?.catchAt, original.rounds.last?.catchAt)
    }

    // MARK: - Column coverage

    func testEveryReactionTimeStatisticIsWritten() throws {
        // Fifteen near-identical assignment lines is exactly the shape of code where one gets
        // missed, and a missed line is invisible: the column just stays zero forever.
        let trial = validTrial()
        let metrics = AkinesiaAnalyzer.analyze(trial)
        let stats = try XCTUnwrap(metrics.reactionTimeStats)

        let saved = try AkinesiaStore.save(attempt: makeAttempt(trial: trial, metrics: metrics), in: context)
        let result = try XCTUnwrap(saved.akinesia)

        XCTAssertEqual(result.reactionTimeMin, stats.min, accuracy: 0.000_001)
        XCTAssertEqual(result.reactionTimeMax, stats.max, accuracy: 0.000_001)
        XCTAssertEqual(result.reactionTimeMean, stats.mean, accuracy: 0.000_001)
        XCTAssertEqual(result.reactionTimeMedian, stats.median, accuracy: 0.000_001)
        XCTAssertEqual(result.reactionTimeP25, stats.p25, accuracy: 0.000_001)
        XCTAssertEqual(result.reactionTimeP75, stats.p75, accuracy: 0.000_001)
        XCTAssertEqual(result.reactionTimeP90, stats.p90, accuracy: 0.000_001)
        XCTAssertEqual(result.reactionTimeStdev, stats.stdev, accuracy: 0.000_001)
        XCTAssertEqual(result.reactionTimeMAD, stats.mad, accuracy: 0.000_001)
    }

    func testEveryMovementTimeStatisticIsWritten() throws {
        let trial = validTrial()
        let metrics = AkinesiaAnalyzer.analyze(trial)
        let stats = try XCTUnwrap(metrics.movementTimeStats)

        let saved = try AkinesiaStore.save(attempt: makeAttempt(trial: trial, metrics: metrics), in: context)
        let result = try XCTUnwrap(saved.akinesia)

        XCTAssertEqual(result.movementTimeMin, stats.min, accuracy: 0.000_001)
        XCTAssertEqual(result.movementTimeMax, stats.max, accuracy: 0.000_001)
        XCTAssertEqual(result.movementTimeMean, stats.mean, accuracy: 0.000_001)
        XCTAssertEqual(result.movementTimeMedian, stats.median, accuracy: 0.000_001)
        XCTAssertEqual(result.movementTimeP25, stats.p25, accuracy: 0.000_001)
        XCTAssertEqual(result.movementTimeP75, stats.p75, accuracy: 0.000_001)
        XCTAssertEqual(result.movementTimeStdev, stats.stdev, accuracy: 0.000_001)
        XCTAssertEqual(result.movementTimeMAD, stats.mad, accuracy: 0.000_001)
    }

    func testEveryCountIsPersistedExactly() throws {
        let rounds = [
            completedRound(index: 0, isPractice: true, reactionTime: 0.35),
            completedRound(index: 1, reactionTime: 0.30),
            completedRound(index: 2, reactionTime: 0.34),
            completedRound(index: 3, reactionTime: 0.05),   // anticipation
            completedRound(index: 4, reactionTime: 3.00),   // lapse
            abortedRound(index: 5, outcome: .falseStart),
            abortedRound(index: 6, outcome: .slip),
            abortedRound(index: 7, outcome: .missed)
        ]
        let trial = trial(rounds)
        let metrics = AkinesiaAnalyzer.analyze(trial)

        let saved = try AkinesiaStore.save(attempt: makeAttempt(trial: trial, metrics: metrics), in: context)
        let result = try XCTUnwrap(saved.akinesia)

        XCTAssertEqual(result.numRounds, Int32(metrics.numRounds))
        XCTAssertEqual(result.numPracticeRounds, Int32(metrics.numPracticeRounds))
        XCTAssertEqual(result.numValidRounds, Int32(metrics.numValidRounds))
        XCTAssertEqual(result.numAnticipations, Int32(metrics.numAnticipations))
        XCTAssertEqual(result.numLapses, Int32(metrics.numLapses))
        XCTAssertEqual(result.numFalseStarts, Int32(metrics.numFalseStarts))
        XCTAssertEqual(result.numSlips, Int32(metrics.numSlips))
        XCTAssertEqual(result.numMissed, Int32(metrics.numMissed))
        XCTAssertEqual(result.numMalformed, Int32(metrics.numMalformed))

        // A count of zero here is a real zero, never a placeholder: counts are always computable.
        XCTAssertEqual(result.numMalformed, 0)
        XCTAssertEqual(result.numPracticeRounds, 1)
    }

    func testSessionBoundsAndDayStartAreWritten() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let completedAt = Date(timeIntervalSince1970: 1_800_000_060)
        let attempt = makeAttempt(trial: validTrial(), startedAt: startedAt, completedAt: completedAt)

        let saved = try AkinesiaStore.save(attempt: attempt, in: context)

        XCTAssertEqual(saved.startedAt, startedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(saved.completedAt, completedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(saved.dayStart, referenceDayStart, accuracy: 0.000_001)
        XCTAssertEqual(saved.akinesia?.timestamp, completedAt.timeIntervalSince1970)
    }

    // MARK: - Validation
    private func assertRejected(
        _ attempt: AkinesiaAttempt,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try AkinesiaStore.save(attempt: attempt, in: context), file: file, line: line)
        XCTAssertTrue(
            context.registeredObjects.isEmpty,
            "a rejected attempt left objects in the shared context",
            file: file,
            line: line
        )
        XCTAssertEqual(try? context.count(for: TestSession.fetchRequest()), 0, file: file, line: line)
    }

    func testASessionWithNoRoundsIsRejected() {
        assertRejected(makeAttempt(trial: trial([])))
    }

    func testMetricsFromADifferentTrialAreRejected() {
        // Metrics computed from nine rounds, handed a trial of three.
        let metrics = AkinesiaAnalyzer.analyze(validTrial())
        let shortTrial = trial((0..<3).map { completedRound(index: $0, reactionTime: 0.3) })
        assertRejected(makeAttempt(trial: shortTrial, metrics: metrics))
    }

    func testOutcomeCountsThatDoNotSumAreRejected() {
        var metrics = AkinesiaAnalyzer.analyze(validTrial())
        metrics.numValidRounds += 1   // the seven counts no longer partition numRounds
        assertRejected(makeAttempt(trial: validTrial(), metrics: metrics))
    }

    func testANonPositiveSessionDurationIsRejected() {
        // monotonicCompletedAt at or before the trial start means a broken clock.
        assertRejected(makeAttempt(trial: validTrial(), monotonicCompletedAt: 95))
    }

    func testANonFiniteWallClockIsRejected() {
        assertRejected(
            makeAttempt(trial: validTrial(), startedAt: Date(timeIntervalSince1970: .infinity))
        )
    }

    // MARK: - Medication context

    func testTheMostRecentDoseTakenBeforeTheSessionIsLinked() throws {
        let dayStart = referenceDayStart
        makeMedicationLog(at: dayStart + 6 * 3600)
        let expected = makeMedicationLog(at: dayStart + 8 * 3600)
        makeMedicationLog(at: dayStart + 20 * 3600)   // after the session
        try context.save()

        let attempt = makeAttempt(
            trial: validTrial(),
            startedAt: Date(timeIntervalSince1970: dayStart + 9 * 3600),
            completedAt: Date(timeIntervalSince1970: dayStart + 9 * 3600 + 60)
        )
        let saved = try AkinesiaStore.save(attempt: attempt, in: context)

        XCTAssertEqual(saved.medicationContext?.id, expected.id)
        XCTAssertEqual(saved.minutesSinceDose, 60, accuracy: 0.000_001)
    }

    func testSkippedDosesAreIgnored() throws {
        let dayStart = referenceDayStart
        makeMedicationLog(at: dayStart + 8 * 3600, wasSkipped: true)
        try context.save()

        let attempt = makeAttempt(
            trial: validTrial(),
            startedAt: Date(timeIntervalSince1970: dayStart + 9 * 3600),
            completedAt: Date(timeIntervalSince1970: dayStart + 9 * 3600 + 60)
        )
        let saved = try AkinesiaStore.save(attempt: attempt, in: context)

        XCTAssertNil(saved.medicationContext, "a skipped dose never entered the body")
    }

    func testDosesFromThePreviousDayAreIgnored() throws {
        let dayStart = referenceDayStart
        makeMedicationLog(at: dayStart - 2 * 3600)
        try context.save()

        let attempt = makeAttempt(
            trial: validTrial(),
            startedAt: Date(timeIntervalSince1970: dayStart + 9 * 3600),
            completedAt: Date(timeIntervalSince1970: dayStart + 9 * 3600 + 60)
        )
        let saved = try AkinesiaStore.save(attempt: attempt, in: context)

        XCTAssertNil(saved.medicationContext)
    }

    func testNoQualifyingDoseLeavesTheContextNilAndMinutesAtPlaceholderZero() throws {
        let saved = try AkinesiaStore.save(attempt: makeAttempt(trial: validTrial()), in: context)

        XCTAssertNil(saved.medicationContext)
        // The zero is a schema placeholder, not "took a dose zero minutes ago". medicationContext
        // being nil is the only thing that says the number means nothing.
        XCTAssertEqual(saved.minutesSinceDose, 0, accuracy: 0.000_001)
    }

    // MARK: - Unavailable statistics

    func testTooFewValidRoundsPersistAsInvalidWithAReason() throws {
        // Below `minimumValidRounds` the analyzer returns nil statistics. The columns are required,
        // so they take placeholder zeros and isValid records that they mean nothing.
        let shortTrial = trial((0..<3).map { completedRound(index: $0, reactionTime: 0.3) })
        let metrics = AkinesiaAnalyzer.analyze(shortTrial)
        XCTAssertNil(metrics.reactionTimeStats, "fixture should be under the minimum")

        let saved = try AkinesiaStore.save(attempt: makeAttempt(trial: shortTrial, metrics: metrics), in: context)
        let result = try XCTUnwrap(saved.akinesia)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.reactionTimeMedian, 0, "placeholder, not a measured zero")
        let reason = try XCTUnwrap(result.invalidReason)
        XCTAssertTrue(reason.contains("reaction time"))

        // The counts are still real, which is the point of recording them separately.
        XCTAssertEqual(result.numRounds, 3)
        XCTAssertEqual(result.numValidRounds, 3)
    }

    func testACompleteSessionIsMarkedValidWithNoReason() throws {
        let saved = try AkinesiaStore.save(attempt: makeAttempt(trial: validTrial()), in: context)
        let result = try XCTUnwrap(saved.akinesia)

        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.invalidReason)
    }

    // MARK: - Reading back

    func testFetchLatestResultReturnsTheNewestByWallClock() throws {
        try AkinesiaStore.save(
            attempt: makeAttempt(
                trial: validTrial(),
                startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                completedAt: Date(timeIntervalSince1970: 1_800_000_060)
            ),
            in: context
        )
        let newer = makeAttempt(
            trial: validTrial(),
            startedAt: Date(timeIntervalSince1970: 1_800_003_000),
            completedAt: Date(timeIntervalSince1970: 1_800_003_060)
        )
        try AkinesiaStore.save(attempt: newer, in: context)

        let latest = try XCTUnwrap(AkinesiaStore.fetchLatestResult(in: context))
        XCTAssertEqual(latest.timestamp, newer.completedAt.timeIntervalSince1970, accuracy: 0.000_001)
    }

    func testFetchLatestResultIsNilOnAnEmptyStore() throws {
        XCTAssertNil(try AkinesiaStore.fetchLatestResult(in: context))
    }

    func testFetchResultsIsNewestFirst() throws {
        try AkinesiaStore.save(
            attempt: makeAttempt(
                trial: validTrial(),
                startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                completedAt: Date(timeIntervalSince1970: 1_800_000_060)
            ),
            in: context
        )
        try AkinesiaStore.save(
            attempt: makeAttempt(
                trial: validTrial(),
                startedAt: Date(timeIntervalSince1970: 1_800_003_000),
                completedAt: Date(timeIntervalSince1970: 1_800_003_060)
            ),
            in: context
        )

        let results = try AkinesiaStore.fetchResults(in: context)
        XCTAssertEqual(results.count, 2)
        XCTAssertGreaterThan(results[0].timestamp, results[1].timestamp)
    }

    func testHasCompletedSessionIsFalseThenTrue() throws {
        XCTAssertFalse(try AkinesiaStore.hasCompletedSession(in: context))
        try AkinesiaStore.save(attempt: makeAttempt(trial: validTrial()), in: context)
        XCTAssertTrue(try AkinesiaStore.hasCompletedSession(in: context))
    }

    func testHasCompletedSessionCountsSessionsThatWereNotScored() throws {
        // Someone who played but produced too few clean rounds has still seen the game, so
        // practice should not be offered to them again.
        let shortTrial = trial((0..<3).map { completedRound(index: $0, reactionTime: 0.3) })
        try AkinesiaStore.save(attempt: makeAttempt(trial: shortTrial), in: context)

        XCTAssertFalse(try XCTUnwrap(AkinesiaStore.fetchLatestResult(in: context)).isValid)
        XCTAssertTrue(try AkinesiaStore.hasCompletedSession(in: context))
    }

    // MARK: - Context reset

    func testASavedSessionSurvivesAContextReset() throws {
        let saved = try AkinesiaStore.save(attempt: makeAttempt(trial: validTrial()), in: context)
        let id = try XCTUnwrap(saved.id)   // Core Data generates `id` as UUID?
        context.reset()

        let request = TestSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let refetched = try XCTUnwrap(try context.fetch(request).first)

        XCTAssertNotNil(refetched.akinesia)
        XCTAssertEqual(refetched.akinesia?.numRounds, 9)
    }
}
